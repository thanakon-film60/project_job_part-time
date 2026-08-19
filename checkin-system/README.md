# ระบบเช็คอินเข้างาน MARDODI

ระบบเช็คอินเข้างานที่ยืนยันด้วย **ตำแหน่ง GPS (รัศมี 2 กม. รอบออฟฟิศ)** + **สแกนใบหน้า** บันทึกเวลาเข้า/ออกลงฐานข้อมูล และให้เจ้านายดูเป็น **ปฏิทินรายเดือน**

```
Flutter app  ──(GPS ตลอดเวลา + สแกนหน้า)──►  FastAPI + PostgreSQL  ──►  React ปฏิทิน (เจ้านายดู)
```

## เริ่มใช้งานเร็วสุด

**ดับเบิลคลิก `START.bat`** → เปิดแผงควบคุม กดปุ่มเดียว (รันบนเครื่อง / อัปขึ้นเว็บจริง / เช็คสถานะ)
รายละเอียด: [`RUN_LOCAL.md`](RUN_LOCAL.md)

เว็บจริงที่ใช้งานอยู่: **https://thanakronpart-time.com**
(ใช้ได้ทั้ง `thanakronpart-time.com`, `www.thanakronpart-time.com` และ `api.thanakronpart-time.com` — ชี้ที่เดียวกันหมด)

---

## องค์ประกอบ
| ส่วน | เทคโนโลยี | โฟลเดอร์ |
|---|---|---|
| Back-end + ฐานข้อมูล | FastAPI + PostgreSQL + SQLAlchemy | `backend/` |
| หน้าจอเจ้านาย (ปฏิทิน) | React + Vite + Ant Design (responsive) | `frontend/` |
| แอปพนักงาน | Flutter (GPS + ML Kit face detection) | `flutter_app/` |
| การวิเคราะห์ Takeout | — | `TRAVEL_ANALYSIS.md` |

## สถานที่เข้างานและเงื่อนไข

รองรับ **หลายสถานที่** — เช็คอินได้ถ้าอยู่ในเขตของที่ใดที่หนึ่ง

| สถานที่ | พิกัด | รัศมี |
|---|---|---|
| **MARDODI** (บริษัท มาดูดิ จำกัด) | `13.9231953, 100.5195808` | 2 กม. |
| **BJH Bangkok** (บริษัท โรงพยาบาล บีเจเอช จำกัด) | `13.8918358, 100.563443` | 1 กม. |
| **ถึงบ้านแล้ว** | `13.8865664, 100.5066278` | 0.2 กม. (200 เมตร) |

- เช็คอินได้เมื่อ **อยู่ในรัศมีของสถานที่ใดสถานที่หนึ่ง** และ **ตรวจพบใบหน้า (liveness ผ่าน)**
- ถ้าอยู่ในเขตหลายที่พร้อมกัน ระบบเลือก **ที่ใกล้ที่สุด** และบันทึกชื่อสถานที่ลงในประวัติ (`office_name`)
- Flutter เปิด GPS ต่อเนื่อง (background service) ส่งพิกัดทุก 60 วินาที เพื่อรู้ว่าอยู่จุดไหน

### เพิ่ม / แก้ / ลบสถานที่

แก้ `OFFICES` ใน `backend/.env` — เป็น **JSON บรรทัดเดียว**:

```
OFFICES=[{"name":"MARDODI","lat":13.9231953,"lng":100.5195808,"radius_km":2.0},{"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0},{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2}]
```

แล้ว restart backend (กดปุ่ม **อัปขึ้นเว็บจริง** ใน `START.bat` หรือ `Start-ScheduledTask -TaskName MardodiCheckinAPI`)

> - หาพิกัดจาก Google Maps: คลิกขวาที่จุดนั้น → ตัวเลขชุดแรกคือ lat ชุดที่สองคือ lng
> - ถ้าเว้น `OFFICES` ว่างไว้ ระบบจะถอยไปใช้ `OFFICE_LAT` / `OFFICE_LNG` / `GEOFENCE_RADIUS_KM` เป็นสถานที่เดียว (เข้ากันได้กับของเดิม)
> - ถ้าจะให้ **แอป Flutter** แสดงระยะถูกต้องด้วย ต้องแก้ `flutter_app/lib/config.dart` → `Config.offices` ให้ตรงกัน แล้ว build APK ใหม่
>   (ตัวตัดสินว่าเช็คอินผ่านหรือไม่คือ backend เสมอ แอปแค่แสดงผลล่วงหน้า)

---

## 1) รัน Back-end (แนะนำใช้ Docker)
```bash
cd checkin-system
docker compose up --build
```
เปิด API docs ที่ http://localhost:8000/docs

### หรือรันเอง (ไม่ใช้ Docker)
```bash
cd backend
python -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env        # ปรับ DATABASE_URL ให้ชี้ PostgreSQL ของคุณ
python seed.py              # สร้างบัญชีตัวอย่าง + ข้อมูลทดสอบ
uvicorn app.main:app --reload
```

บัญชีตัวอย่างจาก `seed.py`:
- พนักงาน: `EMP001` / `password123`
- เจ้านาย: `BOSS001` / `boss12345`

## 2) รัน React (ปฏิทินให้เจ้านายดู)
```bash
cd frontend
npm install
cp .env.example .env        # ตั้ง VITE_API_BASE=http://localhost:8000
npm run dev
```
เปิด http://localhost:5173 → ถูกพาไป **`/login`** → ล็อกอิน แล้วใช้เมนู 2 หน้า:
- **`/` ปฏิทินเข้างาน** — ผู้จัดการเลือกพนักงาน/เดือน เห็นเวลาเข้า-ออกและสถานะอยู่ในออฟฟิศ
- **`/face-records` ประวัติใบหน้า** — เปิดกล้องเว็บถ่ายบันทึกใบหน้าเข้าประวัติ และดูแกลเลอรีรูปที่บันทึกไว้ (ผู้จัดการดูของพนักงานทุกคนได้)

> ⚠️ เว็บกับ API อยู่โดเมนเดียวกันและ **API ไม่มี `/api` นำหน้า** ดังนั้นชื่อ route ของหน้าเว็บห้ามซ้ำกับ path ของ API
> (หน้าประวัติใบหน้าจึงใช้ `/face-records` ไม่ใช่ `/faces` เพราะ `/faces` เป็นของ API)
> ถ้าเพิ่ม router ใหม่ใน backend ต้องไปเติมชื่อในกฎ `ProxyToBackend` ของ `deploy/windows-server/web.config` ด้วย

> หน้าเว็บมีระบบล็อกอินจริง (JWT เก็บใน localStorage) ทุกหน้าถูกป้องกัน ถ้ายังไม่ล็อกอินจะเด้งไป `/login`
> การเปิดกล้องบันทึกใบหน้าต้องรันผ่าน **HTTPS** เบราว์เซอร์ถึงจะให้ใช้กล้อง — ใช้ Cloudflare Tunnel (ดูหัวข้อ Deploy ด้านล่าง)

## 📱 ติดตั้งเป็นแอปบนมือถือ (PWA)

เว็บนี้เป็น **PWA** — ติดตั้งลงมือถือได้เหมือนแอป มีไอคอน เปิดเต็มจอ ใช้กล้อง + GPS ได้ครบ

| มือถือ | วิธีติดตั้ง |
|---|---|
| **Android** (Chrome) | เปิด https://thanakronpart-time.com → เมนู ⋮ → **ติดตั้งแอป / Add to Home screen** |
| **iPhone** (ต้องเป็น Safari) | เปิดเว็บ → ปุ่มแชร์ ⬆️ → **เพิ่มไปยังหน้าจอโฮม** |

> iPhone **ต้องใช้ Safari เท่านั้น** — Chrome บน iOS ติดตั้ง PWA ไม่ได้

**ข้อดีเทียบกับ APK:** อัปเดตทันทีที่ deploy ไม่ต้องให้พนักงานลงไฟล์ใหม่ · ใช้ได้ทั้ง Android/iOS ด้วยโค้ดชุดเดียว · ไม่ต้องติดตั้ง Flutter/Android SDK บนเซิร์ฟเวอร์

ตั้งค่าอยู่ใน `frontend/vite.config.js` (`vite-plugin-pwa`) — จงใจ **ไม่ cache คำขอที่ยิงไป API** เพื่อให้ข้อมูลเช็คอินสดเสมอ

---

## 3) รัน Flutter (แอปพนักงาน — ทางเลือก)

> โค้ด Flutter เขียนไว้ครบและต่อ API ถูกต้องแล้ว แต่ยังไม่ได้ build เป็น APK
> (เครื่องเซิร์ฟเวอร์ยังไม่มี Flutter SDK / Android SDK)
> ถ้าใช้ PWA ด้านบนอยู่แล้วก็ไม่จำเป็นต้องใช้ส่วนนี้

```bash
cd flutter_app
flutter create .            # สร้างโฟลเดอร์ android/ ios/ ครั้งแรก
# ทำตาม PLATFORM_SETUP.md เพื่อเพิ่มสิทธิ์ location/camera/background
flutter pub get
flutter run
```
ปรับ `lib/config.dart` → `apiBase` ให้ชี้ backend (emulator ใช้ `http://10.0.2.2:8001`)
ค่า production ตั้งไว้แล้วเป็น `https://thanakronpart-time.com` (เรียก API ได้ตรง ๆ ไม่มี `/api` นำหน้า)

---

## Deploy: เปิดออกสู่อินเทอร์เน็ต

**วิธีหลัก — Cloudflare Tunnel** (URL คงที่ + HTTPS ฟรี + ไม่ต้องเปิดพอร์ตที่ router)

```
มือถือ ──► https://thanakronpart-time.com ──(cloudflared)──► IIS :80 ┬─ React (static)
                                                                        └─ /auth /reports ... → uvicorn :8001
```

เปิด PowerShell แบบ Administrator แล้วรัน 3 คำสั่ง:

```powershell
cd checkin-system\deploy
.\windows-server\install-iis-site.ps1      # IIS + URL Rewrite + ARR + build React
.\windows-server\install-backend-task.ps1  # backend เป็น Scheduled Task ที่ :8001
.\cloudflare\setup-tunnel.ps1 -InstallService
```

รายละเอียดทั้งหมด คำสั่งที่ใช้บ่อย และตารางแก้ปัญหา: [`deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md`](deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md)

**ทางเลือกอื่น**

| วิธี | คู่มือ | เหมาะกับ |
|---|---|---|
| Cloudflare Tunnel ✅ | `deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md` | ใช้งานจริง — URL คงที่ ไม่มีหน้าเตือน |
| ngrok | `deploy/ngrok/NGROK_SETUP.md` | ทดสอบชั่วคราว (URL ฟรีเปลี่ยนทุกครั้งที่รีสตาร์ต) |
| โดเมนจริง + port forward | `deploy/windows-server/DEPLOY_WINDOWS_SERVER.md` | มี public IP และคุม router ได้ |

---

## API หลัก
| Method | Path | ใช้ทำอะไร |
|---|---|---|
| POST | `/auth/register` | สมัครพนักงาน/ผู้จัดการ |
| POST | `/auth/login` | เข้าสู่ระบบ (คืน JWT) |
| POST | `/checkins` | เช็คอิน/เอาต์ (ตรวจ geofence + face, แนบรูป) |
| GET | `/checkins/me` | ประวัติเช็คอินของตัวเอง |
| POST | `/faces/enroll` | บันทึกรูปใบหน้าเข้าประวัติ (face enrollment) |
| GET | `/faces/me` | ประวัติใบหน้าของตัวเอง |
| GET | `/faces/employee/{id}` | ประวัติใบหน้าของพนักงาน (ผู้จัดการ/เจ้าของ) |
| GET | `/faces/{id}/photo` | สตรีมไฟล์รูป (เฉพาะเจ้าของหรือผู้จัดการ) |
| POST | `/locations/ping` | ส่งพิกัด GPS ต่อเนื่อง |
| GET | `/reports/employees` | รายชื่อพนักงาน (เฉพาะผู้จัดการ) |
| GET | `/reports/calendar` | สรุปเข้า-ออกรายวันสำหรับปฏิทิน (เฉพาะผู้จัดการ) |
| GET | `/reports/geofence` | รายการสถานที่ทั้งหมด + รัศมี (`offices[]`) |

## ฐานข้อมูล (ตาราง)
- `employees` — พนักงาน/ผู้จัดการ (มี hashed password, is_manager)
- `checkins` — log การเข้า/ออก: เวลา, พิกัด, ระยะจากสถานที่, อยู่ในเขต?, **ชื่อสถานที่**, พบใบหน้า?, path รูป
- `location_pings` — พิกัด GPS ต่อเนื่องจาก background service (+ ชื่อสถานที่ที่ใกล้ที่สุด)

> คอลัมน์ `office_name` ถูกเพิ่มทีหลัง — `app/database.py` จะ `ALTER TABLE` เติมให้อัตโนมัติตอนสตาร์ต
> ถ้าเพิ่มคอลัมน์ใหม่ในอนาคต ให้เติมใน `_ADDED_COLUMNS` ด้วย

## หมายเหตุด้านความปลอดภัย/ต่อยอด
- โหมดใบหน้าเป็น **detection + liveness** (ยืนยันว่าเป็นคนจริง) ไม่ได้จับคู่ตัวตน 1:1 — ถ้าต้องการยืนยันว่าเป็น "คุณจริง ๆ" ต้องเพิ่ม face embeddings (FaceNet) และเก็บรูปต้นแบบ
- production: เปลี่ยน `SECRET_KEY`, จำกัด CORS, ใช้ HTTPS, และย้าย migration ไปใช้ Alembic
- รองรับหลายสาขาได้โดยเพิ่มตาราง `offices` และเทียบ geofence กับสาขาที่ใกล้ที่สุด

ดูผลการวิเคราะห์ข้อมูลการเดินทางจาก Google Takeout ได้ที่ `TRAVEL_ANALYSIS.md`
