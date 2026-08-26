import 'package:flutter_test/flutter_test.dart';

import 'package:thanakon_box_checkin/models/directory.dart';
import 'package:thanakon_box_checkin/models/employee.dart';
import 'package:thanakon_box_checkin/models/json.dart';
import 'package:thanakon_box_checkin/models/live_location.dart';
import 'package:thanakon_box_checkin/services/employee_registration.dart';
import 'package:thanakon_box_checkin/services/thai_id.dart';

/// ที่อยู่ตัวอย่างที่ใช้แทนผลค้นจาก /addresses/postal-code/{code}
const ThaiAddress _sampleAddress = ThaiAddress(
  id: 1,
  postalCode: '11110',
  subdistrict: 'บางบัวทอง',
  district: 'บางบัวทอง',
  province: 'นนทบุรี',
);

/// ฟอร์มที่กรอกครบและถูกต้องทุกช่อง — แต่ละเทสต์ค่อยทำให้ผิดทีละอย่าง
RegistrationDraft validDraft() => RegistrationDraft()
  ..firstName = 'ธนกร'
  ..lastName = 'ทดสอบ'
  ..birthDate = DateTime(2000, 1, 15)
  // เลขบัตรตัวอย่างที่ผ่าน checksum (หลักที่ 13 คำนวณจาก 12 หลักแรก)
  ..nationalId = '110070015511${thaiIdCheckDigit('110070015511')}'
  ..phone = '0812345678'
  ..email = 'test@example.com'
  ..addressLine = '99/1 หมู่ 5'
  ..postalCode = '11110'
  ..address = _sampleAddress
  ..department = 'ฝ่ายปฏิบัติการ'
  ..position = 'พนักงานพาร์ตไทม์'
  ..startDate = DateTime(2026, 8, 1);

void main() {
  // -----------------------------------------------------------------
  // เลขบัตรประชาชนไทย — ตรรกะเดียวกับ backend (_valid_thai_id)
  // และเว็บ (lib/thai-id.js) ถ้าสามที่นี้ไม่ตรงกัน ผู้ใช้จะกรอกผ่านในแอป
  // แล้วไปโดน 422 ตอนกดบันทึก
  // -----------------------------------------------------------------
  group('เลขบัตรประชาชน', () {
    test('เลขที่ checksum ถูกต้องผ่านการตรวจ', () {
      final digit = thaiIdCheckDigit('110070015511');
      expect(digit, isNotNull);
      expect(validateThaiNationalId('110070015511$digit').valid, isTrue);
    });

    test('หลักตรวจสอบผิดไปหนึ่ง = ไม่ผ่าน', () {
      final digit = thaiIdCheckDigit('110070015511')!;
      final wrong = (digit + 1) % 10;
      final result = validateThaiNationalId('110070015511$wrong');

      expect(result.valid, isFalse);
      expect(result.message, contains('Checksum'));
    });

    test('เลขซ้ำทั้ง 13 หลักถูกปฏิเสธด้วยเหตุผลของตัวเอง', () {
      // ไม่มีเลขซ้ำ 13 หลักตัวไหนผ่าน checksum อยู่แล้ว กฎนี้จึงเป็นการกันซ้ำ
      // อีกชั้นให้ตรงกับ backend และเว็บ — ที่ต่างคือ "ข้อความบอกเหตุผล"
      // ผู้ใช้ที่พิมพ์ 1 รัวจะได้รู้ว่าพิมพ์มั่ว ไม่ใช่คิดว่าเลขจริงของตัวเองเสีย
      final result = validateThaiNationalId('1111111111111');

      expect(result.valid, isFalse);
      expect(result.message, contains('เลขซ้ำ'));
      expect(result.message, isNot(contains('Checksum')));
    });

    test('ความยาวไม่ครบ / มีตัวอักษร / ว่าง บอกสาเหตุคนละแบบ', () {
      expect(validateThaiNationalId('').message, contains('กรุณากรอก'));
      expect(validateThaiNationalId('11007001551').message, contains('13 หลัก'));
      expect(validateThaiNationalId('11007001551A').message, contains('ตัวเลข'));
    });

    test('หลักตรวจสอบคำนวณได้เฉพาะตัวเลข 12 หลัก', () {
      expect(thaiIdCheckDigit('1100700155'), isNull);
      expect(thaiIdCheckDigit('11007001551A'), isNull);
    });
  });

  // -----------------------------------------------------------------
  // ฟอร์มลงทะเบียนพนักงาน (พอร์ตจาก validateRegistration ฝั่งเว็บ)
  // -----------------------------------------------------------------
  group('ฟอร์มลงทะเบียนพนักงาน', () {
    test('ฟอร์มที่กรอกครบไม่มีข้อผิดพลาด', () {
      final errors = validateRegistration(
        validDraft(),
        addressOptions: const [_sampleAddress],
        lookup: AddressLookup.success,
      );

      expect(errors, isEmpty);
    });

    test('ยังค้นรหัสไปรษณีย์ไม่เสร็จ = ยังผ่านขั้นที่อยู่ไม่ได้', () {
      // กันเคสกดถัดไปเร็วกว่าผลค้นที่อยู่ แล้วไปเจอ 422 ตอนกดบันทึกจริง
      final errors = validateRegistration(
        validDraft(),
        lookup: AddressLookup.loading,
      );

      expect(errors['postalCode'], contains('กำลังตรวจสอบ'));
      expect(registrationStepValid(1, errors), isFalse);
    });

    test('ค้นที่อยู่ไม่สำเร็จ บอกให้ลองใหม่ ไม่ใช่บอกว่ารหัสผิด', () {
      final errors = validateRegistration(
        validDraft(),
        lookup: AddressLookup.error,
      );

      expect(errors['postalCode'], contains('ลองใหม่'));
    });

    test('รหัสไปรษณีย์ที่ไม่มีในฐานข้อมูลถูกปฏิเสธ', () {
      final errors = validateRegistration(
        validDraft(),
        addressOptions: const [],
        lookup: AddressLookup.success,
      );

      expect(errors['postalCode'], contains('ไม่พบรหัสไปรษณีย์'));
    });

    test('วันเกิดในอนาคตไม่ผ่าน', () {
      final draft = validDraft()
        ..birthDate = DateTime.now().add(const Duration(days: 1));
      final errors = validateRegistration(
        draft,
        addressOptions: const [_sampleAddress],
        lookup: AddressLookup.success,
      );

      expect(errors['birthDate'], contains('อนาคต'));
    });

    test('เบอร์โทรต้องขึ้นต้นด้วย 0 และยาว 9-10 หลัก', () {
      Map<String, String> check(String phone) => validateRegistration(
            validDraft()..phone = phone,
            addressOptions: const [_sampleAddress],
            lookup: AddressLookup.success,
          );

      expect(check('0812345678'), isNot(contains('phone')));
      expect(check('021234567'), isNot(contains('phone')));
      expect(check('812345678').containsKey('phone'), isTrue);
      expect(check('08123456').containsKey('phone'), isTrue);
    });

    test('ขั้นที่ยังกรอกไม่ครบถูกกันไว้ ขั้นที่ครบแล้วผ่าน', () {
      final draft = validDraft()
        ..firstName = ''
        ..department = '';
      final errors = validateRegistration(
        draft,
        addressOptions: const [_sampleAddress],
        lookup: AddressLookup.success,
      );

      expect(registrationStepValid(0, errors), isFalse); // ชื่อว่าง
      expect(registrationStepValid(1, errors), isTrue); // ที่อยู่ครบแล้ว
      expect(registrationStepValid(2, errors), isFalse); // ยังไม่เลือกแผนก
    });

    test('payload ที่ส่งไป backend ตรงรูปแบบของ EmployeeRegistrationIn', () {
      final payload = validDraft().toPayload();

      expect(payload['personalInfo'], {
        'firstName': 'ธนกร',
        'lastName': 'ทดสอบ',
        'birthDate': '2000-01-15',
        'nationalId': isA<String>(),
      });
      final contact = payload['contact'] as Map<String, dynamic>;
      expect(contact['email'], 'test@example.com');
      expect(contact['address'], {
        'addressLine': '99/1 หมู่ 5',
        'subdistrict': 'บางบัวทอง',
        'district': 'บางบัวทอง',
        'province': 'นนทบุรี',
        'postalCode': '11110',
      });
      expect(payload['employment'], {
        'department': 'ฝ่ายปฏิบัติการ',
        'position': 'พนักงานพาร์ตไทม์',
        'startDate': '2026-08-01',
      });
    });

    test('อีเมลถูกทำเป็นตัวพิมพ์เล็กก่อนส่ง (backend เก็บแบบ lower)', () {
      final draft = validDraft()..email = '  Test@Example.COM ';
      final contact = draft.toPayload()['contact'] as Map<String, dynamic>;

      expect(contact['email'], 'test@example.com');
    });
  });

  // -----------------------------------------------------------------
  // แก้ไขแฟ้มพนักงาน — PATCH รับเฉพาะช่องที่เปลี่ยนจริง
  // -----------------------------------------------------------------
  group('แก้ไขแฟ้มพนักงาน', () {
    EmployeeProfile existing() => EmployeeProfile(
          id: 7,
          employeeCode: 'EMP007',
          fullName: 'ธนกร ทดสอบ',
          email: 'test@example.com',
          isManager: false,
          profileComplete: true,
          birthDate: DateTime(2000, 1, 15),
          nationalIdMasked: '*********1234',
          phone: '0812345678',
          addressLine: '99/1 หมู่ 5',
          postalCode: '11110',
          subdistrict: 'บางบัวทอง',
          district: 'บางบัวทอง',
          province: 'นนทบุรี',
          department: 'ฝ่ายปฏิบัติการ',
          position: 'พนักงานพาร์ตไทม์',
          startDate: DateTime(2026, 8, 1),
        );

    test('ไม่แก้อะไรเลย = ไม่มีอะไรต้องส่ง', () {
      // ถ้าส่งไปทั้งก้อน backend จะบันทึก Timeline ว่า "แก้ไขข้อมูล" ทั้งที่ไม่ได้แก้
      expect(ProfileEditDraft.from(existing()).changedFields(), isEmpty);
    });

    test('ส่งเฉพาะช่องที่เปลี่ยนจริง', () {
      final draft = ProfileEditDraft.from(existing())
        ..phone = '0899999999'
        ..position = 'หัวหน้าทีม';

      expect(draft.changedFields(), {
        'phone': '0899999999',
        'position': 'หัวหน้าทีม',
      });
    });

    test('เว้นเลขบัตรว่างไว้ = ใช้เลขเดิม ไม่ส่งไปด้วย', () {
      final draft = ProfileEditDraft.from(existing());

      expect(draft.nationalIdRequired, isFalse);
      expect(draft.changedFields().containsKey('nationalId'), isFalse);
      expect(draft.validate(), isNull);
    });

    test('บัญชีเดิมที่ยังไม่มีเลขบัตร ต้องกรอกก่อนถึงจะบันทึกได้', () {
      final legacy = EmployeeProfile(
        id: 8,
        employeeCode: 'EMP008',
        fullName: 'บัญชีเดิม ทดสอบ',
        email: 'legacy@example.com',
        isManager: false,
        profileComplete: false,
        birthDate: DateTime(1999, 5, 5),
        phone: '0812345678',
        addressLine: '1/1',
        postalCode: '11110',
        subdistrict: 'บางบัวทอง',
        district: 'บางบัวทอง',
        province: 'นนทบุรี',
        department: 'ฝ่ายบุคคล',
        position: 'หัวหน้าทีม',
        startDate: DateTime(2025, 1, 1),
      );
      final draft = ProfileEditDraft.from(legacy);

      expect(draft.nationalIdRequired, isTrue);
      expect(draft.validate(), contains('เลขบัตรประชาชน'));

      draft.nationalId = '110070015511${thaiIdCheckDigit('110070015511')}';
      expect(draft.validate(), isNull);
    });

    test('เลขบัตรใหม่ที่ checksum ไม่ผ่าน ถูกกันตั้งแต่ในแอป', () {
      final draft = ProfileEditDraft.from(existing())
        ..nationalId = '1111111111111';

      expect(draft.validate(), contains('เลขซ้ำ'));
    });

    test('เปลี่ยนรหัสไปรษณีย์ ล้างตำบล/อำเภอ/จังหวัดที่เลือกไว้', () {
      // ที่อยู่เดิมไม่ใช่ของรหัสใหม่ ถ้าไม่ล้าง backend จะตอบ 422
      final draft = ProfileEditDraft.from(existing())..setPostalCode('10200');

      expect(draft.address, isNull);
      expect(draft.subdistrict, isEmpty);
      expect(draft.validate(), contains('ให้ครบทุกช่อง'));
    });
  });

  // -----------------------------------------------------------------
  // เวลาจาก backend — บาง endpoint ส่ง ISO ที่ไม่มี timezone ติดมา
  // ซึ่งค่าจริงเป็น UTC (ตรรกะเดียวกับ thaiFrom ฝั่งเว็บ)
  // -----------------------------------------------------------------
  group('เวลาที่ backend ส่งมา', () {
    test('ไม่มี timezone = ตีความเป็น UTC', () {
      final parsed = parseServerDateTime('2026-08-21T04:41:00');

      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, 4);
    });

    test('มี offset +07:00 = เก็บช่วงเวลาเดิมไว้', () {
      final parsed = parseServerDateTime('2026-08-21T11:41:00+07:00');

      expect(parsed!.toUtc().hour, 4);
    });

    test('วันที่ล้วนไม่โดนเลื่อนเพราะ timezone', () {
      final parsed = parseDateOnly('2000-01-15');

      expect(parsed, DateTime(2000, 1, 15));
      expect(formatDateOnly(parsed!), '2000-01-15');
    });
  });

  // -----------------------------------------------------------------
  // เทียบเวอร์ชันแอปกับไฟล์ติดตั้งบนเซิร์ฟเวอร์ (/app/info)
  // -----------------------------------------------------------------
  group('เวอร์ชันแอป', () {
    AppRelease release(String version) =>
        AppRelease(available: true, version: version);

    test('เวอร์ชันใหม่กว่าถึงจะเตือนให้อัปเดต', () {
      expect(release('1.3.1').isNewerThan('1.3.0'), isTrue);
      expect(release('1.3.0').isNewerThan('1.3.0'), isFalse);
      expect(release('1.2.9').isNewerThan('1.3.0'), isFalse);
    });

    test('เทียบเป็นตัวเลข ไม่ใช่ข้อความ (1.10.0 ใหม่กว่า 1.9.0)', () {
      expect(release('1.10.0').isNewerThan('1.9.0'), isTrue);
    });

    test('เลข build ท้ายเวอร์ชันก็นับด้วย', () {
      expect(release('1.3.0+6').isNewerThan('1.3.0'), isTrue);
    });

    test('ยังไม่มีไฟล์ / เวอร์ชันอ่านไม่ออก = ไม่เตือน', () {
      expect(const AppRelease(available: false).isNewerThan('1.0.0'), isFalse);
      expect(release('').isNewerThan('1.0.0'), isFalse);
      expect(release('ไม่ทราบ').isNewerThan('1.0.0'), isFalse);
    });
  });

  // -----------------------------------------------------------------
  // ข้อความบอกตำแหน่งบนแผนที่ติดตาม (describeWhere ฝั่งเว็บ)
  // -----------------------------------------------------------------
  group('ตำแหน่งล่าสุดของพนักงาน', () {
    LiveLocation at({
      required bool within,
      String? office,
      double? distanceKm,
      int? secondsAgo,
      String status = 'online',
    }) =>
        LiveLocation.fromJson({
          'employee_id': 1,
          'employee_code': 'EMP001',
          'full_name': 'ธนกร ทดสอบ',
          'is_manager': false,
          'status': status,
          'latitude': 13.9,
          'longitude': 100.5,
          'within_geofence': within,
          'office_name': office,
          'distance_km': distanceKm,
          'seconds_ago': secondsAgo,
        });

    test('อยู่ในเขตบ้าน = "อยู่บ้าน" ไม่ใช่ "อยู่ในเขตที่ทำงาน"', () {
      final home = at(within: true, office: 'ถึงบ้านแล้ว');

      expect(home.whereText, 'อยู่บ้าน');
      expect(home.whereShortText, 'อยู่บ้าน');
    });

    test('อยู่ในเขตที่ทำงานบอกชื่อสถานที่', () {
      expect(at(within: true, office: 'MARDODI').whereText, 'อยู่ในเขต MARDODI');
    });

    test('อยู่นอกเขตบอกระยะห่าง', () {
      final away = at(within: false, office: 'MARDODI', distanceKm: 3.456);

      expect(away.whereText, 'นอกเขต ห่าง 3.46 กม. จาก MARDODI');
      expect(away.whereShortText, 'นอกเขต ห่าง 3.46 กม.');
    });

    test('อายุของพิกัดอ่านเป็นภาษาคน', () {
      expect(at(within: true, secondsAgo: 30).ageText, 'เมื่อสักครู่');
      expect(at(within: true, secondsAgo: 12 * 60).ageText, '12 นาทีที่แล้ว');
      expect(
        at(within: true, secondsAgo: 2 * 3600 + 5 * 60).ageText,
        '2 ชม. 5 นาทีที่แล้ว',
      );
      expect(at(within: true, secondsAgo: 50 * 3600).ageText, '2 วันที่แล้ว');
    });

    test('ไม่เคยส่งพิกัดมาเลย', () {
      final never = LiveLocation.fromJson({
        'employee_id': 2,
        'employee_code': 'EMP002',
        'full_name': 'ยังไม่เคยเปิดแอป',
        'is_manager': false,
        'status': 'no_data',
      });

      expect(never.hasPosition, isFalse);
      expect(never.status, LiveStatus.noData);
      expect(never.ageText, 'ไม่เคยส่งพิกัด');
    });

    test('นับจำนวนคนแยกตามสถานะสำหรับแถบสรุป', () {
      final snapshot = LiveLocationsSnapshot.fromJson({
        'server_time': '2026-08-26T09:00:00',
        'employees': [
          _json('online'),
          _json('online'),
          _json('offline'),
        ],
      });

      expect(snapshot.counts[LiveStatus.online], 2);
      expect(snapshot.counts[LiveStatus.offline], 1);
      expect(snapshot.counts[LiveStatus.noData], 0);
    });
  });
}

Map<String, dynamic> _json(String status) => {
      'employee_id': 1,
      'employee_code': 'EMP001',
      'full_name': 'ธนกร ทดสอบ',
      'is_manager': false,
      'status': status,
      'latitude': 13.9,
      'longitude': 100.5,
    };
