import 'json.dart';

/// ตัวเลือกแผนก/ตำแหน่งที่หัวหน้ากำหนดไว้ในระบบ (/employment-options)
///
/// backend บังคับว่าแผนกและตำแหน่งของพนักงานต้องมาจากรายการนี้เท่านั้น
/// พิมพ์เองไม่ได้ ถ้าจะใช้ชื่อใหม่ต้องเพิ่มเข้าไปในรายการก่อน
class EmploymentOption {
  final int id;

  /// "department" หรือ "position"
  final String kind;
  final String name;

  const EmploymentOption({
    required this.id,
    required this.kind,
    required this.name,
  });

  bool get isDepartment => kind == 'department';
  bool get isPosition => kind == 'position';

  factory EmploymentOption.fromJson(Map<String, dynamic> json) {
    return EmploymentOption(
      id: asInt(json['id']),
      kind: asText(json['kind']) ?? '',
      name: asText(json['name']) ?? '',
    );
  }
}

/// ที่อยู่ไทย 1 รายการที่ได้จากการค้นด้วยรหัสไปรษณีย์
/// (/addresses/postal-code/{code})
class ThaiAddress {
  final int id;
  final String postalCode;
  final String subdistrict;
  final String district;
  final String province;

  const ThaiAddress({
    required this.id,
    required this.postalCode,
    required this.subdistrict,
    required this.district,
    required this.province,
  });

  /// ข้อความที่โชว์ในตัวเลือก — รูปแบบเดียวกับฝั่งเว็บ
  String get label => 'ต.$subdistrict / อ.$district / จ.$province';

  /// ตรงกับที่อยู่ที่เลือกไว้ในฟอร์มหรือไม่
  bool matches(String? sub, String? dis, String? prov) =>
      subdistrict == sub && district == dis && province == prov;

  factory ThaiAddress.fromJson(Map<String, dynamic> json) {
    return ThaiAddress(
      id: asInt(json['id']),
      postalCode: asText(json['postal_code']) ?? '',
      subdistrict: asText(json['subdistrict']) ?? '',
      district: asText(json['district']) ?? '',
      province: asText(json['province']) ?? '',
    );
  }
}

/// ข้อมูลไฟล์ติดตั้งแอปที่วางไว้บนเซิร์ฟเวอร์ (/app/info)
///
/// แอปเอามาเทียบกับเวอร์ชันของตัวเอง เพื่อบอกพนักงานว่ามีตัวใหม่ให้อัปเดต
class AppRelease {
  final bool available;
  final String version;
  final String minAndroid;
  final int sizeBytes;
  final DateTime? builtAt;

  const AppRelease({
    required this.available,
    this.version = '',
    this.minAndroid = '',
    this.sizeBytes = 0,
    this.builtAt,
  });

  String get sizeText {
    if (sizeBytes <= 0) return '-';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// เวอร์ชันบนเซิร์ฟเวอร์ใหม่กว่าที่ติดตั้งอยู่หรือไม่
  ///
  /// เทียบเป็นตัวเลขทีละส่วน (1.10.0 ต้องใหม่กว่า 1.9.0 ซึ่งการเทียบข้อความทำไม่ได้)
  /// รูปแบบที่อ่านไม่ออกให้ถือว่า "ไม่ใหม่กว่า" ดีกว่าไปเตือนผิด ๆ
  bool isNewerThan(String installed) {
    if (!available || version.trim().isEmpty) return false;
    final remote = _parts(version);
    final local = _parts(installed);
    if (remote.isEmpty) return false;
    for (var i = 0; i < remote.length || i < local.length; i++) {
      final r = i < remote.length ? remote[i] : 0;
      final l = i < local.length ? local[i] : 0;
      if (r != l) return r > l;
    }
    return false;
  }

  static List<int> _parts(String value) => value
      .split(RegExp(r'[.+\-]'))
      .map((part) => int.tryParse(part.trim()))
      .whereType<int>()
      .toList(growable: false);

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    return AppRelease(
      available: asBool(json['available']),
      version: asText(json['version']) ?? '',
      minAndroid: asText(json['min_android']) ?? '',
      sizeBytes: asInt(json['size_bytes']),
      builtAt: parseServerDateTime(json['built_at']),
    );
  }
}

/// รูปใบหน้าอ้างอิง 1 รูปในประวัติของพนักงาน (/faces/*)
///
/// ตัวไฟล์รูปไม่ได้มากับ JSON — ต้องดึงแยกที่ /faces/{id}/photo พร้อมแนบ token
class FaceRecord {
  final int id;
  final int employeeId;

  /// "web" (ถ่ายจากเว็บ) หรือ "mobile" (ถ่ายจากแอป)
  final String source;
  final String? note;
  final DateTime? createdAt;

  /// ลำดับที่พนักงานลากจัดเอง — null = ยังไม่เคยจัด (เรียงตามเวลาบันทึก)
  final int? sortOrder;

  const FaceRecord({
    required this.id,
    required this.employeeId,
    required this.source,
    this.note,
    this.createdAt,
    this.sortOrder,
  });

  String get sourceLabel => source == 'mobile' ? 'แอปมือถือ' : 'เว็บไซต์';

  factory FaceRecord.fromJson(Map<String, dynamic> json) {
    return FaceRecord(
      id: asInt(json['id']),
      employeeId: asInt(json['employee_id']),
      source: asText(json['source']) ?? 'web',
      note: asText(json['note']),
      createdAt: parseServerDateTime(json['created_at']),
      sortOrder: json['sort_order'] == null ? null : asInt(json['sort_order']),
    );
  }
}
