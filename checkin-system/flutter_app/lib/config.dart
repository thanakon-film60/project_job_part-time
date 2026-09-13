class Config {
  // ---------------------------------------------------------------
  // เวอร์ชันของแอปที่ติดตั้งอยู่
  //
  // ต้องแก้ให้ตรงกับ version: ใน pubspec.yaml ทุกครั้งที่ปล่อยเวอร์ชันใหม่
  // (อ่านจาก pubspec ตอนรันไม่ได้ถ้าไม่เพิ่ม package_info_plus ซึ่งไม่คุ้ม
  // กับการเพิ่ม native plugin แค่เพื่อโชว์ตัวเลขบรรทัดเดียว)
  // แอปเอาไปเทียบกับ /app/info เพื่อบอกพนักงานว่ามีตัวใหม่ให้อัปเดตหรือยัง
  // ---------------------------------------------------------------
  static const String appVersion = "1.7.0";

  // ---------------------------------------------------------------
  // production: ผ่าน Cloudflare Tunnel -> IIS :80 -> backend
  // Cloudflare จัดการ HTTPS/SSL ให้อัตโนมัติ เหมาะกับ iOS App Transport Security
  // ที่บังคับ HTTPS (ดู deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md)
  //
  // เรียก API ได้ตรง ๆ ไม่มี /api นำหน้า เช่น
  //   POST https://thanakronpart-time.com/auth/login
  //   GET  https://thanakronpart-time.com/reports/calendar
  //
  // ตอนพัฒนาบนเครื่องตัวเอง ให้สลับไปใช้บรรทัดที่คอมเมนต์ไว้แทน:
  //   Android emulator : http://10.0.2.2:8002
  //   iOS simulator    : http://localhost:8002
  // ---------------------------------------------------------------
  //
  // ตอนทดสอบกับ backend บนเครื่องตัวเอง ไม่ต้องแก้ไฟล์นี้ — ส่งทาง --dart-define
  // แทน แล้วค่า production จะยังเป็นค่าเริ่มต้นอยู่เหมือนเดิม:
  //   มือถือต่อสาย USB : adb reverse tcp:8002 tcp:8002
  //                      flutter run --dart-define=API_BASE=http://localhost:8002
  //   Android emulator : flutter run --dart-define=API_BASE=http://10.0.2.2:8002
  // ---------------------------------------------------------------
  static const String apiBase = String.fromEnvironment(
    "API_BASE",
    defaultValue: "https://thanakronpart-time.com",
  );

  // ---------------------------------------------------------------
  // สถานที่ fallback ถ้าโหลด /reports/geofence จาก backend ไม่ได้
  //
  // ตัวตัดสินจริงคือ backend และแอปจะพยายามดึง OFFICES ล่าสุดตอนเปิดหน้าแรก/ก่อนกดยืนยัน
  // ---------------------------------------------------------------
  static const List<Office> offices = [
    Office(
      name: "Motta & Montipa (Head office)",
      lat: 13.9040518,
      lng: 100.5391995,
      radiusKm: 0.5,
      category: "work",
    ),
  ];

  // ---------------------------------------------------------------
  // เวลาทำงานมาตรฐาน — fallback ถ้าโหลด /reports/geofence ไม่ได้
  //
  // ตัวตัดสินจริงคือ backend (WORK_START_TIME / WORK_END_TIME ใน .env)
  // ค่าตรงนี้ใช้แค่ตอนเปิดแอปครั้งแรกหรือเน็ตหลุด เพื่อให้หน้าจอยังบอก
  // "สาย/ตรงเวลา" ได้ ไม่ใช่ค้างเป็นขีดกลาง
  // ---------------------------------------------------------------
  static const WorkSchedule workSchedule = WorkSchedule(
    startMinutes: 8 * 60 + 30,    // 08:30 น.
    endMinutes: 17 * 60 + 30,     // 17:30 น.
  );

  // ของเดิม เก็บไว้ให้โค้ดส่วนที่ยังอ้างถึงอยู่ไม่พัง = สถานที่แรกในรายการ
  static double get officeLat => offices.first.lat;
  static double get officeLng => offices.first.lng;
  static double get geofenceRadiusKm => offices.first.radiusKm;

  // ช่วงเวลาส่งพิกัด GPS ต่อเนื่อง (วินาที)
  static const int pingIntervalSeconds = 60;

  // ---------------------------------------------------------------
  // การติดตามตำแหน่งตลอดเวลา (ตั้งแต่ล็อกอิน จนกว่าจะออกจากระบบ)
  //
  // อยู่บ้าน อยู่ออฟฟิศ หรือยังไม่ได้เช็คอิน ก็ส่งพิกัดเหมือนกันหมด
  // ระบบต้องรู้ว่าคนที่ล็อกอินค้างไว้ตอนนี้อยู่ตรงไหน
  // ---------------------------------------------------------------

  /// ping ล่าสุดเก่ากว่านี้ = ถือว่าการติดตามสะดุด (ปิด GPS / เน็ตหลุด / ระบบฆ่าแอป)
  static const Duration trackingStaleAfter = Duration(minutes: 5);

  /// ยังไม่ได้สิทธิ์ "อนุญาตตลอดเวลา" ให้ทวงซ้ำทุกๆ เท่านี้ จนกว่าจะได้หรือออกจากระบบ
  static const Duration locationPermissionNagInterval = Duration(minutes: 10);

  /// รีเฟรชรายการลงเวลาของวันนี้อัตโนมัติ
  static const Duration attendanceRefreshInterval = Duration(minutes: 2);

  /// จังหวะเดินนาฬิกา "รวมเวลาทำงานวันนี้" บนหน้าจอ
  static const Duration workedClockTick = Duration(seconds: 30);

  // ---------------------------------------------------------------
  // หมดเวลาใช้งานประจำวัน — ทุกคนถูกเด้งออกจากระบบตอน 4 ทุ่ม (22:00 น.)
  // แล้วต้องล็อกอินใหม่ในวันถัดไป
  //
  // กันเคสพนักงานลืมออกจากระบบ แล้วเครื่องส่งพิกัด GPS ต่อทั้งคืน
  // และกัน token ที่ค้างอยู่ในเครื่องที่ทำหาย ถูกใช้ต่อข้ามวัน
  //
  // ยึด "เวลาไทย" ไม่ใช่เวลาในเครื่อง — มือถือที่ตั้ง timezone ผิดจะได้หมดอายุ
  // พร้อมกับคนอื่น (ฝั่งเว็บก็แปลงเวลาด้วย +7 เหมือนกัน)
  // ---------------------------------------------------------------
  static const Duration thaiUtcOffset = Duration(hours: 7);
  static const int sessionEndHour = 22;   // 4 ทุ่ม
  static const int sessionEndMinute = 0;

  /// ข้อความที่ขึ้นบนหน้าล็อกอินเมื่อถูกเด้งออกเพราะหมดเวลาประจำวัน
  static const String sessionExpiredMessage =
      'หมดเวลาใช้งานประจำวัน (4 ทุ่ม) กรุณาเข้าสู่ระบบใหม่';

  /// เวลาไทยตอนนี้ — ไม่ขึ้นกับ timezone ที่ตั้งไว้ในเครื่อง
  /// (เครื่องที่ตั้งเวลาผิดจะได้ตัดวัน/นับชั่วโมงตรงกับฝั่งเซิร์ฟเวอร์)
  static DateTime thaiNow([DateTime? from]) =>
      (from ?? DateTime.now()).toUtc().add(thaiUtcOffset);

  /// เวลาที่ backend ส่งมา (UTC) -> เวลาไทย
  static DateTime toThai(DateTime timestamp) =>
      timestamp.toUtc().add(thaiUtcOffset);
}

/// สถานที่ที่เช็คอินได้ 1 แห่ง
class Office {
  final String name;
  final double lat;
  final double lng;
  final double radiusKm;
  final bool allowCheckout;

  /// หมวดของสถานที่จาก backend: work / hospital / home
  final String? category;

  const Office({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    this.allowCheckout = true,
    this.category,
  });

  /// ที่นี่คือ "บ้าน" — อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่มีเข้างาน/ออกงาน
  bool get isHome => isHomeLabel(category) || isHomeLabel(name);

  /// ที่ที่นับเป็นการมาทำงานจริง (ใช้ตัดสินทั้งเข้างานและออกงาน)
  bool get isWorkplace => allowCheckout && !isHome;

  /// ข้อความนี้หมายถึงบ้านหรือไม่ — ตรรกะเดียวกับ backend (geofence.py)
  /// ใช้กับทั้ง category และชื่อสถานที่ เพราะ config เก่าบางชุดไม่มี category
  static bool isHomeLabel(String? value) {
    final text = (value ?? '').trim().toLowerCase();
    if (text.isEmpty) return false;
    return text.contains('บ้าน') ||
        text.contains('home') ||
        text.contains('house');
  }

  factory Office.fromJson(Map<String, dynamic> json) {
    return Office(
      name: json['name']?.toString() ?? '-',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      radiusKm: (json['radius_km'] as num).toDouble(),
      allowCheckout: json['allow_checkout'] is bool
          ? json['allow_checkout'] as bool
          : true,
      category: json['category']?.toString(),
    );
  }
}

/// เกณฑ์เวลาทำงานที่ใช้ตัดสิน "สาย / ออกก่อนเวลา"
///
/// เก็บเป็น "นาทีนับจากเที่ยงคืน" ไม่ใช่ DateTime เพราะเป็นเวลาในวัน ไม่ผูกกับ
/// วันที่ใดวันหนึ่ง — เทียบตรงๆ กับเวลาไทยของรายการลงเวลาได้เลย
class WorkSchedule {
  /// เวลาเข้างาน (นาทีนับจากเที่ยงคืน) เช่น 08:30 = 510
  final int startMinutes;

  /// เวลาออกงาน (นาทีนับจากเที่ยงคืน) เช่น 17:30 = 1050
  final int endMinutes;

  /// ผ่อนผันกี่นาทีถึงเริ่มนับว่าสาย
  final int lateGraceMinutes;

  /// ออกก่อนเวลาเกินกี่นาทีถึงจะเตือน
  final int earlyLeaveGraceMinutes;

  /// false = บริษัทปิดการตัดสินสาย/ออกก่อนไว้ (หน้าจอจะไม่โชว์ป้าย)
  final bool enabled;

  const WorkSchedule({
    required this.startMinutes,
    required this.endMinutes,
    this.lateGraceMinutes = 0,
    this.earlyLeaveGraceMinutes = 0,
    this.enabled = true,
  });

  String get startText => _clock(startMinutes);
  String get endText => _clock(endMinutes);

  /// "08:30 - 17:30 น."
  String get rangeText => '$startText - $endText น.';

  static String _clock(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// แปลง "HH:MM" จาก backend เป็นนาที — ค่าผิดรูปแบบคืน [fallback]
  /// (ตรรกะเดียวกับ _parse_hhmm ใน backend/app/config.py)
  static int parseHhmm(Object? raw, int fallback) {
    final parts = (raw?.toString() ?? '').trim().split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return fallback;
    if (h < 0 || h > 23 || m < 0 || m > 59) return fallback;
    return h * 60 + m;
  }

  factory WorkSchedule.fromJson(Map<String, dynamic> json) {
    const fallback = Config.workSchedule;
    return WorkSchedule(
      startMinutes: parseHhmm(json['work_start'], fallback.startMinutes),
      endMinutes: parseHhmm(json['work_end'], fallback.endMinutes),
      lateGraceMinutes:
          (json['late_grace_minutes'] as num?)?.toInt() ?? 0,
      earlyLeaveGraceMinutes:
          (json['early_leave_grace_minutes'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }
}
