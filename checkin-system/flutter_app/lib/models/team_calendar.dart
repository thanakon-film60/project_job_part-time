import 'json.dart';

/// พนักงาน 1 คนที่ลงเวลาในวันนั้น (/reports/team-calendar)
class TeamCalendarPerson {
  final int employeeId;
  final String employeeCode;
  final String fullName;

  /// เวลาที่ backend ส่งมาพร้อม offset +07:00 แล้ว
  final DateTime? firstIn;
  final DateTime? lastOut;

  /// ป้ายสถานที่ของวันนั้น เรียงมาแล้วจาก backend (ที่ทำงานก่อน แล้วค่อยบ้าน)
  final List<String> locations;

  /// วันนั้นมีแต่การลงเวลาที่บ้าน = ไม่ได้ไปทำงาน
  final bool homeOnly;
  final int count;

  /// เคยลงทะเบียนใบหน้าอ้างอิงไว้แล้วหรือยัง
  final bool faceEnrolled;

  const TeamCalendarPerson({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    required this.locations,
    required this.homeOnly,
    required this.count,
    this.faceEnrolled = true,
    this.firstIn,
    this.lastOut,
  });

  factory TeamCalendarPerson.fromJson(Map<String, dynamic> json) {
    final locations = json['locations'];
    return TeamCalendarPerson(
      employeeId: asInt(json['employee_id']),
      employeeCode: asText(json['employee_code']) ?? '-',
      fullName: asText(json['full_name']) ?? '-',
      locations: locations is List
          ? locations.map((item) => item.toString()).toList(growable: false)
          : const [],
      homeOnly: asBool(json['home_only']),
      count: asInt(json['count']),
      faceEnrolled: asEnrolled(json['face_enrolled']),
      firstIn: parseServerDateTime(json['first_in']),
      lastOut: parseServerDateTime(json['last_out']),
    );
  }
}

/// พนักงานที่ "ยังไม่ได้ยืนยันตัวตน" ของวันนั้น (ไม่มีการลงเวลาเลย)
///
/// ข้อความเตือนที่ใช้คู่กันอยู่ใน widgets/duty_warning_card.dart
class TeamCalendarMissing {
  final int employeeId;
  final String employeeCode;
  final String fullName;
  final bool faceEnrolled;

  const TeamCalendarMissing({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    required this.faceEnrolled,
  });

  factory TeamCalendarMissing.fromJson(Map<String, dynamic> json) {
    return TeamCalendarMissing(
      employeeId: asInt(json['employee_id']),
      employeeCode: asText(json['employee_code']) ?? '-',
      fullName: asText(json['full_name']) ?? '-',
      faceEnrolled: asEnrolled(json['face_enrolled']),
    );
  }
}

/// อ่าน face_enrolled แบบ "ไม่มีค่ามา = ถือว่าลงทะเบียนแล้ว"
///
/// asBool() คืน false เมื่อคีย์หายไป ซึ่งจะกลายเป็นการกล่าวหาพนักงานทุกคนว่า
/// ไม่ได้ลงทะเบียนใบหน้า ตอนแอปรุ่นใหม่คุยกับ backend รุ่นเก่าที่ยังไม่ส่งคีย์นี้
bool asEnrolled(Object? value) => value != false;

/// 1 วันในปฏิทินรวมของหัวหน้า
class TeamCalendarDay {
  /// คีย์วันที่รูปแบบ YYYY-MM-DD ตามเวลาไทย
  final String date;
  final List<TeamCalendarPerson> people;

  /// คนที่วันนั้นไม่มีการลงเวลาเลย — ยังไม่ได้ยืนยันตัวตน
  final List<TeamCalendarMissing> missing;

  const TeamCalendarDay({
    required this.date,
    required this.people,
    this.missing = const [],
  });

  factory TeamCalendarDay.fromJson(Map<String, dynamic> json) {
    return TeamCalendarDay(
      date: asText(json['date']) ?? '',
      people: mapList(json['people'], TeamCalendarPerson.fromJson),
      missing: mapList(json['missing'], TeamCalendarMissing.fromJson),
    );
  }
}

/// ปฏิทินรวมทั้งเดือน — จัด index ตามวันที่ไว้ให้ตารางเรียกใช้ได้ทันที
class TeamCalendarMonth {
  final int year;
  final int month;
  final List<TeamCalendarDay> days;

  const TeamCalendarMonth({
    required this.year,
    required this.month,
    required this.days,
  });

  Map<String, TeamCalendarDay> get byDate =>
      {for (final day in days) day.date: day};

  /// จำนวนพนักงาน (ไม่ซ้ำ) ที่ลงเวลาในเดือนนี้
  int get activeEmployees =>
      days.expand((day) => day.people).map((p) => p.employeeId).toSet().length;

  /// วันที่มีคนลงเวลาจริง — days รวมวันที่มีแต่คนขาดมาด้วย จึงนับตรงๆ ไม่ได้
  int get daysWithCheckins =>
      days.where((day) => day.people.isNotEmpty).length;

  factory TeamCalendarMonth.fromJson(Map<String, dynamic> json) {
    return TeamCalendarMonth(
      year: asInt(json['year']),
      month: asInt(json['month']),
      days: mapList(json['days'], TeamCalendarDay.fromJson),
    );
  }
}

/// 1 วันในปฏิทินรายบุคคล (/reports/calendar)
class EmployeeCalendarDay {
  final String date;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final bool withinGeofence;
  final bool homeOnly;
  final int count;

  const EmployeeCalendarDay({
    required this.date,
    required this.withinGeofence,
    required this.homeOnly,
    required this.count,
    this.firstIn,
    this.lastOut,
  });

  factory EmployeeCalendarDay.fromJson(Map<String, dynamic> json) {
    return EmployeeCalendarDay(
      date: asText(json['date']) ?? '',
      withinGeofence: asBool(json['within_geofence']),
      homeOnly: asBool(json['home_only']),
      count: asInt(json['count']),
      firstIn: parseServerDateTime(json['first_in']),
      lastOut: parseServerDateTime(json['last_out']),
    );
  }
}

/// ปฏิทินรายบุคคลทั้งเดือน
class EmployeeCalendarMonth {
  final int employeeId;
  final int year;
  final int month;
  final List<EmployeeCalendarDay> days;

  const EmployeeCalendarMonth({
    required this.employeeId,
    required this.year,
    required this.month,
    required this.days,
  });

  Map<String, EmployeeCalendarDay> get byDate =>
      {for (final day in days) day.date: day};

  factory EmployeeCalendarMonth.fromJson(Map<String, dynamic> json) {
    return EmployeeCalendarMonth(
      employeeId: asInt(json['employee_id']),
      year: asInt(json['year']),
      month: asInt(json['month']),
      days: mapList(json['days'], EmployeeCalendarDay.fromJson),
    );
  }
}
