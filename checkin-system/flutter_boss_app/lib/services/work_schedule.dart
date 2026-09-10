import '../config.dart';
import 'attendance_service.dart';

/// ผลตัดสินการลงเวลา — ชื่อ code ตรงกับฝั่ง backend (app/work_schedule.py)
/// ('late' เป็นคำสงวนของ Dart จึงตั้งชื่อ lateArrival)
enum AttendanceStatus {
  onTime('on_time'),
  lateArrival('late'),
  earlyLeave('early_leave'),
  complete('complete'),
  notApplicable('not_applicable');

  final String code;
  const AttendanceStatus(this.code);
}

/// ผลตัดสินการลงเวลา 1 ครั้ง
class AttendanceVerdict {
  final AttendanceStatus status;

  /// นาทีที่สาย หรือ ออกก่อนเวลา (0 ถ้าไม่เข้าเงื่อนไขนั้น)
  final int minutes;

  /// ข้อความสั้นสำหรับแสดงบนหน้าจอ เช่น "สาย 12 นาที"
  final String label;

  const AttendanceVerdict({
    required this.status,
    required this.minutes,
    required this.label,
  });

  static const AttendanceVerdict none = AttendanceVerdict(
    status: AttendanceStatus.notApplicable,
    minutes: 0,
    label: '',
  );

  bool get isLate => status == AttendanceStatus.lateArrival;
  bool get isEarlyLeave => status == AttendanceStatus.earlyLeave;

  /// มีเกณฑ์ให้ตัดสินไหม (false = อยู่บ้าน หรือบริษัทปิดฟีเจอร์ไว้)
  bool get applies => status != AttendanceStatus.notApplicable;

  /// ต้องเน้นสีแดง/ส้มให้ผู้ใช้เห็นไหม
  bool get needsAttention => isLate || isEarlyLeave;
}

/// ตัดสิน "สาย / ตรงเวลา" ฝั่งแอป
///
/// ตรรกะชุดเดียวกับ backend/app/work_schedule.py — แอปคำนวณเองเพื่อให้ป้ายบน
/// หน้าจอขึ้นทันทีโดยไม่ต้องรอ API รอบใหม่ ส่วนข้อความที่ส่งเข้ากลุ่ม LINE
/// ยังตัดสินที่ backend เหมือนเดิม (แหล่งความจริงเดียวคือเกณฑ์ใน .env)
///
/// เกณฑ์ล่าสุดโหลดมาจาก /reports/geofence พร้อมรายการสถานที่ (ดู ApiService)
class WorkScheduleService {
  static WorkSchedule _schedule = Config.workSchedule;

  static WorkSchedule get schedule => _schedule;

  /// อัปเดตเกณฑ์จาก backend — เรียกตอนโหลดรายการสถานที่
  static void update(WorkSchedule? latest) {
    if (latest != null) _schedule = latest;
  }

  /// ตัดสินรายการลงเวลา 1 รายการ
  ///
  /// อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่มีสาย/ไม่มีออกก่อน (ตรงกับ notify_checkin)
  static AttendanceVerdict evaluateRecord(CheckInRecord record) {
    if (record.atHome) return AttendanceVerdict.none;
    return evaluate(kind: record.kind, thaiTime: record.thaiTime);
  }

  /// [thaiTime] ต้องเป็นเวลาไทยแล้ว (Config.toThai) ไม่ใช่ UTC ดิบจาก backend
  static AttendanceVerdict evaluate({
    required String kind,
    required DateTime thaiTime,
  }) {
    final s = _schedule;
    if (!s.enabled) return AttendanceVerdict.none;

    final nowMinutes = thaiTime.hour * 60 + thaiTime.minute;

    if (kind == 'in') {
      // ผ่อนผันเป็นแค่ "เส้นตัดสิน" ว่าจะเรียกว่าสายไหม แต่จำนวนนาทีที่รายงาน
      // นับจากเวลาเข้างานจริง (08:30) เพราะนั่นคือตัวเลขที่ HR ใช้
      final deadline = s.startMinutes + s.lateGraceMinutes;
      if (nowMinutes > deadline) {
        final lateBy = nowMinutes - s.startMinutes;
        return AttendanceVerdict(
          status: AttendanceStatus.lateArrival,
          minutes: lateBy,
          label: 'สาย ${humanMinutes(lateBy)}',
        );
      }
      final earlyBy = s.startMinutes - nowMinutes;
      return AttendanceVerdict(
        status: AttendanceStatus.onTime,
        minutes: 0,
        label: earlyBy <= 0
            ? 'ตรงเวลา'
            : 'ตรงเวลา (ก่อนเวลา ${humanMinutes(earlyBy)})',
      );
    }

    if (kind == 'out') {
      final threshold = s.endMinutes - s.earlyLeaveGraceMinutes;
      if (nowMinutes < threshold) {
        final earlyBy = s.endMinutes - nowMinutes;
        return AttendanceVerdict(
          status: AttendanceStatus.earlyLeave,
          minutes: earlyBy,
          label: 'ออกก่อนเวลา ${humanMinutes(earlyBy)}',
        );
      }
      final overtime = nowMinutes - s.endMinutes;
      return AttendanceVerdict(
        status: AttendanceStatus.complete,
        minutes: overtime < 0 ? 0 : overtime,
        label: overtime <= 0
            ? 'ครบเวลางาน'
            : 'ครบเวลางาน (เกินเวลา ${humanMinutes(overtime)})',
      );
    }

    return AttendanceVerdict.none;
  }

  /// สรุปของทั้งวัน — ยึด "เข้างานครั้งแรก" เป็นตัวตัดสินว่าวันนี้สายไหม
  /// (กดเข้างานซ้ำหลายรอบก็ยังนับครั้งแรกครั้งเดียว เหมือน DayAttendance._pair)
  static AttendanceVerdict evaluateDay(DayAttendance? day) {
    final firstIn = day?.firstCheckIn;
    if (firstIn == null) return AttendanceVerdict.none;
    return evaluateRecord(firstIn);
  }
}

/// 12 -> "12 นาที" / 95 -> "1 ชม. 35 นาที"
String humanMinutes(int total) {
  final safe = total < 0 ? 0 : total;
  final hours = safe ~/ 60;
  final minutes = safe % 60;
  if (hours == 0) return '$minutes นาที';
  if (minutes == 0) return '$hours ชม.';
  return '$hours ชม. $minutes นาที';
}
