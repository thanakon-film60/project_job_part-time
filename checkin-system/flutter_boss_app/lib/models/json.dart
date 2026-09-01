/// ตัวช่วยอ่านค่า JSON จาก backend — รวมไว้ที่เดียวเพื่อให้ทุก model
/// ตีความข้อมูลชุดเดียวกันเหมือนกันหมด (โดยเฉพาะเรื่องเขตเวลา)
library;

/// backend เก็บเวลาเป็น UTC แต่ response บางเส้น (/checkins/me, /locations/*)
/// ส่ง ISO ที่ "ไม่มี" timezone ติดมา ถ้าปล่อยให้ DateTime.parse เดาเอง
/// มันจะตีความเป็นเวลาเครื่อง แล้วเพี้ยนไป 7 ชั่วโมง
/// ส่วนเส้นปฏิทินส่ง +07:00 มาให้แล้ว จึงต้องแยกสองกรณี
/// (ตรรกะเดียวกับ frontend/src/lib/attendance.js -> thaiFrom)
final RegExp _hasTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

DateTime? parseServerDateTime(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(_hasTimezone.hasMatch(text) ? text : '${text}Z');
}

/// วันที่ล้วน (YYYY-MM-DD) — ไม่มีเรื่องเขตเวลามาเกี่ยว
DateTime? parseDateOnly(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// วันที่ล้วนกลับไปเป็นรูปแบบที่ backend รับ (YYYY-MM-DD)
String formatDateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String? asText(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

double? asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

int asInt(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? fallback;

bool asBool(Object? value) => value == true;

/// รายการ JSON -> รายการ model (ข้ามรายการที่รูปแบบไม่ถูกต้อง)
List<T> mapList<T>(Object? value, T Function(Map<String, dynamic>) build) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(build)
      .toList(growable: false);
}
