import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thanakon_box_boss/models/home_verification.dart';
import 'package:thanakon_box_boss/services/api_service.dart'
    show endpointUnavailableCode, sessionExpiredCode;
import 'package:thanakon_box_boss/services/home_verification_service.dart';
import 'package:thanakon_box_boss/widgets/home_verification_card.dart';

/// ผลการยืนยันหนึ่งรายการตามรูปแบบจริงที่ backend ส่งมา
Map<String, dynamic> verificationJson({
  int id = 1,
  String verifiedAt = '2026-09-11T08:11:02Z',
  String localDate = '2026-09-11',
  String office = 'ถึงบ้านแล้ว',
}) =>
    {
      'id': id,
      'request_id': 'req-$id',
      'status': 'verified',
      'category': 'home',
      'office_name': office,
      'verified_at': verifiedAt,
      'local_date': localDate,
      'timezone': 'Asia/Bangkok',
      'distance_km': 0.0631,
      'location_accuracy_m': 12.5,
    };

Map<String, dynamic> dayJson({
  bool verified = false,
  List<Map<String, dynamic>> items = const [],
  String date = '2026-09-11',
  String? serverDate,
}) =>
    {
      'date': date,
      'server_date': serverDate ?? date,
      'server_time': '2026-09-11T08:20:00Z',
      'timezone': 'Asia/Bangkok',
      'verified': verified,
      'verifications': items,
    };

void main() {
  group('HomeVerification — แปลงข้อมูลจาก server', () {
    test('อ่านฟิลด์ครบและรู้ว่ายืนยันแล้ว', () {
      final v = HomeVerification.fromJson(verificationJson());
      expect(v.id, 1);
      expect(v.isVerified, isTrue);
      expect(v.category, 'home');
      expect(v.officeName, 'ถึงบ้านแล้ว');
      expect(v.localDate, '2026-09-11');
    });

    test('แปลงเป็นเวลาไทย +7 ไม่ใช้ timezone ของเครื่อง', () {
      // 08:11 UTC = 15:11 ตามเวลาไทย ไม่ว่าเครื่องจะตั้ง timezone อะไร
      final v = HomeVerification.fromJson(
        verificationJson(verifiedAt: '2026-09-11T08:11:02Z'),
      );
      expect(v.verifiedAtLocal.hour, 15);
      expect(v.verifiedAtLocal.minute, 11);
    });

    test('เวลาที่ไม่มี Z ต่อท้าย ต้องยังถือเป็น UTC ไม่ใช่เวลาเครื่อง', () {
      final v = HomeVerification.fromJson(
        verificationJson(verifiedAt: '2026-09-11T08:11:02'),
      );
      expect(v.verifiedAtLocal.hour, 15);
    });

    test('ข้อมูลพังไม่ทำให้แอปล่ม', () {
      final v = HomeVerification.fromJson({'id': 'ไม่ใช่ตัวเลข'});
      expect(v.id, 0);
      expect(v.isVerified, isFalse);
    });
  });

  group('HomeVerificationDay — สถานะรายวัน', () {
    test('ยังไม่ยืนยัน = verified false และไม่มีรายการ', () {
      final day = HomeVerificationDay.fromJson(dayJson());
      expect(day.verified, isFalse);
      expect(day.latest, isNull);
    });

    test('ยืนยันหลายครั้งในวันเดียว เก็บครบและ latest คือรายการแรกในลิสต์', () {
      final day = HomeVerificationDay.fromJson(dayJson(
        verified: true,
        items: [verificationJson(id: 9), verificationJson(id: 4)],
      ));
      expect(day.verifications.length, 2);
      expect(day.latest!.id, 9);
    });

    test('วันที่ถามไม่ตรงกับวันของ server ต้องรู้ว่าไม่ใช่วันนี้', () {
      final day = HomeVerificationDay.fromJson(
        dayJson(date: '2026-09-10', serverDate: '2026-09-11'),
      );
      expect(day.isToday, isFalse);
    });
  });

  group('request_id', () {
    test('เป็น UUID v4 รูปแบบถูกต้อง', () {
      final id = HomeVerificationService.newRequestId();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id),
        isTrue,
        reason: 'ได้ $id',
      );
    });

    test('ยาวไม่เกิน 36 ตัวตามที่ backend รับ', () {
      expect(HomeVerificationService.newRequestId().length, 36);
    });

    test('ไม่ซ้ำกัน', () {
      final ids = List.generate(200, (_) => HomeVerificationService.newRequestId());
      expect(ids.toSet().length, 200);
    });
  });

  group('HomeVerifyResult — แยกวิธีแก้ตาม error code', () {
    test('โจทย์ใช้ไม่ได้แล้ว ต้องขอโจทย์ใหม่', () {
      for (final code in ['challenge_used', 'challenge_expired', 'challenge_invalid']) {
        final r = HomeVerifyResult.rejected('x', code: code);
        expect(r.needsNewChallenge, isTrue, reason: code);
      }
    });

    test('ยังไม่ลงทะเบียนใบหน้า ต้องพาไปลงทะเบียน', () {
      final r = HomeVerifyResult.rejected('x', code: 'face_not_enrolled');
      expect(r.needsFaceEnrollment, isTrue);
      expect(r.needsNewChallenge, isFalse);
    });

    test('รูปใช้ซ้ำหรือใช้ไม่ได้ ต้องถ่ายใหม่', () {
      expect(HomeVerifyResult.rejected('x', code: 'evidence_reused').needsNewPhoto, isTrue);
      expect(HomeVerifyResult.rejected('x', code: 'evidence_invalid').needsNewPhoto, isTrue);
    });

    test('นอกเขตบ้าน แยกออกจากกรณีอื่น', () {
      final r = HomeVerifyResult.rejected('x', code: 'outside_home');
      expect(r.isOutsideHome, isTrue);
      expect(r.needsNewPhoto, isFalse);
    });

    test('ไม่รู้ผล ต้องไม่ถูกนับเป็นสำเร็จหรือล้มเหลว', () {
      final r = HomeVerifyResult.unknown('เน็ตหลุด');
      expect(r.outcome, HomeVerifyOutcome.unknown);
      expect(r.verification, isNull);
    });
  });

  group('การ์ดสถานะ — ข้อความต้องไม่สื่อว่าเป็นการเข้างาน', () {
    Future<void> pump(WidgetTester tester, Widget card) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card))),
        );

    testWidgets('ยังไม่ยืนยัน — ชวนให้สแกน ไม่มีช่องเวลาเข้า/ออก', (tester) async {
      await pump(
        tester,
        HomeVerificationCard(
          day: HomeVerificationDay.fromJson(dayJson()),
          onVerify: () {},
          onRetryLoad: () {},
        ),
      );
      expect(find.textContaining('วันนี้ยังไม่ได้ยืนยันตัวตน'), findsOneWidget);
      expect(find.textContaining('เข้างาน'), findsNothing);
      expect(find.textContaining('ออกงาน'), findsNothing);
      expect(find.textContaining('สาย'), findsNothing);
    });

    testWidgets('ยืนยันแล้ว — เรียก "เวลายืนยันตัวตน" ไม่ใช่เวลาเข้างาน', (tester) async {
      await pump(
        tester,
        HomeVerificationCard(
          day: HomeVerificationDay.fromJson(
            dayJson(verified: true, items: [verificationJson()]),
          ),
          onVerify: () {},
          onRetryLoad: () {},
        ),
      );
      expect(find.textContaining('ยืนยันตัวตนแล้ว'), findsOneWidget);
      expect(find.textContaining('เวลายืนยันตัวตน 15:11'), findsOneWidget);
      // ห้ามมีป้ายประเมินเวลางานหรือช่องเวลาเข้า-ออก
      // (ประโยคปฏิเสธ "ไม่คิดชั่วโมงทำงาน" มีได้ เอกสารหัวข้อ 5 บังคับให้บอกไว้)
      expect(find.textContaining('เวลาเข้างาน'), findsNothing);
      expect(find.textContaining('ครบเวลางาน'), findsNothing);
      expect(find.textContaining('ตรงเวลา'), findsNothing);
      expect(find.textContaining('ออกก่อนเวลา'), findsNothing);
      expect(
        find.textContaining('ไม่นับเป็นการเข้างาน ไม่มีเวลาเข้า–ออก และไม่คิดชั่วโมงทำงาน'),
        findsOneWidget,
      );
    });

    testWidgets('ยืนยันแล้วยังต้องกดยืนยันซ้ำได้ ปุ่มห้ามถูกปิด', (tester) async {
      var tapped = 0;
      await pump(
        tester,
        HomeVerificationCard(
          day: HomeVerificationDay.fromJson(
            dayJson(verified: true, items: [verificationJson()]),
          ),
          onVerify: () => tapped++,
          onRetryLoad: () {},
        ),
      );
      await tester.tap(find.text('ยืนยันสถานะอีกครั้ง'));
      expect(tapped, 1);
    });

    testWidgets('กำลังส่งอยู่ ปุ่มถูกปิดกันกดซ้ำ', (tester) async {
      var tapped = 0;
      await pump(
        tester,
        HomeVerificationCard(
          day: HomeVerificationDay.fromJson(dayJson()),
          busy: true,
          onVerify: () => tapped++,
          onRetryLoad: () {},
        ),
      );
      await tester.tap(
        find.text('ยืนยันว่าอยู่บ้าน / ไม่ได้ไปทำงาน'),
        warnIfMissed: false,
      );
      expect(tapped, 0);
    });

    testWidgets('โหลดไม่สำเร็จ ต้องบอกว่าไม่ทราบผล ไม่ใช่ว่ายังไม่ได้ยืนยัน',
        (tester) async {
      await pump(
        tester,
        HomeVerificationCard(
          day: null,
          loadFailed: true,
          onVerify: () {},
          onRetryLoad: () {},
        ),
      );
      expect(find.textContaining('ยังตรวจสอบผลการยืนยันไม่ได้'), findsOneWidget);
      expect(find.textContaining('ยังไม่ได้ยืนยันตัวตน'), findsNothing);
    });

    testWidgets('เซิร์ฟเวอร์ยังไม่อัปเดต ต้องไม่โทษอินเทอร์เน็ตของผู้ใช้', (tester) async {
      await pump(
        tester,
        HomeVerificationCard(
          day: null,
          loadFailed: true,
          failureCode: endpointUnavailableCode,
          onVerify: () {},
          onRetryLoad: () {},
        ),
      );
      expect(find.textContaining('ฟีเจอร์นี้ยังไม่พร้อมใช้งาน'), findsOneWidget);
      expect(find.textContaining('ไม่ใช่ปัญหาอินเทอร์เน็ตของคุณ'), findsOneWidget);
      // ห้ามใช้ข้อความเดิมที่ทำให้ผู้ใช้ไปไล่สลับ Wi-Fi/เน็ตมือถือวนไม่จบ
      expect(find.textContaining('เชื่อมต่อเพื่ออ่านสถานะไม่สำเร็จ'), findsNothing);
      expect(find.textContaining('ยังไม่ได้ยืนยันตัวตน'), findsNothing);
    });

    testWidgets('เซสชันหมดอายุ ต้องบอกให้เข้าสู่ระบบใหม่ ไม่ใช่ให้กดลองใหม่',
        (tester) async {
      await pump(
        tester,
        HomeVerificationCard(
          day: null,
          loadFailed: true,
          failureCode: sessionExpiredCode,
          onVerify: () {},
          onRetryLoad: () {},
        ),
      );
      expect(find.textContaining('เซสชันหมดอายุ'), findsOneWidget);
      expect(find.textContaining('เข้าสู่ระบบใหม่'), findsOneWidget);
      // กดลองใหม่ไม่ช่วยอะไรถ้า token หมดอายุ ปุ่มจึงต้องไม่มี
      expect(find.textContaining('ลองอีกครั้ง'), findsNothing);
    });

    testWidgets('เน็ตหลุด (ไม่มี code) ยังใช้ข้อความเดิมและกดลองใหม่ได้', (tester) async {
      var retried = 0;
      await pump(
        tester,
        HomeVerificationCard(
          day: null,
          loadFailed: true,
          onVerify: () {},
          onRetryLoad: () => retried++,
        ),
      );
      expect(find.textContaining('ยังตรวจสอบผลการยืนยันไม่ได้'), findsOneWidget);
      await tester.tap(find.text('ลองอีกครั้ง'));
      expect(retried, 1);
    });

    testWidgets('ยังโหลดไม่เสร็จ ต้องไม่กล่าวหาว่ายังไม่ยืนยัน', (tester) async {
      await pump(
        tester,
        HomeVerificationCard(day: null, onVerify: () {}, onRetryLoad: () {}),
      );
      expect(find.textContaining('กำลังตรวจสถานะ'), findsOneWidget);
      expect(find.textContaining('ยังไม่ได้ยืนยันตัวตน'), findsNothing);
    });

    testWidgets('ยืนยันหลายครั้ง แสดงครบทุกเวลา', (tester) async {
      await pump(
        tester,
        HomeVerificationCard(
          day: HomeVerificationDay.fromJson(dayJson(verified: true, items: [
            verificationJson(id: 2, verifiedAt: '2026-09-11T10:00:00Z'),
            verificationJson(id: 1, verifiedAt: '2026-09-11T08:11:02Z'),
          ])),
          onVerify: () {},
          onRetryLoad: () {},
        ),
      );
      expect(find.textContaining('ยืนยันวันนี้ 2 ครั้ง'), findsOneWidget);
    });
  });
}
