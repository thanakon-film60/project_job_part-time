import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../models/camera.dart';

/// ข้อผิดพลาดที่มีข้อความไทยพร้อมโชว์ให้ผู้ใช้แล้ว
///
/// แยกจาก Exception ทั่วไปเพราะ error ของ SDK เป็นตัวเลขล้วน ถ้าโยนดิบ ๆ
/// ขึ้นจอผู้ใช้จะเห็นแค่ `error -10403` ซึ่งบอกอะไรไม่ได้เลย
class TalkbackException implements Exception {
  final String message;

  const TalkbackException(this.message);

  @override
  String toString() => message;
}

/// สายที่เปิดค้างไว้ 1 สาย พร้อมไมค์ที่ผูกกับ stream ปลายทางแล้ว
///
/// แยกขั้น "เปิดสาย" กับ "เริ่มส่งเสียง" ออกจากกัน เพื่อให้ผู้เรียกมีจังหวะ
/// เช็คว่าผู้ใช้ยังกดปุ่มค้างอยู่ไหมก่อนเปิดไมค์จริง
abstract class TalkbackLink {
  /// สายหลุดเองระหว่างพูด (เน็ตหาย/กล้องตัด) — ไม่ใช่ตอนที่เราสั่งปิด
  set onDropped(void Function(String message)? handler);

  /// เริ่มส่งเสียงไมค์เข้า stream ที่ผูกไว้
  Future<void> startMic();

  /// ปิดให้ขาดทุกชั้น — ต้องเรียกซ้ำได้และห้าม throw
  Future<void> close();
}

/// ตัวกลางไปยัง TiRTC SDK — มีไว้เพื่อ fake ในเทสต์
///
/// widget test เรียก native TiRTC ไม่ได้ (ไม่มี native runtime ให้โหลด)
/// ตรรกะยกเลิก/cleanup จึงต้องเทสต์ผ่าน interface นี้แทน
abstract class TalkbackEngine {
  /// เปิดสาย รอจนต่อติด แล้วผูกไมค์รอไว้ — ยังไม่ส่งเสียงออก
  ///
  /// โยน [TalkbackException] ถ้าต่อไม่ติดภายใน [timeout] และต้องเก็บกวาด
  /// ของที่สร้างไปแล้วให้เรียบร้อยก่อนโยน
  Future<TalkbackLink> open(
    CameraTalkbackSession session, {
    required Duration timeout,
  });
}

// ---------------------------------------------------------------------------
// ตัวจริงที่คุยกับ TiRTC SDK
// ---------------------------------------------------------------------------

class _TiRtcLink implements TalkbackLink {
  _TiRtcLink(this._conn, this._mic);

  final TiRtcConn _conn;
  final TiRtcAudioInput _mic;

  @override
  void Function(String message)? onDropped;

  bool _closed = false;

  @override
  Future<void> startMic() async {
    if (_closed) throw const TalkbackException('สายถูกปิดไปแล้ว');
    final int code = await _mic.start();
    if (code != 0) {
      throw TalkbackException('เปิดไมค์ไม่สำเร็จ (${TiRtc.errorToString(code)})');
    }
  }

  /// ลำดับปิดต้องเป็น stop → detach → dispose ไมค์ → disconnect → dispose สาย
  /// สลับลำดับแล้ว SDK จะคืน in-use error และทรัพยากรค้าง
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // ตัด callback ก่อน กันไม่ให้การปิดที่เราตั้งใจไปเด้ง onDropped
    onDropped = null;
    _conn.onStateChanged = null;
    _mic.onError = null;

    // แต่ละขั้นห้ามล้มทั้งชุด — ถ้าขั้นแรกพัง ขั้นที่เหลือยังต้องได้ทำ
    // ไม่งั้นไมค์หรือสายจะค้างจนกดพูดรอบหน้าไม่ได้
    await _quietly(() => _mic.stop());
    await _quietly(() => _mic.detach(connection: _conn));
    await _quietly(() => _mic.dispose());
    await _quietly(() async => _conn.disconnect());
    await _quietly(() async => _conn.dispose());
  }

  static Future<void> _quietly(Future<Object?> Function() step) async {
    try {
      await step();
    } catch (err) {
      // ปิดไม่สำเร็จบางขั้นไม่ใช่เรื่องคอขาดบาดตาย รอบหน้าสร้างใหม่หมดอยู่แล้ว
      debugPrint('talkback cleanup step failed: $err');
    }
  }
}

class TiRtcTalkbackEngine implements TalkbackEngine {
  const TiRtcTalkbackEngine();

  @override
  Future<TalkbackLink> open(
    CameraTalkbackSession session, {
    required Duration timeout,
  }) async {
    // initialize สั้นวงจรเองถ้าเคยเรียกแล้ว จึงเรียกซ้ำทุกรอบได้ไม่เปลือง
    final int initCode = await TiRtc.initialize(
      TiRtcInitOptions(appId: session.appId),
    );
    if (initCode != 0) {
      throw TalkbackException(
        'เริ่มระบบเสียงไม่ได้ (${TiRtc.errorToString(initCode)})',
      );
    }

    final TiRtcConn conn = TiRtcConn();
    final Completer<void> connected = Completer<void>();
    _TiRtcLink? link;

    conn.onStateChanged = (TiRtcConnState state, int errorCode) {
      switch (state) {
        case TiRtcConnState.connected:
          if (!connected.isCompleted) connected.complete();
        case TiRtcConnState.disconnected:
          final String reason = errorCode == 0
              ? 'ปลายทางตัดสาย'
              : TiRtc.errorToString(errorCode);
          if (!connected.isCompleted) {
            connected.completeError(
              TalkbackException('ต่อไปยังกล้องไม่สำเร็จ ($reason)'),
            );
          } else {
            link?.onDropped?.call('สายพูดหลุด ($reason) — กดพูดใหม่ได้');
          }
        case TiRtcConnState.idle:
        case TiRtcConnState.connecting:
          break;
      }
    };

    final int connectCode = conn.connect(
      remoteId: session.remoteId,
      token: session.token,
    );
    if (connectCode != 0) {
      conn.onStateChanged = null;
      conn.dispose();
      throw TalkbackException(
        'เปิดสายไปกล้องไม่ได้ (${TiRtc.errorToString(connectCode)})',
      );
    }

    try {
      await connected.future.timeout(timeout);
    } catch (err) {
      conn.onStateChanged = null;
      await _TiRtcLink._quietly(() async => conn.disconnect());
      await _TiRtcLink._quietly(() async => conn.dispose());
      if (err is TimeoutException) {
        throw const TalkbackException('ต่อไปยังกล้องไม่ทัน — ลองใหม่อีกครั้ง');
      }
      rethrow;
    }

    final TiRtcAudioInput mic = TiRtcAudioInput();
    link = _TiRtcLink(conn, mic);
    mic.onError = (int code, String? message) {
      link?.onDropped?.call('ไมค์มีปัญหา (${TiRtc.errorToString(code)})');
    };

    try {
      final int optionsCode = await mic.setOptions(_optionsFor(session));
      if (optionsCode != 0) {
        throw TalkbackException(
          'ตั้งค่าไมค์ไม่สำเร็จ (${TiRtc.errorToString(optionsCode)})',
        );
      }

      final int attachCode = await mic.attach(
        connection: conn,
        streamId: session.streamId,
      );
      if (attachCode != 0) {
        throw TalkbackException(
          'ผูกไมค์กับสายไม่สำเร็จ (${TiRtc.errorToString(attachCode)})',
        );
      }
    } catch (_) {
      // ล้มหลังสร้างไมค์แล้ว ต้องคืนทั้งไมค์และสาย ไม่ใช่ปล่อยค้าง
      await link.close();
      rethrow;
    }

    return link;
  }

  /// เซิร์ฟเวอร์เป็นคนบอกว่ากล้องรอฟังฟอร์แมตไหน แอปไม่เดาเอง
  /// ค่าที่แปลงไม่ได้ให้ตกไปที่ค่าตามคู่มือ Tange (g711a / 16k / mono)
  static TiRtcAudioInputOptions _optionsFor(CameraTalkbackSession session) {
    return TiRtcAudioInputOptions(
      codec: switch (session.audioCodec.toLowerCase()) {
        'aac' => TiRtcAudioCodec.aac,
        'pcm' => TiRtcAudioCodec.pcm,
        'opus' => TiRtcAudioCodec.opus,
        'amr' => TiRtcAudioCodec.amr,
        _ => TiRtcAudioCodec.g711a,
      },
      sampleRate: session.sampleRateHz == 8000
          ? TiRtcAudioSampleRate.rate8k
          : TiRtcAudioSampleRate.rate16k,
      channels: TiRtcAudioChannelCount.mono,
      // ลำโพงกล้องกับไมค์มือถืออยู่ห้องเดียวกันได้ ถ้าไม่ตัดเสียงสะท้อน
      // เสียงจะวนกลับจนหอน — เปิด AEC ตามที่คู่มือ talkback แนะนำ
      aecMode: TiRtcAudioAecMode.enabled,
    );
  }
}

// ---------------------------------------------------------------------------
// ตัวคุมสถานะที่ widget ใช้
// ---------------------------------------------------------------------------

enum TalkbackPhase {
  /// ยังไม่ได้กด
  idle,

  /// กำลังขอสิทธิ์ไมค์ / ขอ token / ต่อสาย
  connecting,

  /// ไมค์เปิดอยู่ เสียงกำลังออกลำโพงกล้อง
  talking,
}

typedef TalkbackSessionFetcher = Future<CameraTalkbackSession> Function();
typedef TalkbackPermissionRequester = Future<bool> Function();

/// คุมวงจรชีวิตของการ "กดค้างเพื่อพูด" ทั้งหมด
///
/// แยกออกจาก widget เพราะขั้นตอนมีหลายจังหวะที่ยกเลิกกลางคันได้ (ผู้ใช้ปล่อย
/// นิ้วตอนไหนก็ได้) ถ้าเขียนกองอยู่ใน State จะพลาดเคสไมค์ค้างเปิดได้ง่ายมาก
class CameraTalkbackService {
  CameraTalkbackService({
    required TalkbackSessionFetcher fetchSession,
    required TalkbackPermissionRequester requestPermission,
    TalkbackEngine engine = const TiRtcTalkbackEngine(),
    this.connectTimeout = const Duration(seconds: 12),
  })  : _fetchSession = fetchSession,
        _requestPermission = requestPermission,
        _engine = engine;

  final TalkbackSessionFetcher _fetchSession;
  final TalkbackPermissionRequester _requestPermission;
  final TalkbackEngine _engine;
  final Duration connectTimeout;

  /// แจ้ง widget ว่าสถานะเปลี่ยน — ตั้งเป็น setState ของ State ที่ใช้
  VoidCallback? onChanged;

  TalkbackPhase _phase = TalkbackPhase.idle;
  TalkbackPhase get phase => _phase;

  String? _error;
  String? get error => _error;

  bool get isActive => _phase != TalkbackPhase.idle;

  /// ปฏิเสธสิทธิ์ไมค์แบบถาวร — widget เอาไปตัดสินว่าจะโชว์ปุ่มไป App Settings
  bool _permissionBlocked = false;
  bool get permissionBlocked => _permissionBlocked;

  TalkbackLink? _link;
  bool _disposed = false;

  /// ตัวนับรอบ ใช้แทน "ธงยกเลิก" เพราะกดพูดรอบใหม่ก่อนรอบเก่าเก็บของเสร็จได้
  ///
  /// ทุกขั้นที่ await เสร็จต้องเทียบเลขรอบก่อนไปต่อ ถ้าไม่ตรงแปลว่าผู้ใช้
  /// ปล่อยนิ้วไปแล้ว (หรือเริ่มรอบใหม่) — ต้องเก็บของที่สร้างมาแล้วทิ้ง
  int _generation = 0;

  /// เริ่มพูด — เรียกตอนผู้ใช้กดปุ่มค้าง
  ///
  /// ปลอดภัยถ้าถูกเรียกซ้อน: รอบก่อนหน้าจะถูกปิดก่อนเสมอ
  Future<void> start() async {
    if (_disposed) return;
    await stop();
    if (_disposed) return;

    final int generation = ++_generation;
    _permissionBlocked = false;
    _setPhase(TalkbackPhase.connecting, error: null);

    try {
      // ขอสิทธิ์ก่อนเสมอ — ห้ามแตะ token หรือ SDK จนกว่าจะได้สิทธิ์จริง
      final bool granted = await _requestPermission();
      if (!_stillCurrent(generation)) return;
      if (!granted) {
        _permissionBlocked = true;
        _fail('ต้องอนุญาตให้ใช้ไมโครโฟนก่อนจึงจะพูดออกกล้องได้');
        return;
      }

      final CameraTalkbackSession session = await _fetchSession();
      if (!_stillCurrent(generation)) return;
      if (!session.isUsable) {
        _fail('เซิร์ฟเวอร์ยังตั้งค่าการพูดออกกล้องไม่ครบ');
        return;
      }

      final TalkbackLink link = await _engine.open(
        session,
        timeout: connectTimeout,
      );

      // ต่อติดแล้วแต่ผู้ใช้ปล่อยนิ้วไปตั้งแต่ตอนไหนก็ไม่รู้ — ห้ามเปิดไมค์
      // ต้องปิดสายที่เพิ่งเปิดทิ้งด้วย ไม่งั้นค้างกินสายของกล้องไว้
      if (!_stillCurrent(generation)) {
        await link.close();
        return;
      }

      link.onDropped = (String message) {
        if (!_stillCurrent(generation)) return;
        unawaited(stop());
        _fail(message);
      };
      _link = link;

      await link.startMic();
      if (!_stillCurrent(generation)) {
        await stop();
        return;
      }

      _setPhase(TalkbackPhase.talking, error: null);
    } on TalkbackException catch (err) {
      if (!_stillCurrent(generation)) return;
      await stop();
      _fail(err.message);
    } catch (err) {
      if (!_stillCurrent(generation)) return;
      await stop();
      // ข้อความจาก ApiService เป็นภาษาไทยพร้อมโชว์อยู่แล้ว
      _fail('$err');
    }
  }

  /// หยุดพูดและคืนทรัพยากรทุกชั้น — เรียกซ้ำได้ ไม่ throw
  Future<void> stop() async {
    // ขยับเลขรอบก่อน เพื่อให้ขั้นตอนที่ยัง await ค้างอยู่รู้ตัวว่าถูกยกเลิก
    _generation++;

    final TalkbackLink? link = _link;
    _link = null;
    if (link != null) {
      link.onDropped = null;
      await link.close();
    }

    if (_phase != TalkbackPhase.idle) {
      _setPhase(TalkbackPhase.idle, error: _error);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    onChanged = null;
  }

  /// ล้างข้อความ error ตอนผู้ใช้เริ่มทำอย่างอื่น
  void clearError() {
    if (_error == null) return;
    _error = null;
    onChanged?.call();
  }

  bool _stillCurrent(int generation) => !_disposed && generation == _generation;

  void _fail(String message) {
    _error = message;
    _phase = TalkbackPhase.idle;
    onChanged?.call();
  }

  void _setPhase(TalkbackPhase phase, {required String? error}) {
    _phase = phase;
    _error = error;
    onChanged?.call();
  }
}
