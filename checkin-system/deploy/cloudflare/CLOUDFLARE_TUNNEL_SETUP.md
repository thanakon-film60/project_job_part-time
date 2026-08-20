# เปิดระบบออกสู่อินเทอร์เน็ตด้วย Cloudflare Tunnel

ใช้ Cloudflare Tunnel แทน ngrok / port forward / ทำ HTTPS เอง — ได้ **URL คงที่** ไม่มีหน้าเตือน และ Cloudflare จัดการใบรับรอง HTTPS ให้อัตโนมัติ

```
มือถือ / เบราว์เซอร์
        │
        ▼
https://thanakronpart-time.com          (Cloudflare — HTTPS ให้ฟรี)
https://www.thanakronpart-time.com      ← ทั้ง 3 ชี้ที่เดียวกัน
https://api.thanakronpart-time.com
        │
   (cloudflared tunnel — ขาออกอย่างเดียว ไม่ต้องเปิดพอร์ตที่ router)
        │
        ▼
IIS :80  ┬─ React ที่ build แล้ว (static)
         └─ /auth /reports /faces ... →  uvicorn 127.0.0.1:8001  →  SQLite
```

> เว็บกับ API อยู่โดเมนเดียวกัน (same-origin) จึงไม่ต้องกังวลเรื่อง CORS

---

## สถานะที่ตั้งค่าไว้แล้วบนเครื่องนี้

| รายการ | ค่า |
|--------|-----|
| โปรแกรม | cloudflared 2026.8.1 — `F:\Game\cloudflared-windows-amd64.exe` |
| Domain | `thanakronpart-time.com` (Cloudflare Registrar) |
| โดเมนที่ใช้ได้ | `thanakronpart-time.com`, `www.…`, `api.…` (ชี้ที่เดียวกันหมด) |
| ชื่อ Tunnel | `Film_Part-Time` |
| Tunnel ID | `1d37443e-8845-4c41-8c80-aa0f671ba280` |
| Credentials (ผู้ใช้) | `C:\Users\Administrator\.cloudflared\1d37443e-....json` |
| Credentials (service) | `C:\ProgramData\Cloudflare\cloudflared\1d37443e-....json` |
| config ของ service | `C:\ProgramData\Cloudflare\cloudflared\config.yml` |
| log | `F:\Game\cloudflared.log` |
| เว็บไซต์ IIS | `checkin` → `C:\inetpub\checkin` พอร์ต 80 |
| backend | Scheduled Task `ThanakonBoxCheckinAPI` → uvicorn `127.0.0.1:8001` |

> ⚠️ ไฟล์ `.json` และ `cert.pem` เป็นความลับ **ห้าม push ขึ้น Git**

---

## ติดตั้งใหม่ตั้งแต่ต้น (3 คำสั่ง)

เปิด PowerShell แบบ **Run as Administrator**

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\deploy

# 1) IIS + URL Rewrite + ARR + build React + สร้างเว็บไซต์ :80
.\windows-server\install-iis-site.ps1

# 2) backend: venv + .env + seed + Scheduled Task ที่พอร์ต 8001
.\windows-server\install-backend-task.ps1

# 3) Cloudflare Tunnel เป็น Windows Service
.\cloudflare\setup-tunnel.ps1 -InstallService
```

ทดสอบแบบไม่ติดตั้ง service (รันค้างหน้าจอ กด Ctrl+C เพื่อหยุด):

```powershell
.\cloudflare\setup-tunnel.ps1
```

---

## คำสั่งที่ใช้บ่อย

| ต้องการ | คำสั่ง |
|---------|--------|
| ดู tunnel ทั้งหมด | `F:\Game\cloudflared-windows-amd64.exe tunnel list` |
| ดูว่ามี connection ไหม | `F:\Game\cloudflared-windows-amd64.exe tunnel info Film_Part-Time` |
| ดู log | `Get-Content F:\Game\cloudflared.log -Tail 40 -Wait` |
| สถานะ / เริ่ม / หยุด tunnel | `Get-Service cloudflared` · `Start-Service cloudflared` · `Stop-Service cloudflared` |
| ถอน tunnel service | `.\cloudflare\uninstall-tunnel.ps1` |
| สถานะ / เริ่ม / หยุด backend | `Get-ScheduledTaskInfo -TaskName ThanakonBoxCheckinAPI` · `Start-ScheduledTask ...` · `Stop-ScheduledTask ...` |
| รีสตาร์ต IIS | `iisreset` |
| เช็คพอร์ตที่เปิดอยู่ | `netstat -ano \| findstr LISTENING` |

---

## อัปเดตหน้าเว็บ (React) หลังแก้โค้ด

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\frontend
$env:VITE_API_BASE = ""
npm run build
Copy-Item dist\* C:\inetpub\checkin -Recurse -Force
```

หรือรัน `install-iis-site.ps1` ซ้ำ (ทำให้ทั้งหมดนี้ให้อัตโนมัติ)

---

## การเชื่อมต่อจาก Flutter

`flutter_app/lib/config.dart` ตั้งไว้แล้ว:

```dart
static const String apiBase = "https://thanakronpart-time.com";
```

จากนั้น `flutter build apk --release` — ไม่ต้อง build ใหม่เวลารีสตาร์ตเครื่อง เพราะ URL คงที่ (ต่างจาก ngrok ฟรี)

---

## ปัญหาที่เจอจริงตอนติดตั้ง (ถ้าเจอซ้ำให้ดูตรงนี้)

| อาการ | สาเหตุ | วิธีแก้ |
|-------|--------|---------|
| เว็บขึ้น **error 530 / 1033**, `tunnel info` บอก "does not have any active connection" | service ถูกติดตั้งด้วย ImagePath ที่ไม่มี `--config` เลยหา config ไม่เจอ | `setup-tunnel.ps1` เขียน ImagePath ใหม่ให้เอง แล้ว **stop ก่อน start** (ถ้าไม่ stop process เดิมจะยังใช้ค่าเก่า) |
| `error parsing YAML: control characters are not allowed` | อ่าน/เขียน config ผิด encoding — PowerShell 5.1 อ่านไฟล์เป็น ANSI และเขียน UTF-8 พร้อม BOM | สคริปต์อ่าน-เขียนด้วย `UTF8Encoding($false)` (UTF-8 ไม่มี BOM) |
| **502 Bad Gateway** | ไม่มีอะไร listening ที่พอร์ต 80 หรือ IIS ยังไม่ทำงาน | `Get-Service W3SVC` และ `Invoke-WebRequest http://localhost/` |
| หน้าเว็บขึ้น 404 ของ IIS ทั้งที่เว็บไซต์ `checkin` รันอยู่ | `Default Web Site` แย่งพอร์ต 80 (`iisreset` สตาร์ตมันกลับมา) | ต้อง **ลบ binding** ไม่ใช่แค่ Stop — สคริปต์ทำให้แล้ว |
| path ของ API ขึ้น 404 | ยังไม่ได้เปิด ARR proxy, `web.config` ชี้พอร์ตผิด หรือ **ลืมเติมชื่อ router ใหม่ในกฎ ProxyToBackend** | เช็ค `C:\inetpub\checkin\web.config` |
| ติดตั้ง service ไม่ผ่าน: "registry key already exists" | เคยลบ service ด้วย `sc.exe delete` แล้วเหลือ registry ของ event logger | สคริปต์ลบ `HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared` ให้ |
| backend ขึ้น `password cannot be longer than 72 bytes` | `passlib 1.7.4` ใช้กับ `bcrypt 4.1+` ไม่ได้ | ตรึงไว้แล้วใน `requirements-base.txt` (`bcrypt<4.1`) |
| backend อ่าน `.env` ไม่เจอ (ยังต่อ PostgreSQL ทั้งที่ตั้ง SQLite) | ไฟล์ `.env` มี BOM | บันทึกเป็น UTF-8 ไม่มี BOM |

---

## หมายเหตุ

- cloudflared บน Windows **ไม่อัปเดตอัตโนมัติ** ต้องดาวน์โหลดเวอร์ชันใหม่มาแทนเองเป็นระยะ
- ห้ามดับเบิลคลิกไฟล์ `.exe` ตรง ๆ (จะเจอจอดำ) — ต้องรันผ่าน PowerShell พร้อมคำสั่งเสมอ
- พอร์ต **8001** ถูกเลือกเพราะพอร์ต 8000 บนเครื่องนี้มีโปรเจ็กต์อื่น (`F:\GitHub\frontend_film_dev`) ใช้อยู่
- ถ้าจะเพิ่มโดเมนใหม่: เติม block ใน `ingress` ของ `config.yml` **และ** เติมชื่อใน `$Hostnames` ของ `setup-tunnel.ps1` แล้วรัน `setup-tunnel.ps1 -InstallService` ซ้ำ
- ทุกอย่างตั้งเป็น auto-start แล้ว: IIS, Scheduled Task ของ backend และ service ของ cloudflared จะกลับมาเองหลังรีบูต
