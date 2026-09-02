# ระบบกล้องวงจรปิด CCTV — ติดตั้งบน Windows Server

ดูภาพสด · หมุนกล้อง · ฟังเสียงจากไมค์กล้อง ผ่านแอปหัวหน้าและแอปพนักงาน
(เมนู **"กล้องวงจรปิด"** โผล่เฉพาะบัญชี `is_manager = true`)

---

## สถาปัตยกรรม — ทำไมถึงใช้จากนอกวง LAN ได้

```
   มือถือหัวหน้า (4G / Wi-Fi ที่ไหนก็ได้)
            │  HTTPS + Bearer token
            ▼
   Cloudflare Tunnel → thanakronpart-time.com
            │
            ▼
   IIS (80/443) ── reverse proxy ──► uvicorn 127.0.0.1:8001
            │                        (Scheduled Task: MardodiCheckinAPI)
            │                              │
            │        ┌─────────────────────┴──────────────────────┐
            │        │  ONVIF SOAP (พอร์ต 80)   RTSP (พอร์ต 554)   │
            ▼        ▼                                            ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  กล้อง IP  192.168.1.101   (อยู่ในวง LAN เท่านั้น)              │
   └──────────────────────────────────────────────────────────────┘
```

**หัวใจของการออกแบบ: แอปไม่เคยคุยกับกล้องโดยตรง**

ภาพ คำสั่งหมุน และเสียง วิ่งผ่าน backend ทั้งหมด ผลที่ได้คือ

- หัวหน้าเปิดแอปจาก 4G ที่ไหนก็ใช้ได้ ขอแค่เข้า `thanakronpart-time.com` ได้
- **ไม่ต้อง forward port กล้องออกอินเทอร์เน็ต** ซึ่งเป็นช่องโหว่ที่กล้อง IP ราคาถูกโดนสแกนเจอบ่อยมาก
- ภาพและเสียงถูกกันด้วย token เดียวกับ endpoint อื่น และจำกัดเฉพาะหัวหน้า

**ข้อแลกเปลี่ยน: เครื่องที่รัน backend ต้องอยู่วง LAN เดียวกับกล้อง**
ถ้าย้าย backend ไปคลาวด์ ระบบกล้องจะใช้ไม่ได้ (ส่วนอื่นของระบบยังปกติ)

---

## สิ่งที่ต้องเตรียม

| อย่าง | รายละเอียด |
| --- | --- |
| กล้อง | รองรับ ONVIF และเปิด PTZ — ทดสอบแล้วกับ `ONVIF cloudCam` fw 43.4.0.0 |
| เครือข่าย | เครื่อง backend ต้อง ping กล้องเจอ (วง LAN เดียวกัน) |
| ffmpeg | **ต้องมี ถ้าจะใช้ฟังเสียง** — ส่วนภาพกับการหมุนกล้องไม่ต้องใช้ |
| Python | ไม่ต้องลง package เพิ่มเลย โค้ด ONVIF ใช้ stdlib ล้วน |

---

## ขั้นที่ 1 — ติดตั้ง ffmpeg (เฉพาะถ้าจะใช้เสียง)

```powershell
choco install ffmpeg -y
```

ไม่มี Chocolatey ก็โหลด zip จาก https://www.gyan.dev/ffmpeg/builds/ แล้วแตกไว้ที่
`C:\ffmpeg` จากนั้นชี้ path ตรง ๆ ใน `.env` ด้วย `FFMPEG_PATH`

ตรวจว่าเจอ:

```powershell
ffmpeg -version
```

> ข้ามขั้นนี้ได้ ระบบจะยังดูภาพและหมุนกล้องได้ครบ แค่ปุ่มฟังเสียงจะไม่ขึ้นในแอป
> (`/camera/status` จะตอบ `audio_supported: false` เอง)

---

## ขั้นที่ 2 — หา IP กล้องและตรวจว่าคุยได้

รันบนเครื่อง server ที่โฟลเดอร์ `backend`:

```powershell
cd C:\apps\checkin-system\backend
.\venv\Scripts\python.exe camera_onvif.py --host 192.168.1.101
```

ได้แบบนี้ = พร้อมใช้:

```
Device: ONVIF cloudCam fw 43.4.0.0
PTZ service:  http://192.168.1.101/onvif/ptz_service
Profile:      Profile_1
Home support: True
```

ทดสอบสั่งหมุนจริง (ยืนหน้ากล้องแล้วดูว่าขยับไหม):

```powershell
.\venv\Scripts\python.exe camera_onvif.py --host 192.168.1.101 --action right --duration 1.5
.\venv\Scripts\python.exe camera_onvif.py --host 192.168.1.101 --action home
```

กล้องที่ตั้งรหัสผ่านไว้ ใส่ `--username` และ `--password` เพิ่ม

---

## ขั้นที่ 3 — ใส่ค่าใน `.env`

เพิ่มท้ายไฟล์ `C:\apps\checkin-system\backend\.env`
(ค่าเต็มพร้อมคำอธิบายอยู่ใน `backend\.env.example`)

```ini
# ===== กล้องวงจรปิด ONVIF =====
CAMERA_PTZ_ENABLED=true
CAMERA_PTZ_HOST=192.168.1.101
CAMERA_PTZ_PORT=80
CAMERA_PTZ_USERNAME=
CAMERA_PTZ_PASSWORD=

# ความเร็วหมุน/ซูม 0..1
CAMERA_PTZ_SPEED=0.6
CAMERA_PTZ_ZOOM_SPEED=0.6

# กด 1 ครั้ง = หมุนกี่มิลลิวินาที และเพดานที่ยอมให้แอปขอได้
CAMERA_PTZ_DURATION_MS=600
CAMERA_PTZ_MAX_DURATION_MS=3000

# ติดกล้องกลับหัว/แขวนเพดาน แล้วกดขึ้นได้ลง ค่อยเปิด
CAMERA_PTZ_INVERT_PAN=false
CAMERA_PTZ_INVERT_TILT=false
CAMERA_TIMEOUT_SECONDS=8.0

# ===== ฟังเสียงจากไมค์กล้อง =====
CAMERA_AUDIO_ENABLED=true
CAMERA_RTSP_URL=rtsp://192.168.1.101:554
CAMERA_AUDIO_BITRATE=32k
FFMPEG_PATH=
```

> ไฟล์ `.env` ต้องเป็น **UTF-8 ไม่มี BOM** ไม่งั้น python-dotenv อ่านคีย์บรรทัดแรกเพี้ยน
> (ข้อควรระวังเดียวกับที่ `install-backend-task.ps1` เขียนไว้)

**ไม่มีกล้องที่เครื่องนั้น** ให้ตั้ง `CAMERA_PTZ_ENABLED=false` — แอปจะขึ้นข้อความบอกแทนที่จะพัง

---

## ขั้นที่ 4 — IIS ต้องรู้จัก `/camera`

`web.config` ในโค้ดชุดนี้เติม `camera` ให้แล้วในกฎ `ProxyToBackend`
ถ้าเครื่อง production ใช้ `web.config` คนละไฟล์กับใน repo ต้องเติมเอง:

```xml
<match url="^(app|addresses|auth|camera|checkins|...)(/.*)?$" />
```

**ไม่เติม = `/camera/*` จะไปโดนกฎ React แล้วตอบหน้าเว็บกลับมาแทน JSON**
แอปจะขึ้นว่าเชื่อมต่อไม่ได้ทั้งที่ backend ทำงานปกติ

### สตรีมเสียงกับ IIS ARR

`/camera/audio` เป็น response แบบไหลต่อเนื่องไม่รู้จบ ซึ่งต่างจาก endpoint อื่น
ถ้า ARR ตั้ง buffer ไว้ เสียงจะไม่ออกหรือออกช้าผิดปกติ แก้โดยปิด buffer:

```powershell
Import-Module WebAdministration
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
  -Filter "system.webServer/proxy" -Name "responseBufferThreshold" -Value 0
iisreset
```

> ข้อนี้ยังไม่ได้ทดสอบบนเครื่อง production จริง — ทดสอบมาถึงแค่ยิงตรงเข้า uvicorn
> ถ้าภาพกับการหมุนกล้องใช้ได้แต่เสียงเงียบอย่างเดียว ให้สงสัยข้อนี้ก่อน
> (Cloudflare Tunnel ไม่ buffer สตรีมแบบนี้ จึงไม่น่าเป็นต้นเหตุ)

---

## ขั้นที่ 5 — restart backend

```powershell
cd C:\apps\checkin-system\deploy\windows-server
.\deploy-update.ps1
```

หรือ restart อย่างเดียว:

```powershell
Stop-ScheduledTask  -TaskName MardodiCheckinAPI
Start-ScheduledTask -TaskName MardodiCheckinAPI
```

---

## ขั้นที่ 6 — ตรวจว่าใช้งานได้

```powershell
# ล็อกอินด้วยบัญชีหัวหน้า
$r = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8001/auth/login" `
     -Body @{ username = "BOSS001"; password = "รหัสผ่านจริง" }
$h = @{ Authorization = "Bearer $($r.access_token)" }

# 1) สถานะกล้อง
Invoke-RestMethod -Uri "http://127.0.0.1:8001/camera/status" -Headers $h

# 2) ภาพนิ่ง (ต้องได้ไฟล์ ~35KB)
Invoke-WebRequest -Uri "http://127.0.0.1:8001/camera/snapshot" -Headers $h -OutFile snap.jpg
(Get-Item snap.jpg).Length

# 3) สั่งหมุน
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8001/camera/ptz" -Headers $h `
  -ContentType "application/json" -Body '{"action":"right","duration_ms":800}'
```

`/camera/status` ควรตอบ:

```json
{
  "enabled": true,
  "reachable": true,
  "host": "192.168.1.101",
  "message": "พร้อมใช้งาน",
  "model": "cloudCam",
  "firmware": "43.4.0.0",
  "home_supported": true,
  "audio_supported": true,
  "talkback_supported": false
}
```

จากนั้นลองผ่านโดเมนจริงเพื่อยืนยันว่าใช้จากนอกวง LAN ได้:

```powershell
Invoke-RestMethod -Uri "https://thanakronpart-time.com/camera/status" -Headers $h
```

---

## ขั้นที่ 7 — build APK ใหม่

แท็บกล้องอยู่ใน **ทั้งสองแอป** ต้อง build ใหม่ทั้งคู่ถึงจะเห็นเมนู
และทั้งคู่มี dependency เพิ่ม (`just_audio`) จึงต้อง `flutter pub get` ก่อนเสมอ

**แอปพนักงาน** — สคริปต์เดิมทำให้ครบ (สร้างไอคอน + build + วางไฟล์):

```powershell
cd C:\apps\checkin-system\deploy\windows-server
.\build-flutter-apk.ps1
.\publish-apk.ps1
```

**แอปหัวหน้า** — `build-flutter-apk.ps1` ไม่ได้ครอบคลุมตัวนี้ ต้องทำมือตามขั้นตอนใน
`flutter_boss_app\BOSS_APK_PRODUCTION.md`:

```powershell
cd C:\apps\checkin-system\flutter_boss_app
flutter pub get
flutter build apk --release
Copy-Item .\build\app\outputs\flutter-apk\app-release.apk C:\Temp\thanakon-boss.apk -Force
```

แล้ววางที่ `<site>\downloads\thanakon-boss.apk`
(ห้ามเอาไปทับ `thanakon-checkin.apk` ซึ่งเป็นของแอปพนักงาน)

---

## API ที่เพิ่มเข้ามา

ทุกเส้นทางต้องเป็นบัญชีหัวหน้า (`require_manager`) — พนักงานทั่วไปได้ `403`

| Method | Path | ทำอะไร |
| --- | --- | --- |
| `GET` | `/camera/status` | ต่อกล้องติดไหม + รุ่น/เฟิร์มแวร์ + รองรับเสียงไหม |
| `GET` | `/camera/snapshot` | ภาพนิ่ง JPEG 1 เฟรม |
| `POST` | `/camera/ptz` | หมุนกล้อง `{"action": "...", "duration_ms": 600}` |
| `POST` | `/camera/ptz/stop` | สั่งหยุดทันที (ปุ่มฉุกเฉิน) |
| `GET` | `/camera/audio` | สตรีมเสียง AAC จากไมค์กล้อง |

`action` ที่รับ: `up` `down` `left` `right` `zoom_in` `zoom_out` `home` `stop`

### ทำไมเซิร์ฟเวอร์เป็นคนสั่งหยุดกล้องเอง

แอปส่งแค่ "หมุนขวา 600ms" แล้วเซิร์ฟเวอร์สั่ง `Stop` ให้เองเมื่อครบเวลา
ไม่ได้ให้แอปส่ง `stop` ตามมาทีหลัง เพราะถ้าเน็ตมือถือหลุดกลางทาง
คำสั่งหยุดจะไม่ถึงกล้อง แล้วกล้องจะหมุนค้างไปเรื่อย ๆ จนกว่าจะชนสุดระยะ

---

## ข้อจำกัดที่ทดสอบแล้ว

| เรื่อง | สถานะ | รายละเอียด |
| --- | --- | --- |
| หมุน/ก้ม/เงย/ซูม | ใช้ได้ | ผ่าน ONVIF `ContinuousMove` + `Stop` |
| กลับตำแหน่งตั้งต้น | ใช้ได้ | `GotoHomePosition` |
| ฟังเสียงจากกล้อง | ใช้ได้ | RTSP มี track `PCMA/8000` |
| **พูดออกลำโพงกล้อง** | **ยังไม่ได้ในระบบเรา** | แอป iCam365 ทำได้ แต่กล้องไม่เปิด RTSP backchannel มาตรฐาน |
| `AbsoluteMove` / `RelativeMove` | ทำไม่ได้ | เฟิร์มแวร์ตอบ `space not supported by the PTZ Node` |

**เรื่องพูดกลับ** — ยิง `DESCRIBE` พร้อม `Require: www.onvif.org/ver20/backchannel`
แล้วกล้องตอบ SDP เดิมไม่มี track ขาส่งเพิ่ม จึงทำไม่ได้ผ่าน ONVIF/RTSP มาตรฐาน
ที่ระบบเราใช้ตอนนี้ แต่ไม่ใช่ข้อสรุปว่าฮาร์ดแวร์ทำไม่ได้ เพราะแอป iCam365 พูดออกกล้องได้จริง
ถ้าจะทำกับกล้องรุ่นนี้ต้องใช้ SDK/credential ของ Tange หรือจับแพ็กเก็ตตอน iCam365 กดพูด
ดูขั้นต่อที่ [`ICAM365_TALKBACK.md`](ICAM365_TALKBACK.md)

**เสียงเริ่มดังช้า ~6 วินาที** — เป็นเวลาที่กล้องใช้ setup RTSP เอง วัดแล้วปรับ
flag ของ ffmpeg ยังไงก็ไม่ต่ำกว่านี้ (ลอง `-allowed_media_types audio` แล้วกล้องไม่ส่งอะไรเลย
เพราะกล้องรุ่นนี้บังคับให้เปิด track วิดีโอด้วย)

---

## แก้ปัญหา

| อาการ | สาเหตุ / วิธีแก้ |
| --- | --- |
| `เชื่อมต่อกล้องไม่ได้: URL error: timed out` | เครื่อง server ไม่ได้อยู่วง LAN เดียวกับกล้อง หรือ IP เปลี่ยน — เช็คด้วย `ping 192.168.1.101` แล้วแก้ `CAMERA_PTZ_HOST` |
| `403 ต้องเป็นผู้จัดการเท่านั้น` | ล็อกอินด้วยบัญชีที่ `is_manager = false` |
| ปุ่มฟังเสียงไม่ขึ้นในแอป | เซิร์ฟเวอร์หา ffmpeg ไม่เจอ — ตั้ง `FFMPEG_PATH` ให้ชี้ `ffmpeg.exe` ตรง ๆ |
| กดขึ้นแล้วกล้องก้มลง | เปิด `CAMERA_PTZ_INVERT_TILT=true` (ซ้าย/ขวาสลับใช้ `CAMERA_PTZ_INVERT_PAN`) |
| กล้องหมุนแล้วไม่หยุด | ยิง `POST /camera/ptz/stop` หรือกดปุ่ม "สั่งหยุดทันที" ในแอป |
| ภาพค้าง/ไม่อัปเดต | กล้องหลุด — แอปยังโชว์เฟรมล่าสุดพร้อมข้อความ "ภาพสะดุด" กด refresh ที่มุมขวาล่างของจอ |
| แอป build ไม่ผ่านที่ `just_audio` / `audio_session` | ทั้งคู่ถูกตรึงเวอร์ชันไว้ใน `pubspec.yaml` แล้ว อย่าอัปเกรดจนกว่าจะขยับ AGP เป็น 9 (ดูคอมเมนต์ในไฟล์) |
| มี `ffmpeg.exe` ค้างเต็มเครื่อง | ไม่ควรเกิดแล้ว — endpoint เสียงฆ่าโปรเซสเมื่อแอปตัดการเชื่อมต่อ ถ้ายังเจอให้เช็คว่าอัปโค้ดครบ |

ตรวจสถานะ backend:

```powershell
Get-ScheduledTaskInfo -TaskName MardodiCheckinAPI
Invoke-RestMethod -Uri "http://127.0.0.1:8001/health"
```

อยากเห็น log ของกล้องแบบเรียลไทม์ ให้หยุด task แล้วรัน uvicorn มือชั่วคราว:

```powershell
Stop-ScheduledTask -TaskName MardodiCheckinAPI
cd C:\apps\checkin-system\backend
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8001
# ทดสอบเสร็จแล้ว Ctrl+C  แล้ว  Start-ScheduledTask -TaskName MardodiCheckinAPI
```

---

## ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | หน้าที่ |
| --- | --- |
| `backend/camera_onvif.py` | ONVIF client (stdlib ล้วน) + เครื่องมือทดสอบในตัว |
| `backend/camera_audio.py` | ดึงเสียง RTSP ผ่าน ffmpeg |
| `backend/camera_ptz.py` | รวมโปรไฟล์ PTZ หลายแบบ (`onvif`, `hi3510`, `ptzctrl`, `hy-cgi`, `custom`) |
| `backend/app/routers/camera.py` | endpoint `/camera/*` |
| `backend/camera_ffmpeg_gui.py` | โปรแกรมหน้าจอบนคอม ไว้ทดสอบกล้องตรง ๆ |
| `flutter_app/lib/screens/tabs/camera_tab.dart` | หน้าจอกล้องในแอปพนักงาน (ซ่อนถ้าไม่ใช่หัวหน้า) |
| `flutter_boss_app/lib/screens/tabs/camera_tab.dart` | หน้าจอกล้องในแอปหัวหน้า |
