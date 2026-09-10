import 'package:flutter_test/flutter_test.dart';
import 'package:thanakon_box_checkin/config.dart';
import 'package:thanakon_box_checkin/services/work_schedule.dart';

/// เวลาไทยของวันทำงานหนึ่งวัน (10 ก.ย. 2026)
DateTime at(int hour, int minute) => DateTime(2026, 9, 10, hour, minute);

void main() {
  setUp(() {
    // คืนเกณฑ์กลับเป็นค่าเริ่มต้น 08:30-17:30 ก่อนทุกเทสต์
    WorkScheduleService.update(Config.workSchedule);
  });

  group('เข้างาน', () {
    test('ก่อนเวลา = ตรงเวลา และบอกว่ามาก่อนกี่นาที', () {
      final v = WorkScheduleService.evaluate(kind: 'in', thaiTime: at(8, 15));
      expect(v.status, AttendanceStatus.onTime);
      expect(v.isLate, isFalse);
      expect(v.label, 'ตรงเวลา (ก่อนเวลา 15 นาที)');
    });

    test('ตรง 08:30 พอดี ยังไม่สาย', () {
      final v = WorkScheduleService.evaluate(kind: 'in', thaiTime: at(8, 30));
      expect(v.status, AttendanceStatus.onTime);
      expect(v.label, 'ตรงเวลา');
    });

    test('08:31 = สาย 1 นาที (ไม่มีผ่อนผัน)', () {
      final v = WorkScheduleService.evaluate(kind: 'in', thaiTime: at(8, 31));
      expect(v.isLate, isTrue);
      expect(v.minutes, 1);
      expect(v.label, 'สาย 1 นาที');
    });

    test('สายเกินชั่วโมงแสดงเป็น ชม. + นาที', () {
      final v = WorkScheduleService.evaluate(kind: 'in', thaiTime: at(10, 5));
      expect(v.minutes, 95);
      expect(v.label, 'สาย 1 ชม. 35 นาที');
    });

    test('มีผ่อนผัน 15 นาที: 08:40 ยังไม่สาย แต่ 08:46 สายนับจาก 08:30', () {
      WorkScheduleService.update(
        const WorkSchedule(
          startMinutes: 8 * 60 + 30,
          endMinutes: 17 * 60 + 30,
          lateGraceMinutes: 15,
        ),
      );
      expect(
        WorkScheduleService.evaluate(kind: 'in', thaiTime: at(8, 40)).status,
        AttendanceStatus.onTime,
      );
      final late =
          WorkScheduleService.evaluate(kind: 'in', thaiTime: at(8, 46));
      expect(late.isLate, isTrue);
      // นาทีที่รายงานนับจากเวลาเข้างานจริง ไม่ใช่จากเส้นผ่อนผัน
      expect(late.minutes, 16);
    });
  });

  group('ออกงาน', () {
    test('ก่อน 17:30 = ออกก่อนเวลา', () {
      final v = WorkScheduleService.evaluate(kind: 'out', thaiTime: at(16, 30));
      expect(v.isEarlyLeave, isTrue);
      expect(v.minutes, 60);
      expect(v.label, 'ออกก่อนเวลา 1 ชม.');
    });

    test('ตรง 17:30 = ครบเวลางาน', () {
      final v = WorkScheduleService.evaluate(kind: 'out', thaiTime: at(17, 30));
      expect(v.status, AttendanceStatus.complete);
      expect(v.label, 'ครบเวลางาน');
    });

    test('หลัง 17:30 บอกเวลาที่เกิน', () {
      final v = WorkScheduleService.evaluate(kind: 'out', thaiTime: at(18, 45));
      expect(v.status, AttendanceStatus.complete);
      expect(v.label, 'ครบเวลางาน (เกินเวลา 1 ชม. 15 นาที)');
    });
  });

  group('กรณีที่ไม่ตัดสิน', () {
    test('บริษัทปิดฟีเจอร์ไว้', () {
      WorkScheduleService.update(
        const WorkSchedule(
          startMinutes: 8 * 60 + 30,
          endMinutes: 17 * 60 + 30,
          enabled: false,
        ),
      );
      final v = WorkScheduleService.evaluate(kind: 'in', thaiTime: at(10, 0));
      expect(v.applies, isFalse);
    });

    test('kind แปลกปลอมไม่ทำให้พัง', () {
      expect(
        WorkScheduleService.evaluate(kind: 'xxx', thaiTime: at(10, 0)).applies,
        isFalse,
      );
    });
  });

  group('WorkSchedule.parseHhmm', () {
    test('อ่าน "08:30" ได้', () {
      expect(WorkSchedule.parseHhmm('08:30', 0), 510);
    });

    test('ค่าผิดรูปแบบถอยไปใช้ fallback', () {
      for (final bad in ['', '8', 'aa:bb', '25:00', '08:99', null]) {
        expect(WorkSchedule.parseHhmm(bad, 510), 510, reason: 'input=$bad');
      }
    });

    test('rangeText อ่านง่าย', () {
      expect(Config.workSchedule.rangeText, '08:30 - 17:30 น.');
    });
  });
}
