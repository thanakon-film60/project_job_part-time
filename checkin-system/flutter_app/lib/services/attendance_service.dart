import '../config.dart';
import 'api_service.dart';

/// การลงเวลา 1 ครั้ง (เข้างานหรือออกงาน) ที่ backend บันทึกไว้
class CheckInRecord {
  final int id;
  final String kind; // "in" = เข้างาน, "out" = ออกงาน
  final DateTime timestamp; // เวลา UTC ตามที่ backend เก็บ
  final double distanceKm;
  final bool withinGeofence;
  final String? officeName;

  const CheckInRecord({
    required this.id,
    required this.kind,
    required this.timestamp,
    required this.distanceKm,
    required this.withinGeofence,
    this.officeName,
  });

  bool get isCheckIn => kind == 'in';

  /// เวลาไทยของรายการนี้ (ใช้ทั้งตอนตัดวันและตอนแสดงผล)
  DateTime get thaiTime => Config.toThai(timestamp);

  /// รายการที่แปลงไม่ได้ (ไม่มีเวลา) จะคืน null แล้วให้ผู้เรียกข้ามไป
  static CheckInRecord? fromJson(Map<String, dynamic> json) {
    final timestamp = ApiService.parseServerTimestamp(json['timestamp']);
    if (timestamp == null) return null;
    return CheckInRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() == 'out' ? 'out' : 'in',
      timestamp: timestamp,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      withinGeofence: json['within_geofence'] == true,
      officeName: json['office_name']?.toString(),
    );
  }
}

/// ช่วงเวลาทำงาน 1 ช่วง = เข้างาน 1 ครั้ง คู่กับออกงานครั้งถัดไป
///
/// ยังไม่ได้กดออกงาน (checkOut == null) ถือว่า "กำลังทำงานอยู่"
/// แล้วนับเวลาถึงตอนนี้ ไม่ใช่ข้ามช่วงนั้นไป
class WorkSession {
  final CheckInRecord checkIn;
  final CheckInRecord? checkOut;

  const WorkSession({required this.checkIn, this.checkOut});

  bool get isOpen => checkOut == null;

  /// [now] ต้องเป็นเวลาจริงของเครื่อง (DateTime.now()) ไม่ใช่เวลาไทยที่บวก +7 มาแล้ว
  /// ไม่งั้นช่วงที่ยังไม่ปิดจะเกินจริงไป 7 ชั่วโมง
  Duration durationAt([DateTime? now]) =>
      (checkOut?.timestamp ?? now ?? DateTime.now())
          .difference(checkIn.timestamp);
}

/// สรุปการลงเวลาของพนักงานคนนี้ใน 1 วัน (ตัดวันตามเวลาไทย)
class DayAttendance {
  /// วันที่ของสรุปก้อนนี้ตามเวลาไทย (เที่ยงคืนตรง)
  final DateTime day;

  /// รายการลงเวลาทั้งหมดของวันนั้น เรียงจากเช้าไปเย็น
  final List<CheckInRecord> records;

  /// ช่วงเวลาทำงานที่จับคู่เข้า-ออกแล้ว
  final List<WorkSession> sessions;

  const DayAttendance({
    required this.day,
    required this.records,
    required this.sessions,
  });

  bool get isEmpty => records.isEmpty;

  /// กดเข้างานแล้วแต่ยังไม่ได้กดออกงาน
  bool get isWorking => sessions.any((session) => session.isOpen);

  CheckInRecord? get firstCheckIn {
    for (final record in records) {
      if (record.isCheckIn) return record;
    }
    return null;
  }

  CheckInRecord? get lastCheckOut {
    for (final record in records.reversed) {
      if (!record.isCheckIn) return record;
    }
    return null;
  }

  /// รวมเวลาทำงานถึงตอนนี้ — ช่วงที่ยังไม่ปิดจะนับถึง [now] (ปกติคือ DateTime.now())
  Duration workedAt([DateTime? now]) {
    final at = now ?? DateTime.now();
    return sessions.fold(
      Duration.zero,
      (total, session) => total + session.durationAt(at),
    );
  }

  /// จับคู่เข้า-ออกจากรายการลงเวลาดิบ
  ///
  /// เผื่อกรณีที่เกิดขึ้นจริง: กดเข้างานซ้ำสองครั้ง (ยึดครั้งแรก) หรือ
  /// มีออกงานโดยไม่มีเข้างานคู่กัน (ข้ามไป แต่ยังโชว์ในรายการ)
  static List<WorkSession> _pair(List<CheckInRecord> records) {
    final sessions = <WorkSession>[];
    CheckInRecord? openedAt;
    for (final record in records) {
      if (record.isCheckIn) {
        openedAt ??= record;
        continue;
      }
      if (openedAt != null) {
        sessions.add(WorkSession(checkIn: openedAt, checkOut: record));
        openedAt = null;
      }
    }
    if (openedAt != null) sessions.add(WorkSession(checkIn: openedAt));
    return sessions;
  }

  factory DayAttendance.forDay(DateTime thaiDay, List<CheckInRecord> all) {
    final day = DateTime(thaiDay.year, thaiDay.month, thaiDay.day);
    final records = all
        .where((record) => _isSameThaiDay(record.thaiTime, day))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return DayAttendance(
      day: day,
      records: records,
      sessions: _pair(records),
    );
  }

  static bool _isSameThaiDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class AttendanceService {
  /// รายการลงเวลาของ "วันนี้" ตามเวลาไทย
  static Future<DayAttendance> today() async {
    final raw = await ApiService.fetchMyCheckIns();
    final records = raw
        .map(CheckInRecord.fromJson)
        .whereType<CheckInRecord>()
        .toList(growable: false);
    return DayAttendance.forDay(Config.thaiNow(), records);
  }
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// เวลาไทยแบบ 08:15 (รับค่า UTC จาก backend มาแปลงให้เอง)
String thaiClock(DateTime timestamp) {
  final thai = Config.toThai(timestamp);
  return '${_pad(thai.hour)}:${_pad(thai.minute)}';
}

/// วันที่แบบไทย 25/08/2568
String thaiDate(DateTime thaiDay) =>
    '${_pad(thaiDay.day)}/${_pad(thaiDay.month)}/${thaiDay.year + 543}';

/// ระยะเวลาแบบอ่านง่าย: 3 ชม. 05 น. / 45 นาที
String humanDuration(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  if (hours == 0) return '$minutes นาที';
  return '$hours ชม. ${_pad(minutes)} น.';
}
