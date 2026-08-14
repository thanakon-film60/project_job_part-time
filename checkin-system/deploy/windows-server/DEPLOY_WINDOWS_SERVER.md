# Deploy บน Windows Server (Native: IIS + PostgreSQL + NSSM) — เข้าจากอินเทอร์เน็ตได้

สถาปัตยกรรมที่จะติดตั้ง — ทุกอย่างอยู่บน Windows Server เครื่องเดียว:

```
                    อินเทอร์เน็ต
                         │  (โดเมน + HTTPS 443)
                         ▼
   ┌─────────────────────────────────────────────┐
   │  IIS  (เว็บไซต์เดียว, พอร์ต 80/443)           │
   │   • เสิร์ฟ React (ไฟล์ static ที่ build แล้ว) │
   │   • /api/* ── reverse proxy ──►              │
   └───────────────────────┬─────────────────────┘
                           │ 127.0.0.1:8000
                           ▼
   ┌─────────────────────────────────────────────┐
   │  uvicorn (FastAPI) รันเป็น Windows Service    │
   │  ผ่าน NSSM  ── 127.0.0.1:5432 ──►            │
   └───────────────────────┬─────────────────────┘
                           ▼
   ┌─────────────────────────────────────────────┐
   │  PostgreSQL (เฉพาะ localhost)                 │
   └─────────────────────────────────────────────┘

แอป Flutter บนมือถือ ──► https://checkin.โดเมนคุณ/api
```

> หลักการ: เปิดสู่ภายนอกแค่พอร์ต **80/443** ที่ IIS เท่านั้น
> ส่วน backend (8000) และ PostgreSQL (5432) ให้คุยกันภายในเครื่องผ่าน `127.0.0.1` — ปลอดภัยกว่า

ไฟล์ในโฟลเดอร์นี้:
- `web.config` — วางในโฟลเดอร์เว็บไซต์ IIS (reverse proxy + SPA)
- `install-backend-service.ps1` — ติดตั้ง backend เป็น Windows Service
- `open-firewall.ps1` — เปิดพอร์ต 80/443
- `.env.production.example` — ตัวอย่างตัวแปรแวดล้อม production

---

## สิ่งที่ต้องเตรียม (ติดตั้งครั้งเดียว)
1. **โดเมน** ชี้ A record มาที่ IP สาธารณะของ Windows Server (เช่น `checkin.example.com`)
2. **Port forward** ที่ router: 80→เครื่อง, 443→เครื่อง
3. ซอฟต์แวร์บนเครื่อง:
   - Python 3.11+ (ติ๊ก Add to PATH)
   - Node.js 18+ (ใช้ตอน build React)
   - PostgreSQL 16 (Windows installer จาก EDB)
   - IIS + โมดูล **URL Rewrite** และ **Application Request Routing (ARR)**
   - **NSSM** ( `choco install nssm` หรือดาวน์โหลดจาก nssm.cc )
   - **win-acme** (สำหรับใบรับรอง HTTPS ฟรีจาก Let's Encrypt)

---

## ขั้นที่ 1 — วางไฟล์โปรเจกต์
คัดลอกทั้งโฟลเดอร์ `checkin-system` ไปไว้ที่เช่น `C:\apps\checkin-system`

## ขั้นที่ 2 — ตั้งค่า PostgreSQL
เปิด SQL Shell (psql) แล้วรัน:
```sql
CREATE DATABASE checkin;
CREATE USER checkin WITH PASSWORD 'ใส่รหัสผ่านที่แข็งแรง';
GRANT ALL PRIVILEGES ON DATABASE checkin TO checkin;
```
> ปล่อย PostgreSQL ให้ฟังแค่ `localhost` (ค่าเริ่มต้น) ไม่ต้องเปิดพอร์ต 5432 ออกภายนอก

## ขั้นที่ 3 — ตั้งค่า backend
```powershell
cd C:\apps\checkin-system\backend
python -m venv venv
venv\Scripts\pip install -r requirements.txt
copy ..\deploy\windows-server\.env.production.example .env
notepad .env      # แก้ DATABASE_URL, SECRET_KEY, ALLOWED_ORIGINS
```
เพิ่มบรรทัดนี้ใน `.env` (จำกัด CORS ให้เฉพาะโดเมนจริง):
```
ALLOWED_ORIGINS=https://checkin.example.com
```
สร้างตาราง + บัญชีตัวอย่าง:
```powershell
venv\Scripts\python seed.py
```

## ขั้นที่ 4 — ติดตั้ง backend เป็น Windows Service
เปิด PowerShell **แบบ Administrator**:
```powershell
cd C:\apps\checkin-system\deploy\windows-server
# แก้ค่าตัวแปรแวดล้อมในสคริปต์ให้ตรงก่อน (DATABASE_URL, SECRET_KEY)
.\install-backend-service.ps1 -AppDir "C:\apps\checkin-system\backend"
```
ทดสอบ:
```powershell
curl http://127.0.0.1:8000/health      # ควรได้ {"status":"ok"}
Get-Service MardodiCheckinAPI          # ควรเป็น Running
```
Service จะสตาร์ตอัตโนมัติเมื่อรีบูตเครื่อง

## ขั้นที่ 5 — Build React
```powershell
cd C:\apps\checkin-system\frontend
npm install
# ตั้ง base ของ API ให้เป็น /api (ผ่าน reverse proxy โดเมนเดียวกัน)
echo VITE_API_BASE=/api > .env.production
npm run build
```
ได้ผลลัพธ์ในโฟลเดอร์ `frontend\dist`

## ขั้นที่ 6 — สร้างเว็บไซต์ใน IIS
1. เปิด IIS Manager > Sites > Add Website
   - Site name: `checkin`
   - Physical path: `C:\apps\checkin-system\frontend\dist`
   - Binding: http, พอร์ต 80, hostname `checkin.example.com`
2. คัดลอก `deploy\windows-server\web.config` ไปวางใน `frontend\dist`
3. เปิด proxy ของ ARR (ครั้งเดียว): IIS Manager > คลิกที่ชื่อเครื่อง (root) >
   **Application Request Routing Cache** > ขวามือ **Server Proxy Settings** > ติ๊ก **Enable proxy** > Apply

## ขั้นที่ 7 — เปิด HTTPS (Let's Encrypt)
```powershell
# รัน win-acme
wacs.exe
# เลือก N (new cert) > เลือกเว็บไซต์ checkin > ทำตามขั้นตอน
```
win-acme จะสร้าง binding 443 + ต่ออายุใบรับรองอัตโนมัติให้เอง

## ขั้นที่ 8 — เปิด Firewall
```powershell
cd C:\apps\checkin-system\deploy\windows-server
.\open-firewall.ps1
```

## ขั้นที่ 9 — ตั้งค่าแอป Flutter ให้ชี้เซิร์ฟเวอร์
แก้ `flutter_app\lib\config.dart`:
```dart
static const String apiBase = "https://checkin.example.com/api";
```
แล้ว build:
```powershell
cd C:\apps\checkin-system\flutter_app
flutter build apk --release     # ได้ไฟล์ .apk ไปติดตั้งบนมือถือ
```

---

## ตรวจสอบว่าใช้งานได้
| ทดสอบ | คาดหวัง |
|---|---|
| เปิด `https://checkin.example.com` | เห็นหน้าล็อกอินปฏิทิน (React) |
| `https://checkin.example.com/api/health` | ได้ `{"status":"ok"}` |
| ล็อกอิน `BOSS001 / boss12345` | เห็นปฏิทินพนักงาน |
| แอป Flutter บนมือถือ (4G/นอกวง LAN) | เช็คอินได้เมื่ออยู่ในรัศมี 2 กม. |

## ดูแลรักษา
- อัปเดตโค้ด backend: วางไฟล์ใหม่ แล้ว `nssm restart MardodiCheckinAPI`
- อัปเดต React: `npm run build` ใหม่ แล้วทับโฟลเดอร์ `dist`
- log ของ API: `C:\apps\checkin-system\backend\logs\api-*.log`
- สำรอง DB: `pg_dump -U checkin checkin > backup.sql` (ตั้ง Task Scheduler ให้รันรายวัน)

## ความปลอดภัยที่ควรทำ
- เปลี่ยน `SECRET_KEY` และรหัส PostgreSQL เป็นค่าสุ่มที่แข็งแรง
- ตั้ง `ALLOWED_ORIGINS` ให้เป็นโดเมนจริงเท่านั้น (อย่าใช้ `*`)
- เปิด HTTPS เสมอ (บังคับ redirect 80→443 ได้ใน IIS URL Rewrite)
- ข้อมูลตำแหน่ง + รูปใบหน้าเป็นข้อมูลส่วนบุคคล ควรแจ้งพนักงานและกำหนดระยะเก็บรักษา
