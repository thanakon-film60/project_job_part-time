// production: ปล่อยว่าง = เรียกโดเมนเดียวกัน (IIS จะส่งต่อไป backend ให้เอง)
// ตอน dev: ตั้ง VITE_API_BASE=http://localhost:8002
const BASE = import.meta.env.VITE_API_BASE ?? "";

const SKIP = { "ngrok-skip-browser-warning": "true" }; // ข้ามหน้าเตือน ngrok (เผื่อกลับไปใช้)

let token = localStorage.getItem("token") || null;
let employee = JSON.parse(localStorage.getItem("employee") || "null");

export function getToken() {
  return token;
}
export function getEmployee() {
  return employee;
}
export function setSession(t, emp) {
  token = t;
  employee = emp;
  localStorage.setItem("token", t);
  localStorage.setItem("employee", JSON.stringify(emp));
}
export function clearSession() {
  token = null;
  employee = null;
  localStorage.removeItem("token");
  localStorage.removeItem("employee");
}

function sessionExpired() {
  clearSession();
  if (window.location.pathname !== "/login") {
    window.location.replace("/login?expired=1");
  }
  throw new Error("เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่");
}

function authHeaders(extra = {}) {
  const h = { ...SKIP, ...extra };
  if (token) h["Authorization"] = `Bearer ${token}`;
  return h;
}

async function req(path, opts = {}) {
  const res = await fetch(`${BASE}${path}`, {
    ...opts,
    headers: authHeaders(opts.headers),
  });
  if (res.status === 401) {
    sessionExpired();
  }
  if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
  return res.json();
}

export async function login(username, password) {
  const form = new URLSearchParams();
  form.set("username", username);
  form.set("password", password);
  const res = await fetch(`${BASE}/auth/login`, {
    method: "POST",
    headers: { ...SKIP, "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  if (!res.ok) throw new Error("เข้าสู่ระบบไม่สำเร็จ");
  const data = await res.json();
  setSession(data.access_token, data.employee);
  return data;
}

// ===== reports =====
export const getEmployees = () => req("/reports/employees");
export const getEmployeeHistory = (employeeId, year, month) =>
  req(`/reports/employees/${employeeId}/history?year=${year}&month=${month}`);
export async function getThaiAddresses(postalCode) {
  const rows = await req(`/addresses/postal-code/${encodeURIComponent(postalCode)}`);
  return rows.map((row) => ({
    id: row.id,
    postalCode: row.postal_code,
    subdistrict: row.subdistrict,
    district: row.district,
    province: row.province,
  }));
}

export const getEmploymentOptions = () => req("/employment-options");
export const addEmploymentOption = (kind, name) =>
  req("/employment-options", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ kind, name }),
  });
export const registerEmployee = (payload) =>
  req("/employee-management", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
export const updateEmployeeProfile = (employeeId, payload) =>
  req(`/employee-management/${employeeId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
export const getGeofence = () => req("/reports/geofence");
export const getCalendar = (employeeId, year, month) =>
  req(`/reports/calendar?employee_id=${employeeId}&year=${year}&month=${month}`);
export const getTeamCalendar = (year, month) =>
  req(`/reports/team-calendar?year=${year}&month=${month}`);

// ===== checkins =====
export const getMyCheckins = () => req("/checkins/me");

// ===== locations (แผนที่ติดตามพนักงาน — เฉพาะหัวหน้า) =====
export const getLiveLocations = () => req("/locations/live");
export const getLocationTrail = (employeeId, hours = 6) =>
  req(`/locations/trail/${employeeId}?hours=${hours}`);

// ===== faces (ประวัติใบหน้า) =====
export const getMyFaces = () => req("/faces/me");
export const getEmployeeFaces = (employeeId) =>
  req(`/faces/employee/${employeeId}`);

export async function enrollFace(blob, note = "") {
  const fd = new FormData();
  fd.append("photo", blob, "face.jpg");
  fd.append("source", "web");
  if (note) fd.append("note", note);
  const res = await fetch(`${BASE}/faces/enroll`, {
    method: "POST",
    headers: authHeaders(), // อย่าตั้ง Content-Type เอง ให้ browser ใส่ boundary
    body: fd,
  });
  if (res.status === 401) sessionExpired();
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`บันทึกใบหน้าไม่สำเร็จ (${res.status}): ${detail}`);
  }
  return res.json();
}

// ดึงรูปแบบแนบ token แล้วคืน object URL (ใช้กับ <img src>)
export async function fetchFacePhoto(recordId) {
  const res = await fetch(`${BASE}/faces/${recordId}/photo`, {
    headers: authHeaders(),
  });
  if (res.status === 401) sessionExpired();
  if (!res.ok) throw new Error("โหลดรูปไม่สำเร็จ");
  const blob = await res.blob();
  return URL.createObjectURL(blob);
}

// ===== ไฟล์ติดตั้งแอป Flutter (APK) =====
// ไม่ต้องแนบ token — ตั้งใจให้เปิด/สแกน QR จากมือถือแล้วโหลดได้เลย
export const getAppInfo = () => req("/app/info");
// URL เต็ม เพื่อให้ QR ที่สแกนจากมือถือชี้กลับมาที่เซิร์ฟเวอร์ถูกตัว
export const appDownloadUrl = () =>
  new URL(`${BASE}/app/download`, window.location.origin).href;

// ===== ไฟล์ติดตั้งแอปหัวหน้า (Boss APK) =====
export const getBossAppInfo = () => req("/boss-app/info");
export const bossAppDownloadUrl = () =>
  new URL(`${BASE}/boss-app/download`, window.location.origin).href;
