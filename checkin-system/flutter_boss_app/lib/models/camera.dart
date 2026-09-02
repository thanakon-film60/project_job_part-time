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
  });

  /// สั่งกล้องได้ก็ต่อเมื่อเปิดระบบไว้ และเซิร์ฟเวอร์ต่อกล้องติด
  bool get canControl => enabled && reachable;

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
    );
  }
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
