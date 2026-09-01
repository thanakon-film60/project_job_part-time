import { validateThaiNationalId } from "./thai-id";

export const STEP_FIELDS = [
  ["firstName", "lastName", "birthDate", "nationalId"],
  ["phone", "email", "addressLine", "postalCode", "addressChoice"],
  ["department", "position", "startDate"],
];

export function validateRegistration(data, addressOptions = [], addressLookupStatus = "idle") {
  const errors = {};
  const today = new Date().toISOString().slice(0, 10);

  if (!data.firstName.trim()) errors.firstName = "กรุณากรอกชื่อ";
  if (!data.lastName.trim()) errors.lastName = "กรุณากรอกนามสกุล";
  if (!data.birthDate) errors.birthDate = "กรุณาเลือกวันเกิด";
  else if (data.birthDate > today) errors.birthDate = "วันเกิดต้องไม่เป็นวันที่ในอนาคต";

  const idResult = validateThaiNationalId(data.nationalId);
  if (!idResult.valid) errors.nationalId = idResult.message;

  if (!/^0\d{8,9}$/.test(data.phone)) {
    errors.phone = "กรุณากรอกเบอร์โทรไทย 9–10 หลักและขึ้นต้นด้วย 0";
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email)) {
    errors.email = "รูปแบบอีเมลไม่ถูกต้อง";
  }
  if (!data.addressLine.trim()) errors.addressLine = "กรุณากรอกที่อยู่";
  if (!/^\d{5}$/.test(data.postalCode)) {
    errors.postalCode = "รหัสไปรษณีย์ต้องมี 5 หลัก";
  } else if (addressLookupStatus === "error") {
    errors.postalCode = "เชื่อมต่อระบบค้นหาที่อยู่ไม่สำเร็จ กรุณาลองใหม่";
  } else if (addressLookupStatus === "loading" || addressLookupStatus === "idle") {
    errors.postalCode = "กำลังตรวจสอบรหัสไปรษณีย์";
  } else if (addressOptions.length === 0) {
    errors.postalCode = "ไม่พบรหัสไปรษณีย์นี้ในฐานข้อมูลที่อยู่ไทย";
  }
  if (!data.subdistrict || !data.district || !data.province) {
    errors.addressChoice = "กรุณาเลือกที่อยู่จากรายการ";
  }

  if (!data.department.trim()) errors.department = "กรุณากรอกแผนก";
  if (!data.position.trim()) errors.position = "กรุณากรอกตำแหน่ง";
  if (!data.startDate) errors.startDate = "กรุณาเลือกวันเริ่มงาน";

  return errors;
}

export function buildEmployeePayload(data) {
  return {
    personalInfo: {
      firstName: data.firstName.trim(),
      lastName: data.lastName.trim(),
      birthDate: data.birthDate,
      nationalId: data.nationalId,
    },
    contact: {
      phone: data.phone,
      email: data.email.trim().toLowerCase(),
      address: {
        addressLine: data.addressLine.trim(),
        subdistrict: data.subdistrict,
        district: data.district,
        province: data.province,
        postalCode: data.postalCode,
      },
    },
    employment: {
      department: data.department.trim(),
      position: data.position.trim(),
      startDate: data.startDate,
    },
  };
}
