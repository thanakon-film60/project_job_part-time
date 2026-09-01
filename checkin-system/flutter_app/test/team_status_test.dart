import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/models/employee.dart';
import 'package:thanakon_box_checkin/models/live_location.dart';
import 'package:thanakon_box_checkin/models/team_calendar.dart';
import 'package:thanakon_box_checkin/services/team_status.dart';

/// วันที่ใช้ทดสอบ — ตัวเลขวันไม่สำคัญ ขอแค่ทุกก้อนอ้างวันเดียวกัน
final DateTime _today = DateTime(2026, 8, 30);

EmployeeProfile _profile(
  int id,
  String name, {
  bool isManager = false,
  bool profileComplete = true,
}) {
  return EmployeeProfile(
    id: id,
    employeeCode: 'EMP00$id',
    fullName: name,
    email: 'emp$id@example.com',
    isManager: isManager,
    profileComplete: profileComplete,
  );
}

TeamCalendarPerson _person(
  int id,
  String name, {
  bool homeOnly = false,
  bool faceEnrolled = true,
}) {
  return TeamCalendarPerson(
    employeeId: id,
    employeeCode: 'EMP00$id',
    fullName: name,
    locations: homeOnly ? const ['อยู่ที่บ้าน'] : const ['MARDODI'],
    homeOnly: homeOnly,
    count: 2,
    faceEnrolled: faceEnrolled,
    firstIn: DateTime.utc(2026, 8, 30, 1, 15), // 08:15 เวลาไทย
    lastOut: DateTime.utc(2026, 8, 30, 10, 2), // 17:02 เวลาไทย
  );
}

LiveLocation _live(int id, String name, LiveStatus status) {
  return LiveLocation(
    employeeId: id,
    employeeCode: 'EMP00$id',
    fullName: name,
    isManager: false,
    status: status,
    latitude: 13.92,
    longitude: 100.51,
    withinGeofence: true,
    officeName: 'MARDODI',
    secondsAgo: 30,
  );
}

void main() {
  // -----------------------------------------------------------------
  // การรวมข้อมูลสามเส้นให้เป็นรายชื่อทีมของหัวหน้า
  // (TeamStatus.merge — ใช้ทั้งแท็บภาพรวมทีมและแท็บข้อมูลพนักงาน)
  // -----------------------------------------------------------------
  group('TeamStatus.merge', () {
    TeamStatus build() {
      return TeamStatus.merge(
        today: _today,
        employees: [
          _profile(1, 'ก พนักงาน'),
          _profile(2, 'ข พนักงาน', profileComplete: false),
          _profile(3, 'ค พนักงาน'),
          _profile(9, 'หัวหน้า ใหญ่', isManager: true),
        ],
        todayInCalendar: TeamCalendarDay(
          date: thaiDateKey(_today),
          people: [
            _person(1, 'ก พนักงาน'),
            _person(3, 'ค พนักงาน', homeOnly: true),
          ],
          missing: const [
            TeamCalendarMissing(
              employeeId: 2,
              employeeCode: 'EMP002',
              fullName: 'ข พนักงาน',
              faceEnrolled: false,
            ),
          ],
        ),
        live: LiveLocationsSnapshot(
          employees: [
            _live(1, 'ก พนักงาน', LiveStatus.online),
            _live(3, 'ค พนักงาน', LiveStatus.offline),
          ],
        ),
      );
    }

    test('บัญชีหัวหน้าไม่อยู่ในรายชื่อ แต่ถูกนับแยกไว้', () {
      final status = build();

      expect(status.members.length, 3);
      expect(status.members.any((member) => member.id == 9), isFalse);
      expect(status.managerCount, 1);
    });

    test('แยกสถานะของวันนี้ได้ถูกต้อง', () {
      final status = build();
      final byId = {for (final member in status.members) member.id: member};

      expect(byId[1]!.duty, DutyState.working);
      expect(byId[3]!.duty, DutyState.home); // ลงเวลาแต่ที่บ้าน = ไม่ได้มาทำงาน
      expect(byId[2]!.duty, DutyState.absent);

      expect(status.countOf(DutyState.working), 1);
      expect(status.countOf(DutyState.home), 1);
      expect(status.countOf(DutyState.absent), 1);
      // "ลงเวลาแล้ว" นับคนที่ลงไว้ที่บ้านด้วย
      expect(status.present.length, 2);
      expect(status.absent.single.id, 2);
    });

    test('คนที่ยังไม่ลงเวลาขึ้นก่อนเสมอ', () {
      expect(build().members.first.id, 2);
    });

    test('รู้ว่าใครยังไม่ได้ลงทะเบียนใบหน้า', () {
      final status = build();
      final byId = {for (final member in status.members) member.id: member};

      expect(byId[2]!.faceEnrolled, isFalse);
      expect(byId[1]!.faceEnrolled, isTrue);
      expect(status.withoutFace.single.id, 2);
    });

    test('ต่อพิกัดล่าสุดเข้ากับพนักงานคนเดียวกัน', () {
      final status = build();
      final byId = {for (final member in status.members) member.id: member};

      expect(byId[1]!.liveStatus, LiveStatus.online);
      expect(byId[1]!.whereText, 'ในเขต MARDODI');
      expect(status.onlineCount, 1);

      // คนที่แอปยังไม่เคยส่งพิกัดมาเลยต้องไม่พัง — แค่ไม่มีข้อมูล
      expect(byId[2]!.liveStatus, LiveStatus.noData);
      expect(byId[2]!.whereText, isNull);
    });

    test('วันที่ปฏิทินยังไม่มีช่องของวันนี้ = ทุกคนยังไม่ลงเวลา', () {
      final status = TeamStatus.merge(
        today: _today,
        employees: [_profile(1, 'ก พนักงาน'), _profile(2, 'ข พนักงาน')],
        todayInCalendar: null,
        live: const LiveLocationsSnapshot(employees: []),
      );

      expect(status.countOf(DutyState.absent), 2);
      // ไม่มีข้อมูลใบหน้ามาด้วย = ยังไม่ตั้งข้อกล่าวหาว่าไม่ได้ลงทะเบียน
      expect(status.withoutFace, isEmpty);
    });
  });
}
