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

  /// พูดกลับออกลำโพงกล้องได้ไหม
  ///
  /// กล้องที่ใช้อยู่ตอนนี้ตอบว่าไม่ได้ — ไม่มีลำโพงและไม่เปิด RTSP backchannel
  /// เก็บเป็นฟิลด์ไว้เผื่อเปลี่ยนไปใช้กล้องที่มีลำโพง แอปจะได้ไม่ต้องแก้
  final bool talkbackSupported;

  const CameraStatus({
    required this.enabled,
    required this.reachable,
    required this.host,
    required this.message,
    this.model,
    this.firmware,
    this.homeSupported = false,
    this.audioSupported = false,
    this.talkbackSupported = false,
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
      talkbackSupported: json['talkback_supported'] == true,
    );
  }
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
