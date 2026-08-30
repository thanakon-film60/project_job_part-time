/// ตรวจสอบเลขบัตรประชาชนไทย
///
/// ตรรกะเดียวกันสามที่: backend (schemas.py -> _valid_thai_id),
/// เว็บ (frontend/src/lib/thai-id.js) และไฟล์นี้ — ตรวจตั้งแต่ในแอป
/// เพื่อบอกผู้ใช้ทันทีที่พิมพ์ ไม่ต้องรอ 422 กลับมาจากเซิร์ฟเวอร์
library;

/// เลขตรวจสอบหลักที่ 13 ที่ควรจะเป็น จากเลข 12 หลักแรก
///
/// น้ำหนักของ 12 หลักแรกคือ 13, 12, ... 2 ตามลำดับ
/// คืน null ถ้ารูปแบบไม่ใช่ตัวเลข 12 หลัก
int? thaiIdCheckDigit(String firstTwelveDigits) {
  if (!RegExp(r'^\d{12}$').hasMatch(firstTwelveDigits)) return null;

  var sum = 0;
  for (var index = 0; index < 12; index++) {
    sum += int.parse(firstTwelveDigits[index]) * (13 - index);
  }
  return (11 - (sum % 11)) % 10;
}

/// ผลการตรวจ พร้อมเหตุผลเป็นภาษาไทยให้เอาไปแสดงใต้ช่องกรอกได้เลย
class ThaiIdCheck {
  final bool valid;
  final String message;

  const ThaiIdCheck({required this.valid, required this.message});

  static const ThaiIdCheck ok = ThaiIdCheck(valid: true, message: '');
}

ThaiIdCheck validateThaiNationalId(String? value) {
  final id = (value ?? '').trim();

  if (id.isEmpty) {
    return const ThaiIdCheck(valid: false, message: 'กรุณากรอกเลขบัตรประชาชน');
  }
  if (!RegExp(r'^\d+$').hasMatch(id)) {
    return const ThaiIdCheck(
      valid: false,
      message: 'เลขบัตรประชาชนต้องเป็นตัวเลขเท่านั้น',
    );
  }
  if (id.length != 13) {
    return const ThaiIdCheck(
      valid: false,
      message: 'เลขบัตรประชาชนต้องมี 13 หลัก',
    );
  }
  // เลขซ้ำทั้ง 13 หลัก (1111111111111) ผ่าน checksum ได้ แต่ไม่ใช่เลขจริง
  if (RegExp(r'^(\d)\1{12}$').hasMatch(id)) {
    return const ThaiIdCheck(
      valid: false,
      message: 'เลขบัตรประชาชนที่เป็นเลขซ้ำทั้งหมดใช้ไม่ได้',
    );
  }

  if (thaiIdCheckDigit(id.substring(0, 12)) != int.parse(id[12])) {
    return const ThaiIdCheck(
      valid: false,
      message: 'เลขบัตรประชาชนไม่ผ่านการตรวจสอบ Checksum',
    );
  }

  return ThaiIdCheck.ok;
}
