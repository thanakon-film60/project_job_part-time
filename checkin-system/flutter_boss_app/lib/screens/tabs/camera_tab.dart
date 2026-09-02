import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/camera.dart';
import '../../services/api_service.dart';

/// ดึงภาพนิ่งถี่แค่ไหนตอนทุกอย่างปกติ — ถี่กว่านี้เปลืองเน็ตมือถือโดยไม่ได้
/// ภาพลื่นขึ้นจริง (ภาพละ ~35KB ทุก 1 วินาที = ~2MB ต่อนาที)
///
/// นับจาก "รอบก่อนหน้าดึงเสร็จ" ไม่ใช่เดินนาฬิกาทุก 1 วินาทีตายตัว —
/// เน็ตช้ากว่า 1 วินาทีเมื่อไร แบบเดินนาฬิกาจะยิงทับกันจนคิวบวม
const Duration _snapshotInterval = Duration(seconds: 1);

/// ดึงภาพไม่ผ่านติดกัน ให้ถอยห่างขึ้นเรื่อยๆ แทนที่จะยิงรัวเท่าเดิม
///
/// กล้องหรือเน็ตมีปัญหาอยู่แล้ว การยิงซ้ำวินาทีละครั้งไม่ได้ช่วยให้กลับมาเร็วขึ้น
/// มีแต่ทำให้เซิร์ฟเวอร์และกล้องแย่ลง แถมกินแบตมือถือทิ้งเปล่า
const Duration _minBackoff = Duration(seconds: 2);
const Duration _maxBackoff = Duration(seconds: 15);

/// ต่อกล้องไม่ติด ให้ลองเช็คสถานะใหม่เองเป็นระยะ ไม่ต้องรอผู้ใช้กดปุ่ม
const Duration _statusRetryInterval = Duration(seconds: 20);

/// สถานะที่เพิ่งโหลดมาไม่เกินเท่านี้ ถือว่ายังใช้ได้ ไม่ต้องโหลดซ้ำ
///
/// ใช้ตอนผู้ใช้กลับเข้ามาดูแท็บหรือสลับกลับมาที่แอป — กันไม่ให้ยิงซ้ำรัวๆ
/// เวลาสลับแท็บไปมาเร็วๆ แต่ก็สั้นพอที่ความสามารถฝั่งเซิร์ฟเวอร์ที่เพิ่งเปลี่ยน
/// จะขึ้นมาให้เห็นทันที
const Duration _statusFreshFor = Duration(seconds: 15);

/// รอเสียงเริ่มไหลนานสุดเท่านี้ — กล้องปกติใช้เวลาราว 6 วินาที
/// ไม่ใส่เพดานไว้ ปุ่มจะค้างที่ "กำลังต่อเสียง..." ไปตลอดเมื่อสตรีมไม่มา
const Duration _audioConnectTimeout = Duration(seconds: 25);

/// แตะปุ่มทิศทาง 1 ครั้ง = หมุนสั้นๆ, กดค้าง = หมุนไกลขึ้น
/// เพดานจริงถูกจำกัดอีกชั้นที่เซิร์ฟเวอร์ด้วย CAMERA_PTZ_MAX_DURATION_MS
const int _tapDurationMs = 500;
const int _longPressDurationMs = 1500;

/// ลากนิ้วบนภาพต้องเกินระยะนี้ถึงนับเป็นการสั่งหมุน — กันสั่งพลาดตอนแตะเฉยๆ
const double _dragThreshold = 24;

/// สีพื้นของโซนดูภาพ — จอกล้องควรมืดเพื่อให้เห็นรายละเอียดในภาพชัด
const Color _consoleBg = Color(0xFF10131A);
const Color _consolePanel = Color(0xFF1A1F2B);

/// แท็บ "กล้องวงจรปิด" (หัวหน้าเท่านั้น)
///
/// ภาพเป็นภาพนิ่งที่รีเฟรชเองเรื่อยๆ ไม่ใช่วิดีโอ RTSP — แลกความลื่นกับการ
/// ไม่ต้องพึ่ง plugin วิดีโอ และไม่ต้องเปิดพอร์ตกล้องออกอินเทอร์เน็ต
/// ส่วนเสียงเป็นสตรีมจริงจากไมค์กล้อง ผ่าน ffmpeg ที่เซิร์ฟเวอร์
class CameraTab extends StatefulWidget {
  const CameraTab({super.key});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> with WidgetsBindingObserver {
  CameraStatus? _status;

  /// ภาพที่โชว์อยู่ — เก็บเป็น MemoryImage ไม่ใช่ bytes ดิบ เพราะต้องถือ
  /// ตัวเดิมไว้ไล่ออกจากแคชของ Flutter ตอนเปลี่ยนเฟรม (ดู _showFrame)
  MemoryImage? _frameImage;
  DateTime? _frameAt;
  bool _frameStale = false;

  String? _statusError;
  String? _frameError;
  String? _commandError;

  bool _loadingStatus = true;
  bool _paused = false;

  /// กันไม่ให้รอบถัดไปยิงซ้อนรอบที่ยังไม่จบ (เน็ตช้า/กล้องตอบช้า)
  bool _fetchingFrame = false;

  /// ดึงภาพไม่ผ่านติดกันกี่รอบแล้ว — ใช้คำนวณระยะถอย
  int _failStreak = 0;

  /// กำลังรอกล้องหมุนอยู่ — ปิดปุ่มไว้ก่อน กันกดรัวจนคำสั่งกองกัน
  bool _moving = false;

  /// ทิศที่เพิ่งสั่งไป ใช้โชว์ลูกศรทับบนภาพให้รู้ว่าคำสั่งไปแล้ว
  String? _lastDirection;

  Timer? _timer;
  Timer? _statusRetry;

  /// สถานะที่โหลดมายัง "สด" อยู่ไหม — ตัวจับเวลาข้างล่างเป็นคนพลิกเป็น false
  ///
  /// ใช้ตัวจับเวลาแทนการเทียบ DateTime.now() เพราะเป็นกลไกเดียวกับลูปดึงภาพ
  /// อ่านง่ายกว่า และทดสอบได้ด้วยนาฬิกาจำลองของ widget test
  bool _statusFresh = false;
  Timer? _statusFreshTimer;

  /// แท็บนี้ถูกเปิดดูอยู่จริงไหม (IndexedStack เก็บแท็บที่ซ่อนไว้ให้ยังมีชีวิต)
  bool _visible = true;

  /// แอปอยู่หน้าจอไหม — ย่อแอปแล้วยังดึงภาพต่อ = เปลืองเน็ตทิ้งเปล่า
  bool _foreground = true;

  /// ระยะลากนิ้วสะสมของท่าทางที่กำลังทำอยู่
  ///
  /// ต้องเป็นตัวแปรของ State ไม่ใช่ตัวแปรใน build — ภาพเปลี่ยนทุกวินาที
  /// ทำให้ build ใหม่ตลอด ถ้าเก็บไว้ใน build ระยะที่ลากมาจะถูกล้างกลางคัน
  /// แล้วการลากจะสั่งกล้องเพี้ยนหรือไม่สั่งเลย
  Offset _dragTotal = Offset.zero;

  // ---- เสียง ----
  AudioPlayer? _player;
  StreamSubscription<PlaybackEvent>? _audioEvents;
  bool _listening = false;
  bool _audioConnecting = false;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // app_shell ห่อแท็บที่ซ่อนอยู่ด้วย TickerMode(enabled: false) ไว้ให้แล้ว
    final visible = TickerMode.of(context);
    if (visible == _visible) return;
    _visible = visible;
    _syncPolling();
    if (visible) _refreshStatusIfStale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _statusRetry?.cancel();
    _statusFreshTimer?.cancel();
    _audioEvents?.cancel();
    _player?.dispose();
    // เฟรมสุดท้ายยังค้างอยู่ในแคชรูปของ Flutter ถ้าไม่ไล่ออก
    _frameImage?.evict();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // เสียงปล่อยให้เล่นต่อได้ตอนย่อแอป — หัวหน้าอาจอยากฟังเสียงไปทำอย่างอื่นไป
    _syncPolling();
    if (_foreground) _refreshStatusIfStale();
  }

  /// โหลดสถานะใหม่เมื่อผู้ใช้กลับเข้ามาดู (สลับกลับมาที่แท็บ หรือกลับเข้าแอป)
  ///
  /// จำเป็นเพราะความสามารถฝั่งเซิร์ฟเวอร์เปลี่ยนได้ระหว่างที่แอปเปิดค้างอยู่
  /// เช่นเพิ่งติดตั้ง ffmpeg ที่เซิร์ฟเวอร์ ปุ่มฟังเสียงก็ควรโผล่มาเอง
  ///
  /// ตัวจับเวลาลองใหม่ทุก 20 วินาทีช่วยเคสนี้ไม่ได้ เพราะมันทำงานเฉพาะตอน
  /// "ต่อกล้องไม่ติด" ซึ่งไม่ใช่กรณีนี้ — กล้องปกติดี แค่ความสามารถเปลี่ยน
  /// ก่อนหน้านี้ค่าเก่าจึงค้างจนกว่าผู้ใช้จะลากรีเฟรชเองหรือปิดแอปเปิดใหม่
  void _refreshStatusIfStale() {
    if (!_visible || !_foreground || _loadingStatus || _statusFresh) return;
    _loadStatus(silent: true);
  }

  /// เพิ่งคุยกับ /camera/status มา — อีกสักพักค่อยถือว่าเก่าพอที่จะถามใหม่
  void _markStatusLoaded() {
    _statusFreshTimer?.cancel();
    _statusFresh = true;
    _statusFreshTimer = Timer(_statusFreshFor, () => _statusFresh = false);
  }

  // -------------------------------------------------------------------
  // จังหวะดึงภาพ
  // -------------------------------------------------------------------

  /// ตอนนี้ควรดึงภาพอยู่หรือไม่ — เงื่อนไขทั้งหมดรวมไว้ที่เดียว
  bool get _shouldPoll =>
      mounted &&
      _visible &&
      _foreground &&
      !_paused &&
      (_status?.canControl ?? false);

  /// ให้ลูปดึงภาพตรงกับสถานการณ์ปัจจุบัน — เรียกได้ทุกครั้งที่เงื่อนไขเปลี่ยน
  void _syncPolling() {
    if (_shouldPoll) {
      _scheduleNext(Duration.zero);
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _syncStatusRetry();
  }

  /// ตั้งรอบถัดไป — ลูปแบบ "จบรอบแล้วค่อยนัดรอบใหม่" ไม่ใช่ Timer.periodic
  /// รอบที่ยังไม่จบจึงไม่มีวันถูกยิงทับ ต่อให้เน็ตช้ากว่าจังหวะที่ตั้งไว้
  void _scheduleNext(Duration delay) {
    _timer?.cancel();
    if (!_shouldPoll) {
      _timer = null;
      return;
    }
    _timer = Timer(delay, () async {
      await _fetchFrame();
      if (!mounted) return;
      _scheduleNext(_nextDelay());
    });
  }

  /// ปกติ 1 วินาที, พลาดแล้วถอยเป็น 2 → 4 → 8 → 15 วินาที
  Duration _nextDelay() {
    if (_failStreak == 0) return _snapshotInterval;
    final shift = (_failStreak - 1).clamp(0, 3);
    final ms = _minBackoff.inMilliseconds << shift;
    return Duration(
      milliseconds: ms.clamp(
        _minBackoff.inMilliseconds,
        _maxBackoff.inMilliseconds,
      ),
    );
  }

  /// เอาเฟรมใหม่ขึ้นจอ แล้วไล่เฟรมเก่าออกจากแคชรูปของ Flutter
  ///
  /// MemoryImage แต่ละก้อนนับเป็นคนละรูปในแคช (เทียบกันด้วยตัวออบเจ็กต์
  /// ไม่ใช่เนื้อภาพ) ถ้าปล่อยไว้ แคชจะโตขึ้นวินาทีละภาพจนชนเพดาน ~100MB
  /// แล้วแอปจะเริ่มกระตุก และเครื่องแรมน้อยจะถูกระบบฆ่าทิ้ง
  /// นี่คือสาเหตุที่ยิ่งเปิดหน้ากล้องทิ้งไว้นาน ยิ่งหน่วง
  void _showFrame(CameraFrame frame) {
    final previous = _frameImage;
    setState(() {
      _frameImage = MemoryImage(frame.bytes);
      _frameAt = DateTime.now().subtract(frame.age);
      _frameStale = frame.isStale;
      _frameError = null;
    });
    previous?.evict();
  }

  void _syncStatusRetry() {
    // ต่อกล้องไม่ติด/เช็คสถานะไม่ผ่าน แล้วผู้ใช้ยังเปิดหน้านี้ค้างอยู่ —
    // ลองใหม่ให้เองเป็นระยะ กล้องกลับมาเมื่อไรภาพจะขึ้นเองโดยไม่ต้องกดอะไร
    final needsRetry = _visible &&
        _foreground &&
        !_loadingStatus &&
        (_statusError != null || !(_status?.canControl ?? false));

    if (!needsRetry) {
      _statusRetry?.cancel();
      _statusRetry = null;
      return;
    }
    _statusRetry ??= Timer.periodic(_statusRetryInterval, (_) {
      if (mounted) _loadStatus(silent: true);
    });
  }

  // -------------------------------------------------------------------
  // ข้อมูล
  // -------------------------------------------------------------------

  /// silent = ลองเองเบื้องหลัง ไม่ต้องล้างจอเป็น "กำลังเช็คสถานะ..."
  Future<void> _loadStatus({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingStatus = true;
        _statusError = null;
      });
    }

    try {
      final status = await ApiService.fetchCameraStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusError = null;
        _loadingStatus = false;
        _failStreak = 0;
      });
      _markStatusLoaded();
      // กล้องหลุดไปแล้วกลับมา — เริ่มดึงภาพต่อทันที
      _syncPolling();
    } on ApiException catch (err) {
      _onStatusFailed(err.message);
    } catch (err) {
      _onStatusFailed('เช็คสถานะกล้องไม่สำเร็จ: $err');
    }
  }

  void _onStatusFailed(String message) {
    if (!mounted) return;
    setState(() {
      _statusError = message;
      _loadingStatus = false;
    });
    // นับเป็น "เพิ่งลองไป" ด้วย กันไม่ให้สลับแท็บไปมาแล้วยิงซ้ำรัวๆ
    // ตอนเซิร์ฟเวอร์ล่ม (ตัวจับเวลา 20 วินาทีรับหน้าที่ลองใหม่อยู่แล้ว)
    _markStatusLoaded();
    _syncPolling();
  }

  Future<void> _fetchFrame() async {
    if (_fetchingFrame || !mounted) return;
    _fetchingFrame = true;

    try {
      final frame = await ApiService.fetchCameraSnapshot();
      if (!mounted) return;
      _failStreak = 0;
      _showFrame(frame);
    } on ApiException catch (err) {
      // 401 = เซสชันหมดอายุ ถูกเด้งออกไปแล้ว ยิงต่อก็ไม่มีวันผ่าน —
      // ล้างสถานะกล้องเพื่อให้ _shouldPoll เป็น false แล้วลูปหยุดเองจริงๆ
      // (แค่ cancel timer ไม่พอ เพราะรอบที่กำลังทำงานอยู่จะตั้งรอบใหม่ต่อทันที)
      if (err.statusCode == 401) {
        if (mounted) setState(() => _status = null);
        _onStatusFailed(err.message);
        return;
      }
      // ภาพหลุดเป็นครั้งคราวถือเป็นเรื่องปกติของกล้อง IP — ไม่ล้างภาพเดิมทิ้ง
      // ยังโชว์เฟรมล่าสุดค้างไว้พร้อมข้อความ ดีกว่าจอดำกะพริบ
      _onFrameFailed(err.message);
    } catch (err) {
      _onFrameFailed('โหลดภาพจากกล้องไม่สำเร็จ: $err');
    } finally {
      _fetchingFrame = false;
    }
  }

  void _onFrameFailed(String message) {
    if (!mounted) return;
    setState(() {
      _failStreak++;
      _frameError = message;
      _frameStale = true;
    });
  }

  Future<void> _send(String action, {int? durationMs}) async {
    if (_moving) return;
    setState(() {
      _moving = true;
      _commandError = null;
      if (action != CameraAction.home) _lastDirection = action;
    });

    try {
      await ApiService.moveCamera(action, durationMs: durationMs);
    } on ApiException catch (err) {
      if (mounted) setState(() => _commandError = err.message);
    } catch (err) {
      if (mounted) setState(() => _commandError = 'สั่งกล้องไม่สำเร็จ: $err');
    } finally {
      if (mounted) {
        setState(() => _moving = false);
        // กล้องเพิ่งขยับ — ขอภาพใหม่ทันทีจะได้เห็นผลโดยไม่ต้องรอรอบถัดไป
        // (ยิงผ่านลูปเดิม ไม่เรียก _fetchFrame ตรงๆ จะได้ไม่ซ้อนรอบที่ค้างอยู่)
        _scheduleNext(Duration.zero);
      }
      // ลูกศรบนภาพค้างไว้แป๊บนึงแล้วค่อยจาง
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _lastDirection = null);
      });
    }
  }

  Future<void> _stop() async {
    try {
      await ApiService.stopCamera();
    } on ApiException catch (err) {
      if (mounted) setState(() => _commandError = err.message);
    } catch (err) {
      if (mounted) {
        setState(() => _commandError = 'สั่งหยุดกล้องไม่สำเร็จ: $err');
      }
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _syncPolling();
  }

  // -------------------------------------------------------------------
  // เสียงจากไมค์กล้อง
  // -------------------------------------------------------------------

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stopListening();
      return;
    }

    setState(() {
      _audioConnecting = true;
      _audioError = null;
    });

    try {
      // สร้างตัวเล่นใหม่ทุกครั้งที่เริ่มฟัง — ตัวเก่าถูกทิ้งไปตอนกดหยุดแล้ว
      // (ดูเหตุผลที่ _releasePlayer)
      final player = _player ??= AudioPlayer();
      _watchAudio(player);
      await player
          .setAudioSource(
            AudioSource.uri(
              Uri.parse(ApiService.cameraAudioUrl),
              headers: ApiService.cameraAudioHeaders,
            ),
          )
          .timeout(_audioConnectTimeout);
      unawaited(player.play());
      if (!mounted) return;
      setState(() {
        _listening = true;
        _audioConnecting = false;
      });
    } on TimeoutException {
      await _onAudioFailed('ต่อเสียงไม่ทัน — กล้องไม่ส่งเสียงมา ลองใหม่อีกครั้ง');
    } catch (err) {
      await _onAudioFailed('ต่อเสียงไม่ได้: $err');
    }
  }

  /// เฝ้าสตรีมเสียงไว้ — ffmpeg ที่เซิร์ฟเวอร์ตายหรือกล้องตัดสายกลางคัน
  /// ถ้าไม่ดักไว้ ปุ่มจะยังขึ้น "หยุดฟังเสียง" ทั้งที่ไม่มีเสียงแล้ว
  void _watchAudio(AudioPlayer player) {
    _audioEvents?.cancel();
    _audioEvents = player.playbackEventStream.listen(
      (event) {
        if (!mounted || !_listening) return;
        if (event.processingState == ProcessingState.completed) {
          setState(() {
            _listening = false;
            _audioError = 'สตรีมเสียงจบลง — กดฟังใหม่ได้';
          });
        }
      },
      onError: (Object err, StackTrace _) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _audioConnecting = false;
          _audioError = 'เสียงหลุด: $err';
        });
      },
    );
  }

  Future<void> _onAudioFailed(String message) async {
    // ตัวเล่นที่ต่อไม่สำเร็จอาจค้างสถานะไว้ ทิ้งไปเลยให้กดใหม่ได้สะอาดๆ
    await _releasePlayer();
    if (!mounted) return;
    setState(() {
      _audioConnecting = false;
      _listening = false;
      _audioError = message;
    });
  }

  Future<void> _stopListening() async {
    await _releasePlayer();
    if (mounted) setState(() => _listening = false);
  }

  /// เลิกใช้ตัวเล่นเสียงให้ขาดจริง ๆ ไม่ใช่แค่หยุดเล่น
  ///
  /// ต้อง dispose ไม่ใช่ stop() เพราะ just_audio บน Android ไม่ได้ให้ ExoPlayer
  /// ต่อ URL ของเราตรง ๆ — ตอนที่ส่ง header ไปด้วย มันจะตั้งพร็อกซีเล็ก ๆ ในเครื่อง
  /// แล้วให้พร็อกซีเป็นคนดึงจากเซิร์ฟเวอร์ให้ stop() หยุดแค่การเล่น
  /// แต่พร็อกซีตัวนั้นยังคาสายไว้กับเซิร์ฟเวอร์
  ///
  /// ผลคือ ffmpeg ฝั่งเซิร์ฟเวอร์ไม่รู้ว่าไม่มีคนฟังแล้ว จึงเปิด RTSP ค้างไว้กับ
  /// กล้องต่อไป (ยืนยันแล้วด้วยการนับ process: กดหยุดแล้ว ffmpeg ยังอยู่)
  /// ซึ่งกินโควตาการเชื่อมต่อของกล้อง แล้วทำให้ภาพนิ่ง/หมุนกล้องพลอยช้าไปด้วย
  Future<void> _releasePlayer() async {
    _audioEvents?.cancel();
    _audioEvents = null;

    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {
      // ปิดไม่สำเร็จไม่ใช่เรื่องคอขาดบาดตาย ครั้งหน้าสร้างตัวใหม่อยู่แล้ว
    }
  }

  // -------------------------------------------------------------------
  // ลากนิ้วบนภาพเพื่อเลื่อนกล้อง
  // -------------------------------------------------------------------

  void _onDragEnd() {
    final total = _dragTotal;
    _dragTotal = Offset.zero;
    if (_moving) return;

    final dx = total.dx;
    final dy = total.dy;
    if (dx.abs() < _dragThreshold && dy.abs() < _dragThreshold) return;

    // ลากแนวไหนมากกว่าก็เอาแนวนั้น — กันสั่งทแยงแล้วกล้องขยับมั่ว
    final horizontal = dx.abs() >= dy.abs();
    final distance = horizontal ? dx.abs() : dy.abs();

    // ลากไกล = หมุนนาน แต่ไม่เกินเพดานที่เซิร์ฟเวอร์ยอมรับ
    final durationMs = (distance * 4).clamp(300, 2500).toInt();

    // ลากนิ้วไปทางซ้าย = อยากเห็นสิ่งที่อยู่ทางซ้าย = หมุนกล้องไปทางซ้าย
    final String action;
    if (horizontal) {
      action = dx < 0 ? CameraAction.left : CameraAction.right;
    } else {
      action = dy < 0 ? CameraAction.up : CameraAction.down;
    }
    _send(action, durationMs: durationMs);
  }

  // -------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _consoleBg,
      child: RefreshIndicator(
        onRefresh: () => _loadStatus(),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildViewport(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildConsole(),
            ),
          ],
        ),
      ),
    );
  }

  /// โซนดูภาพ — ภาพเต็มความกว้าง มีแถบสถานะทับด้านบน/ล่างแบบจอ CCTV
  Widget _buildViewport() {
    final status = _status;
    final live = status?.canControl == true &&
        !_paused &&
        _frameImage != null &&
        !_frameStale;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildFrameLayer(),
            if (_lastDirection != null) _buildDirectionOverlay(),
            _buildTopBar(live),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameLayer() {
    if (_loadingStatus) {
      return const Center(
        child: Text('กำลังเช็คสถานะกล้อง...',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final status = _status;
    if (_statusError != null || (status != null && !status.canControl)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white38, size: 40),
              const SizedBox(height: 10),
              Text(
                _statusError ?? status!.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 6),
              const Text(
                'ระบบจะลองต่อใหม่ให้เองทุก 20 วินาที',
                style: TextStyle(color: Colors.white30, fontSize: 11),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadStatus(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('ลองใหม่เดี๋ยวนี้'),
                style:
                    OutlinedButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final image = _frameImage;
    if (image == null) {
      return const Center(
        child: Text('กำลังรอภาพจากกล้อง...',
            style: TextStyle(color: Colors.white54)),
      );
    }

    // ลากนิ้วบนภาพ = สั่งกล้องหมุน (เก็บระยะรวมเองเพราะ DragEndDetails
    // ให้มาแต่ความเร็ว ไม่ได้บอกว่าลากไปไกลแค่ไหน)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _dragTotal = Offset.zero,
      onPanUpdate: (d) => _dragTotal += d.delta,
      onPanEnd: (_) => _onDragEnd(),
      onPanCancel: () => _dragTotal = Offset.zero,
      child: Image(
        image: image,
        fit: BoxFit.contain,
        // ไม่ใส่ gaplessPlayback ภาพจะกะพริบขาวทุกรอบที่เปลี่ยนเฟรม
        gaplessPlayback: true,
      ),
    );
  }

  /// ลูกศรจางๆ ทับบนภาพ บอกว่าคำสั่งทิศไหนเพิ่งถูกส่งไป
  Widget _buildDirectionOverlay() {
    const icons = {
      CameraAction.up: Icons.arrow_upward,
      CameraAction.down: Icons.arrow_downward,
      CameraAction.left: Icons.arrow_back,
      CameraAction.right: Icons.arrow_forward,
      CameraAction.zoomIn: Icons.zoom_in,
      CameraAction.zoomOut: Icons.zoom_out,
    };
    final icon = icons[_lastDirection];
    if (icon == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 34),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool live) {
    final status = _status;
    final String label;
    if (_paused) {
      label = 'หยุดภาพ';
    } else if (live) {
      label = 'LIVE';
    } else if (_frameImage != null) {
      label = 'ภาพค้าง';
    } else {
      label = 'ออฟไลน์';
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: live
                    ? Colors.redAccent
                    : (_frameImage != null && !_paused
                        ? Colors.orangeAccent
                        : Colors.white38),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (_listening) ...[
              const Icon(Icons.volume_up,
                  color: Colors.lightBlueAccent, size: 14),
              const SizedBox(width: 4),
            ],
            Text(
              status?.deviceLabel ?? status?.host ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final at = _frameAt;
    final stamp = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}:'
            '${at.second.toString().padLeft(2, '0')}';

    final trouble = _frameError != null || _frameStale;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                trouble
                    ? 'ภาพสะดุด — โชว์ภาพล่าสุดไว้ กำลังลองใหม่'
                    : 'ลากนิ้วบนภาพเพื่อเลื่อนกล้อง',
                style: TextStyle(
                  color: trouble ? Colors.orangeAccent : Colors.white60,
                  fontSize: 11,
                ),
              ),
            ),
            Text(stamp,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 8),
            InkWell(
              onTap: _status?.canControl == true
                  ? _togglePause
                  : () => _loadStatus(),
              child: Icon(
                _status?.canControl != true
                    ? Icons.refresh
                    : (_paused ? Icons.play_arrow : Icons.pause),
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// แผงควบคุมใต้จอ
  Widget _buildConsole() {
    final status = _status;
    final canControl = status?.canControl ?? false;

    if (!canControl) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _consolePanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDirectionPad(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _consoleButton(
                  label: 'ซูมเข้า',
                  icon: Icons.zoom_in,
                  onTap: () =>
                      _send(CameraAction.zoomIn, durationMs: _tapDurationMs),
                  onLongPress: () => _send(CameraAction.zoomIn,
                      durationMs: _longPressDurationMs),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _consoleButton(
                  label: 'ซูมออก',
                  icon: Icons.zoom_out,
                  onTap: () =>
                      _send(CameraAction.zoomOut, durationMs: _tapDurationMs),
                  onLongPress: () => _send(CameraAction.zoomOut,
                      durationMs: _longPressDurationMs),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAudioRow(),
          const SizedBox(height: 8),
          _consoleButton(
            label: 'สั่งหยุดทันที',
            icon: Icons.pan_tool,
            onTap: _moving ? null : _stop,
            danger: true,
          ),
          const SizedBox(height: 12),
          const Text(
            'แตะ = ขยับนิดเดียว · กดค้าง = ขยับไกลขึ้น · ลากบนภาพ = เลื่อนตามระยะลาก',
            style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.5),
          ),
          if (_commandError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _commandError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioRow() {
    final status = _status;
    if (status == null || !status.audioSupported) {
      return _buildUnavailableNote(
        // ให้เซิร์ฟเวอร์เป็นคนบอกเหตุผล แอปไม่ต้องเดา — เงื่อนไขอยู่ฝั่งนั้นหมด
        status?.audioNote ?? 'เซิร์ฟเวอร์นี้ยังส่งเสียงจากกล้องไม่ได้',
        // ความสามารถนี้เปิดเพิ่มที่เซิร์ฟเวอร์ได้ตลอด (เช่นเพิ่งลง ffmpeg)
        // จึงต้องมีทางให้ผู้ใช้สั่งเช็คใหม่ ไม่ใช่ปล่อยให้เจอทางตัน
        showRetry: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _consoleButton(
          label: _audioConnecting
              ? 'กำลังต่อเสียง...'
              : (_listening ? 'หยุดฟังเสียง' : 'ฟังเสียงจากกล้อง'),
          icon: _listening ? Icons.volume_up : Icons.mic,
          onTap: _audioConnecting ? null : _toggleListen,
          highlight: _listening,
          // ปุ่มเสียงไม่ควรถูกล็อกตามการหมุนกล้อง — คนละเรื่องกัน
          ignoreMoving: true,
        ),
        if (_audioConnecting)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'กล้องใช้เวลาเริ่มส่งเสียงราว 6 วินาที',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        if (!status.talkbackSupported)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              // เซิร์ฟเวอร์ถามกล้องจริงมาแล้วว่าติดตรงไหน จึงบอกได้ตรงจุด
              // (ข้อความสำรองไว้เผื่อเซิร์ฟเวอร์รุ่นเก่าที่ยังไม่ส่งฟิลด์นี้มา)
              status.talkbackNote == null
                  ? 'กล้องตัวนี้ยังไม่เปิดช่องส่งเสียงเข้า จึงกดพูดออกกล้องไม่ได้'
                  : 'กดพูดออกกล้องไม่ได้ — ${status.talkbackNote}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        if (_audioError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _audioError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// ข้อความ "ทำสิ่งนี้ไม่ได้" พร้อมทางออกให้ผู้ใช้กดลองใหม่
  ///
  /// ของเดิมเป็นข้อความเฉยๆ ผู้ใช้เจอทางตัน ไม่รู้ว่าต้องทำอะไรต่อ ทั้งที่
  /// บางทีเซิร์ฟเวอร์พร้อมแล้วแต่แอปยังถือค่าเก่าอยู่
  Widget _buildUnavailableNote(String message, {bool showRetry = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
          if (showRetry) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _loadingStatus ? null : () => _loadStatus(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('ลองเช็คใหม่', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// แป้นทิศทาง — วางเหมือนบนหน้าจอคอม: บน / ซ้าย-กลาง-ขวา / ล่าง
  Widget _buildDirectionPad() {
    return Column(
      children: [
        _padButton(CameraAction.up, Icons.keyboard_arrow_up, 'ขึ้น'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _padButton(
                    CameraAction.left, Icons.keyboard_arrow_left, 'ซ้าย')),
            const SizedBox(width: 8),
            Expanded(
              child: _consoleButton(
                label: 'ตั้งต้น',
                icon: Icons.center_focus_strong,
                onTap: _moving || !(_status?.homeSupported ?? false)
                    ? null
                    : () => _send(CameraAction.home),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: _padButton(
                    CameraAction.right, Icons.keyboard_arrow_right, 'ขวา')),
          ],
        ),
        const SizedBox(height: 8),
        _padButton(CameraAction.down, Icons.keyboard_arrow_down, 'ลง'),
      ],
    );
  }

  Widget _padButton(String action, IconData icon, String label) {
    return _consoleButton(
      label: label,
      icon: icon,
      onTap: () => _send(action, durationMs: _tapDurationMs),
      onLongPress: () => _send(action, durationMs: _longPressDurationMs),
    );
  }

  /// ปุ่มสไตล์แผงควบคุม — สีเข้มเข้ากับจอกล้อง
  ///
  /// ไม่ได้ทำเป็น "หมุนตราบที่ยังกดค้าง" เหมือนบนคอม เพราะบนมือถือถ้าเน็ต
  /// หลุดตอนปล่อยนิ้ว คำสั่งหยุดจะไม่ถึงกล้อง กล้องจะหมุนค้างไปเรื่อยๆ
  Widget _consoleButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool highlight = false,
    bool danger = false,
    bool ignoreMoving = false,
  }) {
    final enabled = onTap != null && (ignoreMoving || !_moving);
    final Color fg = !enabled
        ? Colors.white24
        : danger
            ? Colors.redAccent
            : highlight
                ? Colors.lightBlueAccent
                : Colors.white;

    return Material(
      color: highlight
          ? Colors.lightBlueAccent.withValues(alpha: 0.15)
          : Colors.white10,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
