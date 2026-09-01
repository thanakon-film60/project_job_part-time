import '../models/directory.dart';
import '../models/employee.dart';
import '../models/json.dart';
import 'thai_id.dart';

/// สถานะการค้นที่อยู่จากรหัสไปรษณีย์
///
/// การตรวจฟอร์มต้องรู้สถานะนี้ด้วย ไม่งั้นจะปล่อยให้กด "ถัดไป" ผ่านไป
/// ทั้งที่ยังค้นที่อยู่ไม่เสร็จ แล้วไปเจอ 422 ตอนกดบันทึกจริง
enum AddressLookup { idle, loading, success, error }

/// ข้อมูลที่หัวหน้ากรอกในฟอร์มลงทะเบียนพนักงาน
///
/// เป็น mutable ตั้งใจ — หน้าฟอร์มถือ draft ตัวเดียวแล้วแก้ทีละช่อง
/// (พอร์ตมาจาก INITIAL_DATA ใน frontend/src/pages/EmployeeRegistrationPage.jsx)
class RegistrationDraft {
  String firstName = '';
  String lastName = '';
  DateTime? birthDate;
  String nationalId = '';

  String phone = '';
  String email = '';
  String addressLine = '';
  String postalCode = '';

  /// ที่อยู่ที่เลือกจากผลค้นรหัสไปรษณีย์ (ตำบล/อำเภอ/จังหวัด)
  ThaiAddress? address;

  String department = '';
  String position = '';
  DateTime? startDate;

  /// เปลี่ยนรหัสไปรษณีย์เมื่อไร ที่อยู่ที่เลือกไว้เดิมใช้ไม่ได้แล้ว
  void setPostalCode(String value) {
    postalCode = value;
    address = null;
  }

  /// payload ที่ POST /employee-management ต้องการ
  /// (buildEmployeePayload ใน frontend/src/lib/employee-registration.js)
  Map<String, dynamic> toPayload() {
    final selected = address;
    return {
      'personalInfo': {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'birthDate': birthDate == null ? '' : formatDateOnly(birthDate!),
        'nationalId': nationalId,
      },
      'contact': {
        'phone': phone,
        'email': email.trim().toLowerCase(),
        'address': {
          'addressLine': addressLine.trim(),
          'subdistrict': selected?.subdistrict ?? '',
          'district': selected?.district ?? '',
          'province': selected?.province ?? '',
          'postalCode': postalCode,
        },
      },
      'employment': {
        'department': department.trim(),
        'position': position.trim(),
        'startDate': startDate == null ? '' : formatDateOnly(startDate!),
      },
    };
  }
}

/// ชื่อช่องที่อยู่ในแต่ละขั้นของฟอร์ม — ใช้ตัดสินว่าขั้นนี้ผ่านหรือยัง
/// (STEP_FIELDS ฝั่งเว็บ)
const List<List<String>> registrationStepFields = [
  ['firstName', 'lastName', 'birthDate', 'nationalId'],
  ['phone', 'email', 'addressLine', 'postalCode', 'addressChoice'],
  ['department', 'position', 'startDate'],
];

/// ตรวจฟอร์มทั้งใบ คืน map ของ "ชื่อช่อง -> ข้อความผิดพลาด"
/// ช่องที่ผ่านจะไม่มีคีย์อยู่ใน map (พอร์ตจาก validateRegistration ฝั่งเว็บ)
Map<String, String> validateRegistration(
  RegistrationDraft data, {
  List<ThaiAddress> addressOptions = const [],
  AddressLookup lookup = AddressLookup.idle,
}) {
  final errors = <String, String>{};
  final today = DateTime.now();

  if (data.firstName.trim().isEmpty) errors['firstName'] = 'กรุณากรอกชื่อ';
  if (data.lastName.trim().isEmpty) errors['lastName'] = 'กรุณากรอกนามสกุล';

  final birthDate = data.birthDate;
  if (birthDate == null) {
    errors['birthDate'] = 'กรุณาเลือกวันเกิด';
  } else if (birthDate.isAfter(DateTime(today.year, today.month, today.day))) {
    errors['birthDate'] = 'วันเกิดต้องไม่เป็นวันที่ในอนาคต';
  }

  final idCheck = validateThaiNationalId(data.nationalId);
  if (!idCheck.valid) errors['nationalId'] = idCheck.message;

  if (!RegExp(r'^0\d{8,9}$').hasMatch(data.phone)) {
    errors['phone'] = 'กรุณากรอกเบอร์โทรไทย 9-10 หลักและขึ้นต้นด้วย 0';
  }
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(data.email)) {
    errors['email'] = 'รูปแบบอีเมลไม่ถูกต้อง';
  }
  if (data.addressLine.trim().isEmpty) {
    errors['addressLine'] = 'กรุณากรอกที่อยู่';
  }

  if (!RegExp(r'^\d{5}$').hasMatch(data.postalCode)) {
    errors['postalCode'] = 'รหัสไปรษณีย์ต้องมี 5 หลัก';
  } else if (lookup == AddressLookup.error) {
    errors['postalCode'] = 'เชื่อมต่อระบบค้นหาที่อยู่ไม่สำเร็จ กรุณาลองใหม่';
  } else if (lookup == AddressLookup.loading || lookup == AddressLookup.idle) {
    errors['postalCode'] = 'กำลังตรวจสอบรหัสไปรษณีย์';
  } else if (addressOptions.isEmpty) {
    errors['postalCode'] = 'ไม่พบรหัสไปรษณีย์นี้ในฐานข้อมูลที่อยู่ไทย';
  }
  if (data.address == null) {
    errors['addressChoice'] = 'กรุณาเลือกที่อยู่จากรายการ';
  }

  if (data.department.trim().isEmpty) errors['department'] = 'กรุณาเลือกแผนก';
  if (data.position.trim().isEmpty) errors['position'] = 'กรุณาเลือกตำแหน่ง';
  if (data.startDate == null) errors['startDate'] = 'กรุณาเลือกวันเริ่มงาน';

  return errors;
}

/// ขั้นนี้กรอกครบแล้วหรือยัง (ใช้เปิด/ปิดปุ่ม "ถัดไป")
bool registrationStepValid(int step, Map<String, String> errors) {
  if (step < 0 || step >= registrationStepFields.length) return true;
  return !registrationStepFields[step].any(errors.containsKey);
}

/// ข้อมูลที่หัวหน้าแก้ไขในแฟ้มพนักงานที่มีอยู่แล้ว
///
/// PATCH /employee-management/{id} รับเฉพาะช่องที่ "เปลี่ยนจริง" (exclude_unset)
/// จึงต้องเทียบกับค่าเดิมก่อนส่ง ไม่งั้น backend จะบันทึก Timeline ว่าแก้ไข
/// ทั้งที่ไม่ได้แก้อะไรเลย
class ProfileEditDraft {
  final EmployeeProfile original;

  String fullName;
  DateTime? birthDate;

  /// เว้นว่าง = ใช้เลขบัตรเดิม (แอปไม่เคยเห็นเลขเต็มของเดิมอยู่แล้ว)
  String nationalId = '';
  String phone;
  String email;
  String addressLine;
  String postalCode;
  ThaiAddress? address;
  String subdistrict;
  String district;
  String province;
  String department;
  String position;
  DateTime? startDate;

  ProfileEditDraft.from(EmployeeProfile employee)
      : original = employee,
        fullName = employee.fullName,
        birthDate = employee.birthDate,
        phone = employee.phone ?? '',
        email = employee.email,
        addressLine = employee.addressLine ?? '',
        postalCode = employee.postalCode ?? '',
        subdistrict = employee.subdistrict ?? '',
        district = employee.district ?? '',
        province = employee.province ?? '',
        department = employee.department ?? '',
        position = employee.position ?? '',
        startDate = employee.startDate;

  void selectAddress(ThaiAddress value) {
    address = value;
    subdistrict = value.subdistrict;
    district = value.district;
    province = value.province;
  }

  void setPostalCode(String value) {
    postalCode = value;
    address = null;
    subdistrict = '';
    district = '';
    province = '';
  }

  /// ยังไม่เคยมีเลขบัตรในระบบ = ต้องกรอกครั้งนี้
  bool get nationalIdRequired => original.nationalIdMasked == null;

  /// ตรวจก่อนส่ง — คืน null ถ้าผ่าน ไม่งั้นคืนข้อความบอกสาเหตุ
  String? validate() {
    final required = <String>[
      fullName,
      phone,
      email,
      addressLine,
      postalCode,
      subdistrict,
      district,
      province,
      department,
      position,
    ];
    if (required.any((value) => value.trim().isEmpty) ||
        birthDate == null ||
        startDate == null) {
      return 'กรุณากรอกข้อมูลพนักงานให้ครบทุกช่อง';
    }
    if (nationalIdRequired && nationalId.trim().isEmpty) {
      return 'กรุณากรอกเลขบัตรประชาชน';
    }
    if (!RegExp(r'^0\d{8,9}$').hasMatch(phone)) {
      return 'เบอร์โทรต้องขึ้นต้นด้วย 0 และมี 9-10 หลัก';
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }
    if (nationalId.trim().isNotEmpty) {
      final check = validateThaiNationalId(nationalId);
      if (!check.valid) return check.message;
    }
    return null;
  }

  /// เฉพาะช่องที่ค่าต่างจากเดิม — ว่างเปล่า = ไม่มีอะไรต้องบันทึก
  Map<String, dynamic> changedFields() {
    final changes = <String, dynamic>{};

    void put(String key, Object? value, Object? previous) {
      if (value != previous) changes[key] = value;
    }

    put('fullName', fullName.trim(), original.fullName);
    put('phone', phone.trim(), original.phone);
    put('email', email.trim().toLowerCase(), original.email.toLowerCase());
    put('addressLine', addressLine.trim(), original.addressLine);
    put('postalCode', postalCode.trim(), original.postalCode);
    put('subdistrict', subdistrict, original.subdistrict);
    put('district', district, original.district);
    put('province', province, original.province);
    put('department', department, original.department);
    put('position', position, original.position);

    if (birthDate != null && birthDate != original.birthDate) {
      changes['birthDate'] = formatDateOnly(birthDate!);
    }
    if (startDate != null && startDate != original.startDate) {
      changes['startDate'] = formatDateOnly(startDate!);
    }
    if (nationalId.trim().isNotEmpty) {
      changes['nationalId'] = nationalId.trim();
    }

    return changes;
  }
}
