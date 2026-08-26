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

  const TeamCalendarPerson({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    required this.locations,
    required this.homeOnly,
    required this.count,
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
      firstIn: parseServerDateTime(json['first_in']),
      lastOut: parseServerDateTime(json['last_out']),
    );
  }
}

/// 1 วันในปฏิทินรวมของหัวหน้า
class TeamCalendarDay {
  /// คีย์วันที่รูปแบบ YYYY-MM-DD ตามเวลาไทย
  final String date;
  final List<TeamCalendarPerson> people;

  const TeamCalendarDay({required this.date, required this.people});

  factory TeamCalendarDay.fromJson(Map<String, dynamic> json) {
    return TeamCalendarDay(
      date: asText(json['date']) ?? '',
      people: mapList(json['people'], TeamCalendarPerson.fromJson),
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
