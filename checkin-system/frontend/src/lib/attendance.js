import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";

dayjs.extend(utc);

// เวลาไทย = UTC+7 (นาที) — บังคับที่ฝั่งเว็บอีกชั้น เพื่อให้ทุกเครื่องเห็นเวลาเดียวกัน
// ต่อให้ตั้ง timezone ของเครื่อง/มือถือไว้เป็นโซนอื่น
export const THAI_OFFSET_MINUTES = 7 * 60;

const HAS_TIMEZONE = /(Z|[+-]\d{2}:?\d{2})$/;

/**
 * เวลาที่ API ส่งมา -> dayjs เวลาไทย
 *
 * บาง endpoint (/checkins/me, /locations/*) ส่ง ISO ที่ "ไม่มี" timezone ติดมา
 * ซึ่งค่าจริงในฐานข้อมูลเป็น UTC — ถ้าปล่อยให้ dayjs เดาเอง มันจะตีความว่าเป็น
 * เวลาเครื่องผู้ใช้ แล้วโชว์ช้าไป 7 ชั่วโมง (ลงเวลา 12:34 กลายเป็น 05:34)
 * ส่วน endpoint ปฏิทินส่ง +07:00 มาให้แล้ว จึงต้องแยกสองกรณี
 */
export function thaiFrom(iso) {
  if (!iso) return null;
  const text = String(iso);
  const base = HAS_TIMEZONE.test(text) ? dayjs(text) : dayjs.utc(text);
  return base.utcOffset(THAI_OFFSET_MINUTES);
}

/** เวลาแบบ 12:34 (เวลาไทย) */
export function thaiTime(iso) {
  return thaiFrom(iso)?.format("HH:mm") ?? "–";
}

/** วันและเวลาแบบ 25 ส.ค. 2026 12:34 น. (เวลาไทย) */
export function thaiDateTime(iso) {
  return thaiFrom(iso)?.format("D MMM YYYY HH:mm น.") ?? "–";
}

/**
 * สถานที่นี้คือ "บ้าน" หรือไม่ — ตรรกะเดียวกับ backend (geofence.py)
 * และแอป Flutter (Office.isHomeLabel)
 */
export function isHomeLocation(value) {
  const text = String(value ?? "").trim().toLowerCase();
  if (!text) return false;
  return text.includes("บ้าน") || text.includes("home") || text.includes("house");
}

/**
 * ป้ายกำกับของการลงเวลา 1 รายการ
 *
 * อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่ใช่ "เข้างาน" และไม่มีออกงานตามมา
 * (พนักงานยังต้องเข้าสู่ระบบทุกวันเพื่อให้ระบบรู้ว่าอยู่ที่ไหน)
 */
export function describeCheckin(record) {
  if (isHomeLocation(record?.office_name)) {
    return { kind: "home", label: "อยู่บ้านแล้ว", badge: "purple" };
  }
  if (record?.kind === "in") {
    return { kind: "in", label: "เข้างาน", badge: "success" };
  }
  return { kind: "out", label: "ออกงาน", badge: "warning" };
}

/**
 * ข้อความบอกตำแหน่งล่าสุดของพนักงาน 1 คน (แผนที่ติดตามของหัวหน้า)
 *
 * อยู่ในเขตบ้าน = อยู่บ้าน ไม่ใช่ "อยู่ในเขตที่ทำงาน"
 */
export function describeWhere({ within_geofence, office_name, distance_km }) {
  const place = office_name || "ที่ทำงาน";
  if (within_geofence) {
    return isHomeLocation(office_name) ? "อยู่บ้าน" : `อยู่ในเขต ${place}`;
  }
  const distance = distance_km == null ? "-" : `${distance_km.toFixed(2)} กม.`;
  return `นอกเขต ห่าง ${distance} จาก ${place}`;
}

/** แบบสั้นสำหรับรายชื่อด้านข้าง */
export function describeWhereShort({ within_geofence, office_name, distance_km }) {
  const place = office_name || "ที่ทำงาน";
  if (within_geofence) {
    return isHomeLocation(office_name) ? "อยู่บ้าน" : `ในเขต ${place}`;
  }
  const distance = distance_km == null ? "-" : `${distance_km.toFixed(2)} กม.`;
  return `นอกเขต ห่าง ${distance}`;
}
