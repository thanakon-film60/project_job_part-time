import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/config.dart';
import 'package:thanakon_box_checkin/main.dart';
import 'package:thanakon_box_checkin/services/api_service.dart';
import 'package:thanakon_box_checkin/services/attendance_service.dart';
import 'package:thanakon_box_checkin/services/location_service.dart';

void main() {
  testWidgets('THANAKON-BOX app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const ThanakonBoxApp());

    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });

  test('checkout geofence ignores offices that disallow checkout', () {
    final (trackingOffice, _, trackingWithin) =
        LocationService.nearestOffice(13.8865664, 100.5066278);
    expect(trackingOffice.name, 'ถึงบ้านแล้ว');
    expect(trackingOffice.allowCheckout, isFalse);
    expect(trackingWithin, isTrue);

    final (workOffice, _, workWithin) = LocationService.nearestOffice(
      13.8865664,
      100.5066278,
      workOnly: true,
    );
    expect(workOffice.allowCheckout, isTrue);
    expect(workOffice.name, isNot('ถึงบ้านแล้ว'));
    expect(workWithin, isFalse);
  });

  test('server timestamps without timezone are treated as UTC', () {
    final parsed = ApiService.parseServerTimestamp('2026-08-21T04:41:00');

    expect(parsed, isNotNull);
    expect(parsed!.isUtc, isTrue);
    expect(parsed.toUtc().hour, 4);
    expect(parsed.toUtc().minute, 41);
  });

  test('server timestamps with timezone keep their absolute instant', () {
    final parsed = ApiService.parseServerTimestamp('2026-08-21T11:41:00+07:00');

    expect(parsed, isNotNull);
    expect(parsed!.toUtc().hour, 4);
    expect(parsed.toUtc().minute, 41);
  });

  // 4 ทุ่มเวลาไทย = 15:00 UTC — เทียบเป็น UTC จะได้ไม่ขึ้นกับ timezone ของเครื่องที่รัน test
  test('session ends at 22:00 Thai time on the same day', () {
    // 17:00 น. เวลาไทย ของวันที่ 24 ส.ค.
    final end = ApiService.nextSessionEnd(DateTime.utc(2026, 8, 24, 10));

    expect(end.toUtc(), DateTime.utc(2026, 8, 24, 15));
  });

  test('after 22:00 Thai time the session ends the next day', () {
    // 23:00 น. เวลาไทย — เลย 4 ทุ่มมาแล้ว ต้องข้ามไปวันถัดไป
    final end = ApiService.nextSessionEnd(DateTime.utc(2026, 8, 24, 16));

    expect(end.toUtc(), DateTime.utc(2026, 8, 25, 15));
  });

  test('exactly 22:00 Thai time rolls over to the next day', () {
    final end = ApiService.nextSessionEnd(DateTime.utc(2026, 8, 24, 15));

    expect(end.toUtc(), DateTime.utc(2026, 8, 25, 15));
  });

  test('a minute before 22:00 Thai time still ends today', () {
    final end = ApiService.nextSessionEnd(DateTime.utc(2026, 8, 24, 14, 59));

    expect(end.toUtc(), DateTime.utc(2026, 8, 24, 15));
  });

  // -----------------------------------------------------------------
  // สรุปการลงเวลาของวันนี้ (การ์ด "การลงเวลาวันนี้" บนหน้าแรก)
  //
  // เวลาที่ใช้ทดสอบเป็น UTC ล้วน — ผลลัพธ์จึงไม่ขึ้นกับ timezone ของเครื่องที่รัน test
  // 24 ส.ค. 01:00 UTC = 08:00 น. เวลาไทยของวันที่ 24
  // -----------------------------------------------------------------
  CheckInRecord record(String kind, DateTime utc) => CheckInRecord(
        id: utc.millisecondsSinceEpoch,
        kind: kind,
        timestamp: utc,
        distanceKm: 0.1,
        withinGeofence: true,
        officeName: 'MARDODI',
      );

  test('today list keeps only records of the same Thai day', () {
    final day = DateTime.utc(2026, 8, 25, 3); // 10:00 น. ของวันที่ 25
    final attendance = DayAttendance.forDay(Config.toThai(day), [
      record('in', DateTime.utc(2026, 8, 24, 17)), // 25 ส.ค. 00:00 น. ไทย
      record('out', DateTime.utc(2026, 8, 25, 10)), // 25 ส.ค. 17:00 น. ไทย
      record('in', DateTime.utc(2026, 8, 24, 16)), // ยังเป็นวันที่ 24 (23:00 น.)
      record('in', DateTime.utc(2026, 8, 25, 17)), // ข้ามไปวันที่ 26 แล้ว
    ]);

    expect(attendance.records.length, 2);
    expect(thaiClock(attendance.records.first.timestamp), '00:00');
    expect(thaiClock(attendance.records.last.timestamp), '17:00');
  });

  test('checked-in and checked-out pairs add up to the worked time', () {
    final day = DateTime.utc(2026, 8, 25, 3);
    final attendance = DayAttendance.forDay(Config.toThai(day), [
      record('in', DateTime.utc(2026, 8, 25, 1)), // 08:00 น.
      record('out', DateTime.utc(2026, 8, 25, 5)), // 12:00 น.
      record('in', DateTime.utc(2026, 8, 25, 6)), // 13:00 น.
      record('out', DateTime.utc(2026, 8, 25, 10)), // 17:00 น.
    ]);

    expect(attendance.sessions.length, 2);
    expect(attendance.isWorking, isFalse);
    expect(attendance.workedAt(), const Duration(hours: 8));
    expect(thaiClock(attendance.firstCheckIn!.timestamp), '08:00');
    expect(thaiClock(attendance.lastCheckOut!.timestamp), '17:00');
  });

  test('an open session is counted up to now', () {
    final now = DateTime.utc(2026, 8, 25, 5); // 12:00 น.
    final attendance = DayAttendance.forDay(Config.toThai(now), [
      record('in', DateTime.utc(2026, 8, 25, 1)), // 08:00 น.
    ]);

    expect(attendance.isWorking, isTrue);
    expect(attendance.workedAt(now), const Duration(hours: 4));
    expect(humanDuration(attendance.workedAt(now)), '4 ชม. 00 น.');
  });

  test('a duplicate check-in does not open a second session', () {
    final now = DateTime.utc(2026, 8, 25, 5);
    final attendance = DayAttendance.forDay(Config.toThai(now), [
      record('in', DateTime.utc(2026, 8, 25, 1)), // 08:00 น.
      record('in', DateTime.utc(2026, 8, 25, 2)), // กดซ้ำ 09:00 น.
      record('out', DateTime.utc(2026, 8, 25, 4)), // 11:00 น.
    ]);

    expect(attendance.sessions.length, 1);
    expect(attendance.isWorking, isFalse);
    // ยึดการกดเข้างานครั้งแรกเป็นตัวเริ่มงาน
    expect(attendance.workedAt(now), const Duration(hours: 3));
  });

  test('an orphan check-out is shown but adds no worked time', () {
    final now = DateTime.utc(2026, 8, 25, 5);
    final attendance = DayAttendance.forDay(Config.toThai(now), [
      record('out', DateTime.utc(2026, 8, 25, 4)),
    ]);

    expect(attendance.records.length, 1);
    expect(attendance.sessions, isEmpty);
    expect(attendance.workedAt(now), Duration.zero);
  });

  test('durations read like a timesheet', () {
    expect(humanDuration(const Duration(minutes: 45)), '45 นาที');
    expect(humanDuration(const Duration(hours: 3, minutes: 5)), '3 ชม. 05 น.');
    expect(humanDuration(const Duration(seconds: -30)), '0 นาที');
  });
}
