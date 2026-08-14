const BASE = import.meta.env.VITE_API_BASE || "http://localhost:8000";

const SKIP = { "ngrok-skip-browser-warning": "true" }; // ข้ามหน้าเตือน ngrok

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
    clearSession();
    throw new Error("หมดเวลาเข้าสู่ระบบ กรุณาล็อกอินใหม่");
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
export const getGeofence = () => req("/reports/geofence");
export const getCalendar = (employeeId, year, month) =>
  req(`/reports/calendar?employee_id=${employeeId}&year=${year}&month=${month}`);

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
  if (!res.ok) throw new Error(`บันทึกใบหน้าไม่สำเร็จ (${res.status})`);
  return res.json();
}

// ดึงรูปแบบแนบ token แล้วคืน object URL (ใช้กับ <img src>)
export async function fetchFacePhoto(recordId) {
  const res = await fetch(`${BASE}/faces/${recordId}/photo`, {
    headers: authHeaders(),
  });
  if (!res.ok) throw new Error("โหลดรูปไม่สำเร็จ");
  const blob = await res.blob();
  return URL.createObjectURL(blob);
}
