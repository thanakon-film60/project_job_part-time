import '../services/attendance_service.dart';
import 'directory.dart';
import 'json.dart';

/// บัญชีที่ล็อกอินอยู่ตอนนี้ — มาจาก response ของ POST /auth/login
///
/// ของเดิมแอปเก็บแค่ access_token แล้วทิ้งก้อน employee ทั้งก้อน ทำให้แอป
/// ไม่รู้ว่าคนที่ล็อกอินเป็นหัวหน้าหรือพนักงาน เมนูฝั่งหัวหน้าจึงทำไม่ได้เลย
class EmployeeAccount {
  final int id;
  final String employeeCode;
  final String fullName;
  final String email;
  final bool isManager;

  const EmployeeAccount({
    required this.id,
    required this.employeeCode,
    required this.fullName,
    required this.email,
    required this.isManager,
  });

  /// ตัวอักษรแรกของชื่อ ใช้ทำ avatar เวลาที่ยังไม่มีรูปใบหน้า
  String get initial {
    final name = fullName.trim();
    return name.isEmpty ? '?' : name.substring(0, 1);
  }

  factory EmployeeAccount.fromJson(Map<String, dynamic> json) {
    return EmployeeAccount(
      id: asInt(json['id']),
      employeeCode: asText(json['employee_code']) ?? '-',
      fullName: asText(json['full_name']) ?? '-',
      email: asText(json['email']) ?? '',
      isManager: asBool(json['is_manager']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_code': employeeCode,
        'full_name': fullName,
        'email': email,
        'is_manager': isManager,
      };
}

/// แฟ้มพนักงานเต็ม — จาก /reports/employees และ /employee-management
/// (ตรงกับ EmployeeProfileOut ใน backend/app/schemas.py)
class EmployeeProfile {
  final int id;
  final String employeeCode;
  final String fullName;
  final String email;
  final bool isManager;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? birthDate;

  /// เลขบัตรที่ backend ปิดบังมาแล้ว (*********1234) — แอปไม่เคยเห็นเลขเต็ม
  final String? nationalIdMasked;
  final String? phone;
  final String? addressLine;
  final String? postalCode;
  final String? subdistrict;
  final String? district;
  final String? province;
  final String? department;
  final String? position;
  final DateTime? startDate;

  /// backend คำนวณให้: กรอกข้อมูลแฟ้มพนักงานครบทุกช่องหรือยัง
  final bool profileComplete;

  const EmployeeProfile({
    required this.id,
    required this.employeeCode,
    required this.fullName,
    required this.email,
    required this.isManager,
    required this.profileComplete,
    this.createdAt,
    this.updatedAt,
    this.birthDate,
    this.nationalIdMasked,
    this.phone,
    this.addressLine,
    this.postalCode,
    this.subdistrict,
    this.district,
    this.province,
    this.department,
    this.position,
    this.startDate,
  });

  /// ที่อยู่เต็มบรรทัดเดียว — เว้นช่องที่ยังไม่ได้กรอกออกไป
  String get addressText {
    final parts = [addressLine, subdistrict, district, province, postalCode]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty);
    return parts.isEmpty ? '' : parts.join(' ');
  }

  /// "แผนก · ตำแหน่ง" สำหรับบรรทัดย่อยในรายชื่อ
  String get roleText => [department, position]
      .whereType<String>()
      .where((part) => part.trim().isNotEmpty)
      .join(' · ');

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    return EmployeeProfile(
      id: asInt(json['id']),
      employeeCode: asText(json['employee_code']) ?? '-',
      fullName: asText(json['full_name']) ?? '-',
      email: asText(json['email']) ?? '',
      isManager: asBool(json['is_manager']),
      profileComplete: asBool(json['profile_complete']),
      createdAt: parseServerDateTime(json['created_at']),
      updatedAt: parseServerDateTime(json['updated_at']),
      birthDate: parseDateOnly(json['birth_date']),
      nationalIdMasked: asText(json['national_id_masked']),
      phone: asText(json['phone']),
      addressLine: asText(json['address_line']),
      postalCode: asText(json['postal_code']),
      subdistrict: asText(json['subdistrict']),
      district: asText(json['district']),
      province: asText(json['province']),
      department: asText(json['department']),
      position: asText(json['position']),
      startDate: parseDateOnly(json['start_date']),
    );
  }
}

/// เหตุการณ์ใน Timeline แฟ้มพนักงาน (ลงทะเบียน / แก้ไขข้อมูล / บัญชีเดิม)
class EmployeeEvent {
  final int id;
  final String eventType;
  final String title;
  final Map<String, dynamic>? detail;
  final DateTime? createdAt;

  const EmployeeEvent({
    required this.id,
    required this.eventType,
    required this.title,
    this.detail,
    this.createdAt,
  });

  /// บรรทัดอธิบายใต้หัวข้อ — ประกอบจาก detail ที่ backend ใส่มาแต่ละชนิด
  String? get detailText {
    final data = detail;
    if (data == null || data.isEmpty) return null;

    final changed = data['changed_fields'];
    if (changed is List && changed.isNotEmpty) {
      return 'แก้ไข: ${changed.join(', ')}';
    }

    final department = asText(data['department']);
    final position = asText(data['position']);
    if (department != null || position != null) {
      return [department, position].whereType<String>().join(' · ');
    }

    return asText(data['note']);
  }

  factory EmployeeEvent.fromJson(Map<String, dynamic> json) {
    final detail = json['detail'];
    return EmployeeEvent(
      id: asInt(json['id']),
      eventType: asText(json['event_type']) ?? '',
      title: asText(json['title']) ?? '-',
      detail: detail is Map<String, dynamic> ? detail : null,
      createdAt: parseServerDateTime(json['created_at']),
    );
  }
}

/// ผลลัพธ์ตอนหัวหน้าลงทะเบียนพนักงานใหม่
///
/// backend สุ่มรหัสผ่านชั่วคราวให้ และคืนมา "ครั้งเดียว" ตอนสมัครเท่านั้น
/// ถ้าปิดหน้าไปโดยไม่ได้จด จะดูย้อนหลังไม่ได้อีก
class EmployeeRegistrationResult {
  final EmployeeProfile employee;
  final String temporaryPassword;

  const EmployeeRegistrationResult({
    required this.employee,
    required this.temporaryPassword,
  });

  factory EmployeeRegistrationResult.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    return EmployeeRegistrationResult(
      employee: EmployeeProfile.fromJson(
        employee is Map<String, dynamic> ? employee : const {},
      ),
      temporaryPassword: asText(json['temporary_password']) ?? '',
    );
  }
}

/// แฟ้มพนักงาน 1 คนในเดือนที่เลือก (/reports/employees/{id}/history)
///
/// รวมทุกอย่างที่หัวหน้าต้องดูไว้ใน request เดียว: ข้อมูลส่วนตัว
/// ประวัติลงเวลาของเดือนนั้น รูปยืนยันตัวตน และ Timeline การเปลี่ยนแปลง
class EmployeeHistory {
  final EmployeeProfile employee;
  final int year;
  final int month;
  final List<CheckInRecord> checkins;
  final List<FaceRecord> faceProfiles;
  final List<EmployeeEvent> events;

  const EmployeeHistory({
    required this.employee,
    required this.year,
    required this.month,
    required this.checkins,
    required this.faceProfiles,
    required this.events,
  });

  /// จำนวนวัน (ไม่ซ้ำ) ที่ "ไปทำงานจริง" — รายการที่บ้านไม่นับ
  int get workDays => checkins
      .where((record) => !record.atHome)
      .map((record) {
        final thai = record.thaiTime;
        return '${thai.year}-${thai.month}-${thai.day}';
      })
      .toSet()
      .length;

  /// จำนวนครั้งที่กดเข้างานจริง (ไม่รวมการบันทึกที่บ้าน)
  int get workCheckIns => checkins
      .where((record) => record.isCheckIn && !record.atHome)
      .length;

  /// จัดกลุ่มตามวันไทย เรียงวันใหม่สุดขึ้นก่อน
  List<MapEntry<DateTime, List<CheckInRecord>>> get byDay {
    final grouped = <DateTime, List<CheckInRecord>>{};
    for (final record in checkins) {
      final thai = record.thaiTime;
      final day = DateTime(thai.year, thai.month, thai.day);
      grouped.putIfAbsent(day, () => []).add(record);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        MapEntry(
          day,
          grouped[day]!..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        ),
    ];
  }

  factory EmployeeHistory.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'];
    final checkins = json['checkins'];
    return EmployeeHistory(
      employee: EmployeeProfile.fromJson(
        employee is Map<String, dynamic> ? employee : const {},
      ),
      year: asInt(json['year']),
      month: asInt(json['month']),
      checkins: checkins is List
          ? checkins
              .whereType<Map<String, dynamic>>()
              .map(CheckInRecord.fromJson)
              .whereType<CheckInRecord>()
              .toList(growable: false)
          : const [],
      faceProfiles: mapList(json['face_profiles'], FaceRecord.fromJson),
      events: mapList(json['events'], EmployeeEvent.fromJson),
    );
  }
}
