import 'dart:typed_data';

/// สถานะกล้องวงจรปิดที่เซิร์ฟเวอร์รายงานกลับมา (GET /camera/status)
///
/// กล้องเป็นอุปกรณ์ในวง LAN ของออฟฟิศ แอปคุยกับกล้องตรงๆ ไม่ได้ —
/// เซิร์ฟเวอร์เป็นคนคุยให้ ตัวนี้จึงบอกว่า "เซิร์ฟเวอร์ต่อกล้องติดไหม"
/// ไม่ใช่ "มือถือต่อกล้องติดไหม"
class CameraStatus {
  /// เปิดใช้ระบบกล้องไว้ที่เซิร์ฟเวอร์หรือเปล่า (CAMERA_PTZ_ENABLED)
  final bool enabled;

  /// เซิร์ฟเวอร์คุยกับกล้องได้จริงหรือไม่
  final bool reachable;

  final String host;

  /// ข้อความพร้อมแสดงบนหน้าจอ — ถ้าต่อไม่ได้จะบอกสาเหตุมาด้วย
  final String message;

  final String? model;
  final String? firmware;

  /// กล้องรองรับ "กลับตำแหน่งตั้งต้น" ไหม — ใช้ตัดสินว่าจะเปิดปุ่ม Reset
  final bool homeSupported;

  /// ฟังเสียงจากไมค์ของกล้องได้ไหม (เซิร์ฟเวอร์ต้องมี ffmpeg ด้วย)
  final bool audioSupported;

  /// เหตุผลที่ฟังเสียงไม่ได้ ตามที่เซิร์ฟเวอร์บอกมา (null = ฟังได้ปกติ)
  ///
  /// ให้เซิร์ฟเวอร์เป็นคนบอกเหตุผล แทนที่แอปจะเดาเอง — เพราะเงื่อนไขอยู่ที่
  /// ฝั่งนั้นทั้งหมด (ปิดระบบเสียงไว้ / ยังไม่ได้ลง ffmpeg)
  final String? audioNote;

  /// พูดกลับออกลำโพงกล้องได้ไหม
  ///
  /// เซิร์ฟเวอร์ไปถามกล้องจริงทุกครั้ง (RTSP DESCRIBE + Require backchannel)
  /// ไม่ได้เขียนคำตอบตายตัวไว้ เปลี่ยนกล้องหรืออัปเฟิร์มแวร์แล้วปุ่มจะโผล่เอง
  final bool talkbackSupported;

  /// เหตุผลที่พูดกลับไม่ได้ ตามที่เซิร์ฟเวอร์ถามกล้องมา (null = พูดได้)
  final String? talkbackNote;

  /// ระบบของเราพร้อมให้กดพูดจริงหรือยัง — คนละเรื่องกับ [talkbackSupported]
  ///
  /// [talkbackSupported] แปลว่า "กล้องเปิดช่องรับเสียงไว้" ซึ่งอาจเป็น RTSP
  /// backchannel ที่แอปเราส่งเข้าไม่ได้ ส่วนตัวนี้แปลว่าเซิร์ฟเวอร์ตั้งค่า
  /// transport ที่แอปใช้ได้จริงครบแล้ว จึงเป็นตัวตัดสินว่าจะโชว์ปุ่มพูดไหม
  final bool talkbackReady;

  /// ช่องทางส่งเสียงที่เซิร์ฟเวอร์เตรียมไว้ — ตอนนี้รองรับเฉพาะ `tirtc`
  ///
  /// ต้องเช็คด้วย ไม่ใช่ดูแค่ [talkbackReady] เพราะวันหน้าเซิร์ฟเวอร์อาจเพิ่ม
  /// transport แบบอื่นที่แอปรุ่นนี้ยังไม่รู้จัก แล้วจะกดพูดไม่ออก
  final String? talkbackTransport;

  /// path ที่ใช้ขอ token — เซิร์ฟเวอร์บอกมาเองเผื่อย้ายที่อยู่ในอนาคต
  final String? talkbackTokenPath;

  /// stream id ที่ต้องส่งเสียงเข้า (ช่วงที่ TiRTC ใช้ได้คือ 0..15)
  final int? talkbackStreamId;

  const CameraStatus({
    required this.enabled,
    required this.reachable,
    required this.host,
    required this.message,
    this.model,
    this.firmware,
    this.homeSupported = false,
    this.audioSupported = false,
    this.audioNote,
    this.talkbackSupported = false,
    this.talkbackNote,
    this.talkbackReady = false,
    this.talkbackTransport,
    this.talkbackTokenPath,
    this.talkbackStreamId,
  });

  /// transport เดียวที่แอปรุ่นนี้ส่งเสียงเข้าได้จริง
  static const String talkbackTransportTiRtc = 'tirtc';

  /// สั่งกล้องได้ก็ต่อเมื่อเปิดระบบไว้ และเซิร์ฟเวอร์ต่อกล้องติด
  bool get canControl => enabled && reachable;

  /// โชว์ปุ่ม "กดค้างเพื่อพูด" ได้ไหม
  ///
  /// ต้องครบทั้งสามอย่าง: เซิร์ฟเวอร์บอกว่าพร้อม, ใช้ transport ที่แอปรู้จัก
  /// และมี stream id ที่ถูกช่วง — ขาดข้อใดข้อหนึ่งแล้วกดไปก็ล้มกลางทาง
  /// สู้ไม่โชว์ปุ่มแล้วบอกเหตุผลไปเลยดีกว่า
  bool get canTalkback =>
      talkbackReady &&
      talkbackTransport == talkbackTransportTiRtc &&
      talkbackStreamId != null &&
      talkbackStreamId! >= 0 &&
      talkbackStreamId! <= 15;

  /// ชื่อรุ่น + เฟิร์มแวร์ สำหรับโชว์ใต้หัวข้อ (null ถ้ากล้องไม่ได้บอกมา)
  String? get deviceLabel {
    if (model == null || model!.isEmpty) return null;
    if (firmware == null || firmware!.isEmpty) return model;
    return '$model · fw $firmware';
  }

  factory CameraStatus.fromJson(Map<String, dynamic> json) {
    return CameraStatus(
      enabled: json['enabled'] == true,
      reachable: json['reachable'] == true,
      host: json['host']?.toString() ?? '-',
      message: json['message']?.toString() ?? '',
      model: json['model']?.toString(),
      firmware: json['firmware']?.toString(),
      homeSupported: json['home_supported'] == true,
      audioSupported: json['audio_supported'] == true,
      audioNote: json['audio_note']?.toString(),
      talkbackSupported: json['talkback_supported'] == true,
      talkbackNote: json['talkback_note']?.toString(),
      // เซิร์ฟเวอร์รุ่นเก่าไม่ส่งสี่ฟิลด์นี้มา ค่าที่ได้จึงต้องแปลว่า
      // "ยังพูดไม่ได้" ไม่ใช่พังทั้งหน้าจอ
      talkbackReady: json['talkback_ready'] == true,
      talkbackTransport: json['talkback_transport']?.toString(),
      talkbackTokenPath: json['talkback_token_path']?.toString(),
      talkbackStreamId: _asInt(json['talkback_stream_id']),
    );
  }
}

/// อ่านตัวเลขจาก JSON ที่อาจมาเป็น int, double หรือ string
int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// ตั๋วอายุสั้นสำหรับเปิดสาย TiRTC ไปหาลำโพงกล้อง (POST /camera/talkback/token)
///
/// เซิร์ฟเวอร์เป็นคนเซ็นและเป็นคนล็อกว่าปลายทางคือกล้องตัวไหน แอปไม่มีสิทธิ์
/// เลือกเอง — `remote_id` ที่ได้มาจึงเป็นค่าที่เชื่อถือได้ ไม่ใช่ค่าที่แอปส่งไป
///
/// **ห้ามเก็บลง SharedPreferences, log, analytics หรือ crash report**
/// ต้องขอใหม่ทุกครั้งที่เริ่มพูด เพราะอายุสั้นมาก (ราว 2 นาที)
class CameraTalkbackSession {
  final String provider;
  final String appId;
  final String remoteId;
  final String token;
  final int streamId;

  /// codec/อัตราสุ่ม/จำนวนช่อง ที่เซิร์ฟเวอร์สั่งให้ใช้ — ต้องตรงกับที่กล้องรอฟัง
  final String audioCodec;
  final int sampleRateHz;
  final int channels;

  /// เวลาหมดอายุของ token (unix seconds ตามที่เซิร์ฟเวอร์บอก)
  final int expiresAt;

  const CameraTalkbackSession({
    required this.provider,
    required this.appId,
    required this.remoteId,
    required this.token,
    required this.streamId,
    this.audioCodec = 'g711a',
    this.sampleRateHz = 16000,
    this.channels = 1,
    this.expiresAt = 0,
  });

  factory CameraTalkbackSession.fromJson(Map<String, dynamic> json) {
    return CameraTalkbackSession(
      provider: json['provider']?.toString() ?? '',
      appId: json['app_id']?.toString() ?? '',
      remoteId: json['remote_id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      streamId: _asInt(json['stream_id']) ?? 14,
      audioCodec: json['audio_codec']?.toString() ?? 'g711a',
      sampleRateHz: _asInt(json['sample_rate_hz']) ?? 16000,
      channels: _asInt(json['channels']) ?? 1,
      expiresAt: _asInt(json['expires_at']) ?? 0,
    );
  }

  /// ครบพอจะเปิดสายได้ไหม — เซิร์ฟเวอร์ตั้งค่าไม่ครบแล้วส่งช่องว่างมาก็มี
  bool get isUsable =>
      appId.isNotEmpty && remoteId.isNotEmpty && token.isNotEmpty;

  /// ไม่ใส่ token ลงใน toString — กัน log/crash report ดูดค่าไปโดยไม่ตั้งใจ
  @override
  String toString() =>
      'CameraTalkbackSession(provider: $provider, streamId: $streamId, '
      'codec: $audioCodec, sampleRate: $sampleRateHz, channels: $channels)';
}

/// ภาพนิ่ง 1 เฟรมจากเซิร์ฟเวอร์ พร้อม "อายุ" ที่เซิร์ฟเวอร์บอกมา
///
/// เซิร์ฟเวอร์ใช้ภาพร่วมกันทุกคนและเก็บภาพล่าสุดไว้ส่งต่อตอนกล้องสะดุด
/// อายุจึงเป็นตัวบอกว่ากำลังดูภาพสดหรือภาพค้าง — ไม่ใช่เดาจากเวลาที่แอปได้รับ
class CameraFrame {
  final Uint8List bytes;
  final Duration age;

  const CameraFrame(this.bytes, this.age);

  /// เก่ากว่านี้ = เซิร์ฟเวอร์ส่งภาพเก็บไว้มาให้ เพราะดึงจากกล้องรอบนี้ไม่ผ่าน
  static const Duration staleAfter = Duration(seconds: 3);

  bool get isStale => age >= staleAfter;
}

/// ทิศที่สั่งกล้องได้ — ต้องตรงกับ CameraPtzAction ฝั่ง backend
class CameraAction {
  static const String up = 'up';
  static const String down = 'down';
  static const String left = 'left';
  static const String right = 'right';
  static const String zoomIn = 'zoom_in';
  static const String zoomOut = 'zoom_out';
  static const String home = 'home';
  static const String stop = 'stop';
}
