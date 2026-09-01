# รันดูเว็บบนเครื่องตัวเอง (ทดสอบเร็ว ใช้ SQLite)

> ถ้าอยากเปิดให้คนอื่นเข้าจากอินเทอร์เน็ต (และให้แอป Flutter เรียกได้) ไม่ต้องใช้วิธีในหน้านี้
> ระบบตั้งไว้แล้วที่ **https://thanakronpart-time.com** ผ่าน Cloudflare Tunnel (ใช้ `www.` และ `api.` ได้ด้วย)
> ดู [`deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md`](deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md)

---

## วิธีที่ง่ายที่สุด — ดับเบิลคลิก `START_PART_TIME.bat`

ที่โฟลเดอร์ `checkin-system` มีไฟล์ **`START_PART_TIME.bat`** — ดับเบิลคลิกแล้วจะเปิด **แผงควบคุม** ขึ้นมา กดปุ่มเอาได้เลย ไม่ต้องเปิด VS Code ไม่ต้องจำคำสั่ง

| ปุ่ม | ทำอะไร |
|---|---|
| ▶ **รันบนเครื่องนี้** | ติดตั้งไลบรารีให้ถ้ายังไม่มี → สร้างข้อมูลตัวอย่าง → เปิด backend + หน้าเว็บ → เปิดเบราว์เซอร์ให้ |
| ■ **หยุดที่รันบนเครื่อง** | ปิด backend + หน้าเว็บที่รันอยู่ (ไม่กระทบเว็บจริง) |
| ▲ **อัปขึ้นเว็บจริง** | build React → copy ขึ้น IIS → restart backend → ทดสอบผ่านโดเมนจริงให้ |
| ✓ **เช็คสถานะเว็บจริง** | ดูว่า IIS / backend / Cloudflare Tunnel ยังปกติไหม |
| ◆ **เปิดเว็บจริง** | เปิด https://thanakronpart-time.com ในเบราว์เซอร์ |
| ⚙ **ติดตั้งใหม่ทั้งหมด** | IIS + backend + tunnel (ใช้ตอนย้ายเครื่อง / ระบบพัง) |

แถบบนสุดจะแสดงสถานะสด ๆ 3 อย่าง: **เว็บจริง / เครื่องนี้ (dev) / Cloudflare Tunnel** พร้อมไฟเขียว-แดง อัปเดตทุก 30 วินาที
ผลลัพธ์ของทุกคำสั่งจะขึ้นในกล่องดำด้านขวาเป็นภาษาไทย

> 💡 คลิกขวาที่ `START_PART_TIME.bat` → **Send to → Desktop (create shortcut)** จะได้ไอคอนบนหน้าจอ กดจากตรงนั้นได้เลย

**ทำไมต้องเป็นหน้าต่างโปรแกรม ไม่ใช่หน้าต่างดำ:** หน้าต่าง cmd/PowerShell ของ Windows ใช้ฟอนต์ที่ไม่มีตัวอักษรไทย ภาษาไทยจะกลายเป็น `???` ทั้งหมด แม้ตั้ง UTF-8 แล้วก็ตาม — แผงควบคุมนี้เป็นหน้าต่างโปรแกรมจริง (WinForms) จึงใช้ฟอนต์ระบบและอ่านภาษาไทยได้ครบ

> หน้าต่างสีดำที่เด้งขึ้นมาตอนกด "รันบนเครื่องนี้" (BACKEND / FRONTEND) ตั้งใจให้เป็นภาษาอังกฤษล้วน ด้วยเหตุผลเดียวกัน — ปิดหน้าต่างนั้น = หยุดตัวนั้น

---

## วิธีที่ 1 — ผ่าน VS Code (ถ้าจะแก้โค้ด)

**เปิดโฟลเดอร์ `checkin-system` ใน VS Code** (ไม่ใช่ `project_job_part-time`) ไม่งั้นไฟล์ `.vscode/` จะไม่ทำงาน

> ครั้งแรกมุมซ้ายล่างจะขึ้น "Restricted Mode" ให้กด **Manage → Trust**
> และมุมขวาล่างจะชวนติดตั้ง extension ที่แนะนำ — กด Install ให้ครบ

### ครั้งแรกครั้งเดียว
`Ctrl+Shift+P` → **Tasks: Run Task** → **1. Dev: ติดตั้งไลบรารีทั้งหมด**
(สร้าง venv + `pip install` + `npm install`)

จากนั้น → **Dev: ใส่ข้อมูลตัวอย่าง (seed)**

### รันทุกครั้งที่ทำงาน
เลือกอย่างใดอย่างหนึ่ง:

| ต้องการ | วิธี |
|---|---|
| รันเฉย ๆ ทั้ง backend + frontend | `Ctrl+Shift+B` (หรือ Run Task → **Dev: รันทั้งหมด**) |
| **debug** ใส่ breakpoint ในโค้ด Python | กด **F5** → เลือก *Backend: debug (uvicorn :8002)* |
| debug ทั้ง backend + เปิด Chrome ให้ | F5 → *รันทั้งระบบ (backend debug + frontend)* |

เปิด http://localhost:5173 (หน้าเว็บ) และ http://localhost:8002/docs (API docs)

### Task ฝั่ง production

| Task | ทำอะไร |
|---|---|
| **Deploy: ตรวจสถานะ production** | เช็ค IIS / backend / tunnel + ยิงทดสอบผ่านโดเมนจริง |
| **Deploy: อัปเดตขึ้น production** | build React → copy ขึ้น IIS → restart backend → ทดสอบให้ |
| **Deploy: ดู log ของ Cloudflare Tunnel** | tail log แบบ realtime |

> 2 อันแรกต้องเปิด VS Code แบบ **Run as Administrator** (คลิกขวาที่ไอคอน VS Code → Run as administrator)

---

## วิธีที่ 2 — พิมพ์เองใน Terminal

ต้องเปิด **2 Terminal พร้อมกัน**

### Terminal ที่ 1 — Backend
```powershell
cd backend
.\run-local.ps1
```
สคริปต์จะสร้าง venv, ลงไลบรารี, ใส่ข้อมูลตัวอย่าง แล้วรัน API ที่ http://localhost:8002
**ปล่อยหน้าต่างนี้ไว้ อย่าปิด**

> ถ้าเจอ error ว่ารันสคริปต์ไม่ได้ (execution policy) ให้พิมพ์ก่อน 1 ครั้ง:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

### Terminal ที่ 2 — Frontend
กด **+** เปิด Terminal ใหม่ (อย่าปิดอันแรก) แล้ว:
```powershell
cd frontend
npm install
$env:VITE_API_BASE = "http://localhost:8002"
npm run dev
```
จะขึ้นบรรทัด `Local: http://localhost:5173/` → กด Ctrl+คลิก เปิดในเบราว์เซอร์

---

## พอร์ตบนเครื่องนี้ (อย่าใช้ชนกัน)

| พอร์ต | ใคร | หมายเหตุ |
|---|---|---|
| 80 | IIS — เว็บ production | อยู่หลัง Cloudflare Tunnel |
| 8000 | **โปรเจ็กต์อื่น** (`frontend_film_dev`) | ห้ามใช้ |
| 8001 | backend production | Scheduled Task `ThanakonBoxCheckinAPI` |
| **8002** | **backend ตอน dev** | ใช้ตัวนี้เวลาเขียนโค้ด |
| 5173 | React dev server (vite) | |
| 5432 | PostgreSQL 16 บนเครื่อง | ฐานข้อมูล production |
| **8010** | backend ใน Docker | `docker-compose.yml` |
| **5433** | PostgreSQL ใน Docker | `docker-compose.yml` |

ฐานข้อมูล dev แยกเป็นคนละไฟล์ (`checkin-dev.db`) จึงแก้อะไรก็ไม่กระทบข้อมูล production

---

## วิธีที่ 3 — Docker Desktop (ยกทั้ง backend + PostgreSQL)

ได้สภาพแวดล้อมใกล้เคียง production กว่า SQLite เพราะเป็น PostgreSQL จริง แต่ยังแยกจากของจริงสนิท

```powershell
cd checkin-system
copy .env.example .env      # ครั้งแรกครั้งเดียว แล้วแก้ POSTGRES_PASSWORD
docker compose up -d --build
docker compose run --rm backend python seed.py
```
เปิด http://localhost:8010/docs · ฝั่ง React ตั้ง `$env:VITE_API_BASE = "http://localhost:8010"`

รายละเอียดและคำสั่งที่ใช้บ่อยอยู่ในหัวข้อ "รัน Back-end" ของ [`README.md`](README.md)

> **ข้อกำหนดของเครื่อง** — Docker Desktop บน Windows Server 2022 ต้องมี WSL2
> ถ้า `docker info` ขึ้น *"Docker Desktop is unable to start"* ให้รัน `wsl --install --no-distribution`
> แล้ว **รีสตาร์ตเครื่อง 1 ครั้ง** (การรีสตาร์ตจะทำให้เว็บ production ล่มชั่วคราว —
> IIS / Scheduled Task `ThanakonBoxCheckinAPI` / Cloudflare Tunnel ตั้ง auto-start ไว้แล้ว จะกลับมาเอง)

---

## ล็อกอินและดูผล
เปิด http://localhost:5173 → ระบบพาไปหน้า `/login`

| บัญชี | รหัสผ่าน | เห็นอะไร |
|---|---|---|
| `BOSS001` | `boss12345` | ปฏิทินเข้างาน (มีข้อมูลตัวอย่าง 5 วัน) + ประวัติใบหน้า |
| `EMP001` | `password123` | หน้าประวัติใบหน้าของตัวเอง |

## อยากเห็น "รูปภาพใบหน้า"
1. ล็อกอิน แล้วไปแท็บ **ประวัติใบหน้า**
2. เบราว์เซอร์จะขอสิทธิ์กล้อง → กด **อนุญาต** (บน `localhost` ใช้กล้องได้เลย ไม่ต้อง HTTPS)
3. กดปุ่ม **ถ่าย & บันทึกใบหน้า** → รูปจะถูกบันทึกและโชว์เป็นการ์ดในแกลเลอรีทันที
4. ถ้าล็อกอินเป็น `BOSS001` จะมีช่องเลือกดูรูปของพนักงานแต่ละคนได้

> รูปจะถูกเก็บไว้ที่ `backend\storage\faces\` และฐานข้อมูล `backend\checkin.db`

---

## ปัญหาที่พบบ่อย
- **หน้าเว็บว่าง/ล็อกอินไม่ได้** → ตรวจว่า Terminal ที่ 1 (backend) ยังรันอยู่ที่พอร์ต 8002
- **กล้องไม่ขึ้น** → ต้องเปิดผ่าน `http://localhost:5173` เท่านั้น (ถ้าเปิดด้วย IP เช่น 127.0.0.1 ก็ได้ แต่ถ้าเป็น IP เครื่องในวง LAN เบราว์เซอร์จะบล็อกกล้องเพราะไม่ใช่ HTTPS)
- **`npm` หรือ `python` ไม่รู้จัก** → ยังไม่ได้ติดตั้ง Node.js / Python หรือยังไม่ได้ปิด-เปิด Terminal ใหม่หลังติดตั้ง
- **`ERROR: Failed building wheel for psycopg2-binary / pydantic-core`** → เกิดจากพยายามลงไดรเวอร์ PostgreSQL ตอนรันโลคอล
  แก้แล้วในสคริปต์เวอร์ชันล่าสุด: `run-local.ps1` จะลง **`requirements-base.txt`** (ไม่รวม psycopg2) ให้อัตโนมัติ
  ถ้าเคยรันแล้วพัง ให้รัน `.\run-local.ps1` อีกครั้ง — สคริปต์จะลบ venv เดิมที่ไม่สมบูรณ์แล้วสร้างใหม่ให้เอง
  (psycopg2/PostgreSQL ใช้เฉพาะตอน deploy จริงเท่านั้น ตอนทดสอบใช้ SQLite ก็พอ)
