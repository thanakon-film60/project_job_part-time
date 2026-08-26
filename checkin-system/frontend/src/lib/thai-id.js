/**
 * คำนวณเลขตรวจสอบหลักที่ 13 ของเลขบัตรประชาชนไทย
 * น้ำหนักของ 12 หลักแรกคือ 13, 12, ... 2 ตามลำดับ
 */
export function calculateThaiIdCheckDigit(firstTwelveDigits) {
  if (!/^\d{12}$/.test(firstTwelveDigits)) return null;

  const sum = [...firstTwelveDigits].reduce(
    (total, digit, index) => total + Number(digit) * (13 - index),
    0,
  );

  return (11 - (sum % 11)) % 10;
}

/**
 * คืนผลแบบ object เพื่อให้ UI แสดงสาเหตุที่ผิดได้ทันที
 */
export function validateThaiNationalId(value) {
  const id = String(value ?? "").trim();

  if (!id) return { valid: false, message: "กรุณากรอกเลขบัตรประชาชน" };
  if (!/^\d+$/.test(id)) {
    return { valid: false, message: "เลขบัตรประชาชนต้องเป็นตัวเลขเท่านั้น" };
  }
  if (id.length !== 13) {
    return { valid: false, message: "เลขบัตรประชาชนต้องมี 13 หลัก" };
  }
  if (/^(\d)\1{12}$/.test(id)) {
    return { valid: false, message: "เลขบัตรประชาชนที่เป็นเลขซ้ำทั้งหมดใช้ไม่ได้" };
  }

  const expected = calculateThaiIdCheckDigit(id.slice(0, 12));
  if (expected !== Number(id[12])) {
    return { valid: false, message: "เลขบัตรประชาชนไม่ผ่านการตรวจสอบ Checksum" };
  }

  return { valid: true, message: "" };
}

