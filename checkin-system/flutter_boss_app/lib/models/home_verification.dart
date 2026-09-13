/// ผลการยืนยันตัวตนตอนอยู่บ้าน (ดู DAILY_HOME_FACE_VERIFICATION_2026-09-11.md)
///
/// **อยู่บ้าน = ไม่ได้ไปทำงาน** โมเดลนี้จึงจงใจไม่มีเวลาเข้างาน เวลาออกงาน
/// สถานะสาย/ตรงเวลา หรือชั่วโมงทำงาน — และห้ามเพิ่มเข้ามาภายหลัง
/// `verifiedAt` คือ **"เวลายืนยันตัวตน"** ไม่ใช่เวลาเข้างาน
library;

class HomeVerification {
  final int id;
  final String requestId;
  final String status;
  final String category;
  final String? officeName;

  /// เวลาที่ server บันทึกหลักฐาน — เก็บเป็น UTC เสมอ
  /// ใช้ [verifiedAtLocal] ตอนแสดงผล อย่าเอาค่านี้ไปโชว์ตรง ๆ
  final DateTime verifiedAt;

  /// วันตามเวลาไทยที่ server ตัดให้ (`YYYY-MM-DD`) — ใช้จัดกลุ่มรายวัน
  /// ห้ามคำนวณเองจากนาฬิกาเครื่อง
  final String localDate;

  final double? distanceKm;
  final double? locationAccuracyM;

  const HomeVerification({
    required this.id,
    required this.requestId,
    required this.status,
    required this.category,
    required this.verifiedAt,
    required this.localDate,
    this.officeName,
    this.distanceKm,
    this.locationAccuracyM,
  });

  bool get isVerified => status == 'verified';

  /// เวลาไทยสำหรับแสดงผล (`Asia/Bangkok` = UTC+7)
  ///
  /// แปลงจาก UTC ตรง ๆ แทนการใช้ `toLocal()` เพราะเครื่องผู้ใช้อาจตั้ง
  /// timezone ไว้ผิด แล้วจะอ่านเป็นคนละเวลากับที่หัวหน้าเห็นบนเว็บ
  DateTime get verifiedAtLocal =>
      verifiedAt.toUtc().add(const Duration(hours: 7));

  // `as num?` จะโยน exception ถ้า JSON ส่งชนิดผิดมา (เช่น id เป็นสตริง)
  // ซึ่งจะทำให้ทั้งหน้าพังแทนที่จะเสียแค่ค่าเดียว — เช็คชนิดก่อนเสมอ
  static int _toInt(Object? value) => value is num ? value.toInt() : 0;

  static double? _toDouble(Object? value) =>
      value is num ? value.toDouble() : null;

  static DateTime _parseUtc(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return DateTime.now().toUtc();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return DateTime.now().toUtc();
    // backend ส่งลงท้ายด้วย Z อยู่แล้ว แต่กันกรณีที่ไม่มีแล้ว Dart อ่านเป็น local
    return parsed.isUtc ? parsed : DateTime.utc(
      parsed.year, parsed.month, parsed.day,
      parsed.hour, parsed.minute, parsed.second,
    );
  }

  factory HomeVerification.fromJson(Map<String, dynamic> json) {
    return HomeVerification(
      id: _toInt(json['id']),
      requestId: json['request_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      category: json['category']?.toString() ?? 'home',
      officeName: json['office_name']?.toString(),
      verifiedAt: _parseUtc(json['verified_at']),
      localDate: json['local_date']?.toString() ?? '',
      distanceKm: _toDouble(json['distance_km']),
      locationAccuracyM: _toDouble(json['location_accuracy_m']),
    );
  }
}

/// สถานะรายวันจาก `GET /home-verifications/me`
class HomeVerificationDay {
  /// วันที่ถาม (เวลาไทย)
  final String date;

  /// **วันปัจจุบันของ server** — ถ้าไม่ตรงกับที่แอปคิดเอง ให้เชื่อค่านี้
  final String serverDate;

  final bool verified;
  final List<HomeVerification> verifications;

  const HomeVerificationDay({
    required this.date,
    required this.serverDate,
    required this.verified,
    required this.verifications,
  });

  /// รายการล่าสุดของวัน (ยืนยันซ้ำได้ รายการก่อนหน้ายังเป็นประวัติ)
  HomeVerification? get latest =>
      verifications.isEmpty ? null : verifications.first;

  bool get isToday => date == serverDate;

  factory HomeVerificationDay.fromJson(Map<String, dynamic> json) {
    final items = (json['verifications'] as List?) ?? const [];
    return HomeVerificationDay(
      date: json['date']?.toString() ?? '',
      serverDate: json['server_date']?.toString() ?? '',
      verified: json['verified'] == true,
      verifications: items
          .whereType<Map>()
          .map((item) => HomeVerification.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
    );
  }
}

/// โจทย์ที่ server ออกให้ก่อนเปิดกล้อง (`POST /home-verifications/challenges`)
class HomeVerificationChallenge {
  final String challengeId;

  /// คำสั่งที่ต้องแสดงและให้ผู้ใช้ทำตอนสแกน
  ///
  /// ⚠️ **server ตรวจไม่ได้ว่าทำจริงไหม** การบังคับอยู่ที่แอปทั้งหมด
  final String action;

  /// รหัสท่าแบบอ่านด้วยเครื่อง เช่น `blink` / `turn_left`
  ///
  /// null ได้ — backend รุ่นที่ deploy อยู่ยังไม่ส่งค่านี้ แอปจะถอยไปเดา
  /// จากข้อความไทยใน [action] แทน **ห้ามทำให้เป็นค่าบังคับ** ไม่งั้นแอปจะพัง
  /// กับเซิร์ฟเวอร์ที่ใช้งานจริงอยู่ตอนนี้
  final String? actionCode;

  final DateTime expiresAt;

  /// ยังไม่มีใบหน้าอ้างอิง = ต้องพาไปลงทะเบียนก่อน อย่าปล่อยให้สแกนแล้วโดนปฏิเสธ
  final bool faceEnrolled;

  const HomeVerificationChallenge({
    required this.challengeId,
    required this.action,
    required this.expiresAt,
    required this.faceEnrolled,
    this.actionCode,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  factory HomeVerificationChallenge.fromJson(Map<String, dynamic> json) {
    final code = json['action_code']?.toString();
    return HomeVerificationChallenge(
      challengeId: json['challenge_id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'หันหน้าตรงกล้อง',
      actionCode: (code == null || code.isEmpty) ? null : code,
      expiresAt: HomeVerification._parseUtc(json['expires_at']),
      faceEnrolled: json['face_enrolled'] == true,
    );
  }
}
