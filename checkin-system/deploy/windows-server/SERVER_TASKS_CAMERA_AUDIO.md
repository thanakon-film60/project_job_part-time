# งานฝั่งเซิร์ฟเวอร์: ทำให้ "ฟังเสียงจากกล้อง" ใช้ได้จริงผ่านโดเมน

เอกสารนี้สำหรับ **คนดูแลเครื่อง production** (เครื่องที่รัน IIS + backend + Cloudflare Tunnel)
ทุกอย่างในนี้ทำที่เครื่องนั้น ฝั่งแอปแก้เสร็จและทดสอบกับกล้องจริงแล้ว

**สรุปสั้น: มี 4 งาน** — งานที่ 1 กับ 2 ต้องทำ, งานที่ 3 ต้องตรวจก่อนว่าจำเป็นไหม, งานที่ 4 รอ credential แล้วตั้งค่า TiRTC

| # | งาน | ความเร่งด่วน | เวลา |
|---|---|---|---|
| 1 | [เอาโค้ด backend ตัวใหม่ขึ้น](#งานที่-1-เอาโค้ด-backend-ตัวใหม่ขึ้น) | **ต้องทำ** | 5 นาที |
| 2 | [เก็บกวาด ffmpeg ที่ค้างอยู่](#งานที่-2-เก็บกวาด-ffmpeg-ที่ค้างอยู่) | **ต้องทำ** | 2 นาที |
| 3 | [ตรวจว่า IIS หน่วงสตรีมเสียงหรือเปล่า](#งานที่-3-ตรวจว่า-iis-หน่วงสตรีมเสียงหรือเปล่า) | ตรวจก่อน | 5 นาที |
| 4 | [เรื่องปุ่มกดพูด (iCam365)](#งานที่-4-เรื่องปุ่มกดพูด-icam365) | ขอ credential + deploy | 10 นาทีหลังได้ค่า |

---

## งานที่ 1: เอาโค้ด backend ตัวใหม่ขึ้น

> ## ✅ แก้แล้วเมื่อ 2 ก.ย. 2026 17:00 น. — restart backend เรียบร้อย
>
> `/camera/audio` ขึ้น production แล้ว ยืนยันจาก `/openapi.json`:
>
> ```
> /camera/status  /camera/ptz  /camera/ptz/stop  /camera/snapshot  /camera/audio
>
> CameraStatusOut: enabled, reachable, host, message, model, firmware,
>                  home_supported, audio_supported, audio_note,
>                  talkback_supported, talkback_note
> ```
>
> `deploy-update.ps1 -CheckOnly` ขึ้น `[OK]` ครบทุก router
> **เหลือแค่ทดสอบจากแอปจริงว่ากดฟังแล้วได้ยินเสียงไหม**
> ถ้าขึ้น "ต่อเสียงไม่ทัน" ค่อยไปทำ [งานที่ 3](#งานที่-3-ตรวจว่า-iis-หน่วงสตรีมเสียงหรือเปล่า)
>
> ---
>
> ### บันทึกการวิเคราะห์ (เก็บไว้อ้างอิง)
>
> #### 🔴 ยืนยันเมื่อ 2 ก.ย. 2026 — นี่คือต้นเหตุที่หัวหน้าฟังเสียงไม่ได้
>
> ตรวจจาก `https://thanakronpart-time.com/openapi.json` (ไม่ต้องล็อกอิน) พบว่า
> **backend บน production ยังไม่เคยมีฟีเจอร์เสียงเลย** ไม่ใช่แค่ยังไม่ได้อัปเดตรอบล่าสุด
>
> ```
> เส้นทาง /camera/* ที่ production มีอยู่จริง:
>    /camera/status
>    /camera/ptz
>    /camera/ptz/stop
>    /camera/snapshot
>                       <-- ไม่มี /camera/audio
>
> ฟิลด์ใน CameraStatusOut ที่ production ตอบ:
>    enabled, reachable, host, message, model, firmware, home_supported
>                       <-- ไม่มี audio_supported เลย
> ```
>
> แอปอ่าน `audio_supported` ไม่เจอ จึงถือว่าเป็น `false` แล้วขึ้นข้อความ
> **"เซิร์ฟเวอร์นี้ยังส่งเสียงจากกล้องไม่ได้"** — ตรงกับที่หัวหน้าเจออยู่ทุกวันนี้
>
> `audio_supported` ถูกเพิ่มเข้า repo ตั้งแต่ commit `af8e7dd` (1 ก.ย. 2026)
> แปลว่าโค้ดที่รันอยู่บน production **เก่ากว่านั้น**
>
> ### แปลว่า
>
> * **ไม่ใช่ปัญหาของแอป** — แอปทำถูกแล้ว เซิร์ฟเวอร์ตอบว่าไม่รองรับก็ต้องขึ้นข้อความนั้น
> * **ยังไม่ต้องไปยุ่งกับ ffmpeg หรือ ARR** ([งานที่ 2](#งานที่-2-เก็บกวาด-ffmpeg-ที่ค้างอยู่)
>   กับ [งานที่ 3](#งานที่-3-ตรวจว่า-iis-หน่วงสตรีมเสียงหรือเปล่า)) — ทั้งสองอย่างจะมีผล
>   ก็ต่อเมื่อ `/camera/audio` มีอยู่จริงบนเซิร์ฟเวอร์ก่อน
> * **ทำงานนี้ให้เสร็จก่อน แล้วค่อยทดสอบใหม่** ถ้ายังไม่ได้เสียงค่อยไปดูงานที่ 2-3
>
> ### ตรวจซ้ำหลัง deploy ด้วยคำสั่งนี้ (ไม่ต้องล็อกอิน)
>
> ```powershell
> $spec = Invoke-RestMethod https://thanakronpart-time.com/openapi.json
> $spec.paths.PSObject.Properties.Name | Where-Object { $_ -like "/camera*" }
> ```
>
> ต้องเห็น `/camera/audio` อยู่ในรายการ ถ้ายังไม่เห็น = deploy ยังไม่สำเร็จจริง
> (อย่าเพิ่งไปเช็คในแอป เพราะแยกไม่ออกว่าติดตรงไหน)

> ## 💡 ที่แท้จริงแล้ว **แค่ restart ก็พอ** — ไม่ต้อง pull ไม่ต้อง build
>
> ตรวจเพิ่มเมื่อ 2 ก.ย. 2026 พบว่าโค้ดบนดิสก์ถูกต้องอยู่แล้ว
> ที่เก่าคือ **โปรเซสที่รันอยู่** เพราะ uvicorn โหลดโค้ดตอนสตาร์ตครั้งเดียว
> (ไม่มี `--reload`) ไฟล์เปลี่ยนทีหลังจึงไม่ถูกอ่านใหม่
>
> | | เวลา |
> |---|---|
> | โปรเซส backend เริ่มรัน | **1 ก.ย. 17:29** |
> | commit `af8e7dd` ที่เพิ่ม `audio_supported` | **1 ก.ย. 18:00** |
>
> ห่างกัน 31 นาที — โปรเซสจึงรันโค้ดที่ยังไม่มีฟีเจอร์เสียงมาตลอด 23 ชั่วโมง
>
> ```powershell
> Stop-ScheduledTask -TaskName MardodiCheckinAPI
> Start-Sleep -Seconds 3
> Start-ScheduledTask -TaskName MardodiCheckinAPI
> ```
>
> รัน `.\deploy-update.ps1` ก็ได้ผลเหมือนกัน (ข้างในก็ restart แบบนี้)
> และได้อัปเดตหน้าเว็บ React กับ `web.config` ไปด้วย
>
> ### ⚠️ ไม่ใช่ Docker — อย่าไปไล่ผิดที่
>
> เครื่องนี้มีคอนเทนเนอร์รันอยู่จริง แต่**คนละชุดกับ production**:
>
> | | พอร์ต | ใครใช้ |
> |---|---|---|
> | scheduled task `MardodiCheckinAPI` (venv) | `127.0.0.1:8001` | **IIS ส่ง traffic มาที่นี่** |
> | คอนเทนเนอร์ `checkin-backend` | `127.0.0.1:8010` | ไม่มีใครส่ง traffic ไป |
> | คอนเทนเนอร์ `checkin-db` | `127.0.0.1:5433` | postgres แยกต่างหาก |
>
> `docker-compose.yml` บรรทัด 5 เขียนกำกับไว้เองว่าจงใจเลี่ยงพอร์ต 5432/8000/8001
> ที่ถูกใช้อยู่แล้ว — Docker เป็นสภาพแวดล้อมทดสอบที่แยกจาก production ตั้งแต่ต้น
>
> ### 🐛 บั๊กใน `deploy-update.ps1` ที่แก้ไปแล้ว (2 ก.ย. 2026)
>
> uvicorn แตกเป็น python 2 ตัว พ่อ-ลูก และ **ตัวลูกคือตัวที่ยึดพอร์ต 8001**
> แต่ `Get-Process` รายงาน `.Path` ของสองตัวไม่เหมือนกัน:
>
> ```
> ตัวพ่อ  .Path = F:\...\backend\venv\Scripts\python.exe      <- ของเดิมจับได้
> ตัวลูก  .Path = C:\Users\...\Python314\python.exe           <- ของเดิมจับไม่ได้
> ```
>
> ตาข่ายกันพลาดเดิมกรองด้วย `$_.Path -like "$root\backend*"` จึงฆ่าแต่ตัวพ่อ
> ปล่อยตัวลูกที่ถือพอร์ตไว้รอด **โค้ดเก่าเลยเสิร์ฟต่อทั้งที่ deploy ขึ้นว่าสำเร็จ**
> ตอนนี้เปลี่ยนไปกรองด้วย `CommandLine` ซึ่งมีพาธ venv อยู่ทั้งพ่อและลูก จับได้ครบ


```powershell
cd F:\GitHub\project_job_part-time\checkin-system\deploy\windows-server
git pull
.\deploy-update.ps1
```

> ต้องเปิด PowerShell แบบ **Run as Administrator**

### สิ่งที่เปลี่ยนในรอบนี้

**แก้รอยรั่วที่ทำให้กล้องช้าลงเรื่อย ๆ (สำคัญที่สุด)**

โค้ดเดิมสั่งปิด ffmpeg ด้วย `terminate()` ซึ่งฆ่าได้แค่ตัวนำ (shim ของ chocolatey)
ส่วน ffmpeg ตัวจริงที่เป็นลูกของมันรอด แล้วเปิด RTSP ค้างไว้กับกล้องตลอดไป
วัดจากเครื่องทดสอบ: กดฟังเสียงไม่กี่ครั้ง เหลือ ffmpeg ค้าง **13 ตัว** ทุกตัวจับกล้องไว้

กล้องรับผู้เชื่อมต่อได้จำกัด พอตัวที่รั่วสะสม กล้องจะช้าลงจน **ภาพนิ่งกับคำสั่งหมุนพลอยหลุดไปด้วย**
— ไม่ใช่แค่เรื่องเสียงอย่างเดียว

ตอนนี้เปลี่ยนไปฆ่าทั้งต้นไม้ของ process (`taskkill /T /F` บน Windows)

**เสียงใช้ ffmpeg ตัวเดียวร่วมกันทุกคน**

เดิม 1 คำขอ = 1 ffmpeg = 1 RTSP กับกล้อง หัวหน้า 2 คนเปิดฟังพร้อมกันก็กินโควตากล้อง 2 ที่
ตอนนี้มี ffmpeg ได้ทีละตัวไม่ว่าจะมีคนฟังกี่คน (ทดสอบแล้ว: ผู้ฟัง 3 คน ได้เสียงครบทุกคนจากสตรีมเดียว)

**เพดานอายุของสตรีมเสียง**

ตัวเล่นเสียงบน Android ไม่ยอมปิดสายเมื่อผู้ใช้กดหยุด — วัดได้ว่าสายยังค้างอยู่ **77 วินาที**
หลังกดหยุดไปแล้ว (สาเหตุ: just_audio ตั้งพร็อกซีในเครื่องเพื่อแนบ header ให้ ExoPlayer
สั่งหยุดแล้วพร็อกซีตัวนั้นยังคาสายไว้) เซิร์ฟเวอร์จึงไม่มีทางรู้ว่าเลิกฟังแล้ว

แก้ด้วยการตั้งเพดานอายุ ครบเวลาแล้วสตรีมจบเอง แอปขึ้นว่า "สตรีมเสียงจบลง — กดฟังใหม่ได้"
ค่าเริ่มต้น **10 นาที** ปรับได้ใน `.env`:

```ini
CAMERA_AUDIO_MAX_SECONDS=600
```

**บอกได้แล้วว่ากล้องพูดกลับได้ไหม โดยไม่ต้องเดา**

เดิมโค้ดเขียนตายตัวว่า `talkback_supported = false` ตอนนี้เซิร์ฟเวอร์ไปถามกล้องจริง
(RTSP DESCRIBE + Require backchannel) แล้วจำผลไว้ 5 นาที
เปลี่ยนกล้องหรืออัปเฟิร์มแวร์เมื่อไร ปุ่มจะโผล่เองโดยไม่ต้องแก้โค้ด

**ตัวตั้งค่าใหม่ (ไม่ใส่ก็ได้ มีค่าเริ่มต้นให้แล้ว)**

```ini
CAMERA_AUDIO_MAX_SECONDS=600              # เพดานอายุสตรีมเสียง (วินาที)
CAMERA_BACKCHANNEL_TIMEOUT_SECONDS=3.0    # เวลารอตอนถามกล้องเรื่องพูดกลับ
CAMERA_SNAPSHOT_CACHE_MS=700              # ภาพที่เพิ่งดึงใช้ซ้ำได้กี่มิลลิวินาที
CAMERA_SNAPSHOT_TIMEOUT_SECONDS=6.0       # เพดานเวลาดึงภาพจากกล้อง
CAMERA_SNAPSHOT_STALE_MS=8000             # ภาพเก่าสุดที่ยังยอมส่งให้ตอนกล้องสะดุด
CAMERA_RECONNECT_AFTER_FAILURES=3         # พลาดกี่ครั้งติดถึงจะต่อกล้องใหม่
```

### ตรวจว่าขึ้นเรียบร้อย

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\backend
venv\Scripts\python.exe camera_cache_check.py
venv\Scripts\python.exe camera_audio_check.py
```

ทั้งสองตัวต้องขึ้น **"ผ่านครบ"** (6 ข้อ และ 10 ข้อ ตามลำดับ)
ไม่ต้องมีกล้องหรือ ffmpeg ก็รันได้ ใช้ตรวจตรรกะล้วน ๆ

---

## งานที่ 2: เก็บกวาด ffmpeg ที่ค้างอยู่

เครื่อง production รันโค้ดเดิมมานาน จึงน่าจะมี ffmpeg ค้างสะสมอยู่แล้ว
ทุกตัวจับ RTSP ของกล้องไว้ ทำให้กล้องช้าโดยไม่มีใครรู้สาเหตุ

**นับก่อนว่ามีกี่ตัว:**

```powershell
(Get-Process ffmpeg -ErrorAction SilentlyContinue | Measure-Object).Count
```

| ผลที่ได้ | แปลว่า |
|---|---|
| `0` | ปกติดี (หรือยังไม่มีใครกดฟังเสียงเลย) |
| `1-2` | ปกติ ถ้ามีคนกำลังฟังเสียงอยู่จริง |
| `3` ขึ้นไป | มีตัวค้างสะสม — ต้องเก็บกวาด |

> **ผลตรวจเมื่อ 2 ก.ย. 2026: ได้ `0`** — ไม่มีตัวค้าง ไม่ต้องเก็บกวาดรอบนี้
> (backend เพิ่งถูก restart ไปตอนแก้ routing และยังไม่มีใครกดฟังเสียงหลังจากนั้น)
> ยังต้องเช็คซ้ำหลังเปิดใช้งานจริงไปสัก 1-2 วันตามที่เขียนไว้ข้างล่าง

**เก็บกวาด** (ทำตอนไม่มีใครฟังเสียงอยู่):

```powershell
Get-Process ffmpeg -ErrorAction SilentlyContinue | Stop-Process -Force
```

> ไม่กระทบภาพนิ่งกับคำสั่งหมุนกล้อง เพราะสองอย่างนั้นไม่ได้ใช้ ffmpeg
> หลังจากขึ้นโค้ดใหม่แล้ว ปัญหานี้จะไม่กลับมาอีก แต่ตัวที่ค้างจากของเดิม
> ต้องเก็บด้วยมือครั้งเดียว

**เช็คซ้ำในอีก 1-2 วัน** ว่ายังเป็น 0-2 อยู่ ถ้ากลับไปสะสมอีกให้แจ้งทีมแอป

---

## งานที่ 3: ตรวจว่า IIS หน่วงสตรีมเสียงหรือเปล่า

**ยังไม่ยืนยัน — ต้องตรวจก่อนว่าจำเป็นต้องแก้ไหม** อย่าเพิ่งแก้ทันที

### เรื่องมันคืออะไร

ARR (ตัวที่ IIS ใช้ส่งต่อคำขอไป backend) มีค่า `minResponseBuffer`
= "สะสมข้อมูลไว้กี่ KB ก่อนจะเริ่มส่งให้ client"

> ⚠️ **แก้ชื่อ attribute เมื่อ 2 ก.ย. 2026** — เอกสารฉบับก่อนเขียนว่า
> `responseBufferThreshold` ซึ่ง **ไม่มีอยู่จริง** ตรวจแล้วไม่พบใน schema ใด ๆ ของ IIS
> (`C:\Windows\System32\inetsrv\config\schema\`) คำสั่งเดิมจะ error ทันทีที่รัน
> ชื่อจริงในหมวด `system.webServer/proxy` มี 3 ตัวที่เกี่ยวกับบัฟเฟอร์:
> `minResponseBuffer`, `responseBufferLimit`, `bufferChunkedResponses`
> และหน่วยเป็น **KB ไม่ใช่ไบต์**

สำหรับหน้าเว็บทั่วไปไม่มีปัญหา เพราะ response จบในตัวและสั้น
แต่เสียงเป็น **สตรีมที่ไม่มีวันจบ** ถ้า ARR รอให้ครบตามค่านั้นก่อนถึงจะปล่อย
แอปจะไม่ได้ยินอะไรเลยจนกว่าบัฟเฟอร์จะเต็ม

วัดอัตราเสียงจริงจากกล้องตัวนี้ได้ **~4.8 KB ต่อวินาที** (ที่ 32 kbit/s) ดังนั้น:

| ค่า `minResponseBuffer` | กว่าเสียงจะเริ่มดัง |
|---|---|
| `0` (ปิดการสะสม) | ทันทีที่กล้องส่งมา (~7-9 วินาที) |
| `256` (256 KB — **ค่า default**) | **~53 วินาที** — แอปยอมรอแค่ 25 วินาที จะขึ้นว่าต่อเสียงไม่ทัน |
| `4096` (4 MB) | ~14 นาที = ใช้ไม่ได้เลย |

อีกตัวที่ต้องดูคู่กันคือ `bufferChunkedResponses` (default `true`)
FastAPI ส่งสตรีมแบบ chunked ถ้า ARR บัฟเฟอร์ chunked ไว้ก็หน่วงได้เหมือนกัน

### ตรวจค่าปัจจุบัน

```powershell
C:\Windows\System32\inetsrv\appcmd.exe list config -section:system.webServer/proxy
```

**ผลตรวจเมื่อ 2 ก.ย. 2026:**

```xml
<proxy enabled="true" preserveHostHeader="false" reverseRewriteHostInResponseHeaders="false">
  <cache />
</proxy>
```

> `appcmd` แสดงเฉพาะค่าที่ตั้งไว้ชัดเจน **ไม่แสดงค่า default**
> ไม่เห็น `minResponseBuffer` = ยังใช้ค่า default 256 KB = แถวสีแดงในตารางข้างบน
> ค่า default อ้างอิงจาก `C:\Windows\System32\inetsrv\config\schema\arr_schema.xml`

### ถ้าค่าไม่ใช่ 0 ให้แก้เป็น 0

```powershell
C:\Windows\System32\inetsrv\appcmd.exe set config -section:system.webServer/proxy /minResponseBuffer:"0" /responseBufferLimit:"0" /commit:apphost
iisreset /noforce
```

ถ้ายังหน่วงอยู่ ค่อยเพิ่มตัวนี้ (แยกคนละขั้นจะได้รู้ว่าตัวไหนเป็นตัวแก้):

```powershell
C:\Windows\System32\inetsrv\appcmd.exe set config -section:system.webServer/proxy /bufferChunkedResponses:"false" /commit:apphost
iisreset /noforce
```

> ตั้งเป็น 0 = ส่งต่อทันทีไม่ต้องสะสม เป็นค่าที่แนะนำสำหรับ reverse proxy
> ที่ต้องส่งสตรีม (เสียง, SSE, WebSocket) หน้าเว็บกับ API ปกติไม่ได้รับผลกระทบ
>
> ⚠️ ค่านี้เป็น **ระดับเครื่อง** มีผลกับทุกอย่างที่ ARR proxy บนเครื่องนี้
> ตามคอมเมนต์ใน `web.config` เครื่องนี้มีโปรเจ็กต์อื่นใช้พอร์ต 8000 อยู่
> ถ้าโปรเจ็กต์นั้นผ่าน ARR ด้วยให้แจ้งเจ้าของก่อน และ `iisreset` ทำให้เว็บสะดุด
> ไม่กี่วินาที ควรทำนอกเวลาที่พนักงานลงเวลากันเยอะ

**ถ้าต้องย้อนกลับ:**

```powershell
C:\Windows\System32\inetsrv\appcmd.exe set config -section:system.webServer/proxy /minResponseBuffer:"256" /responseBufferLimit:"4096" /bufferChunkedResponses:"true" /commit:apphost
iisreset /noforce
```

### ตรวจว่าหายแล้ว

ต้องใช้ token ของหัวหน้า เพราะ `/camera/audio` เปิดให้เฉพาะหัวหน้า:

```powershell
$login = Invoke-RestMethod -Uri "https://thanakronpart-time.com/auth/login" -Method Post `
  -Body @{ username = "<รหัสพนักงานหัวหน้า>"; password = "<รหัสผ่าน>" }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$req = [System.Net.HttpWebRequest]::Create("https://thanakronpart-time.com/camera/audio")
$req.Headers.Add("Authorization", "Bearer $($login.access_token)")
$req.Timeout = 90000
$stream = $req.GetResponse().GetResponseStream()
$buf = New-Object byte[] 4096
$n = $stream.Read($buf, 0, 4096)
"เสียงก้อนแรกมาถึงที่ $([int]$sw.Elapsed.TotalSeconds) วินาที ($n ไบต์)"
$stream.Close()
```

| ผลที่ได้ | แปลว่า |
|---|---|
| ~7-15 วินาที | **ปกติ** — กล้องใช้เวลาเริ่มส่งเสียงราว 7-9 วินาทีอยู่แล้ว |
| 40 วินาทีขึ้นไป | ARR ยังหน่วงอยู่ — ทำขั้นตอนแก้ค่าข้างบน |

> ทดสอบผ่าน backend ตรง ๆ ในเครื่อง (`http://127.0.0.1:8001/camera/audio`) เทียบด้วยก็ได้
> ถ้าตรงเร็วแต่ผ่านโดเมนช้า แปลว่าเป็นที่ IIS แน่นอน

**หลังแก้แล้วอย่าลืมทดสอบจากแอปจริง** — เปิดแท็บกล้อง กด "ฟังเสียงจากกล้อง"
ต้องได้ยินเสียงภายในราว 10 วินาที

---

## งานที่ 4: เรื่องปุ่มกดพูด (iCam365)

**สถานะใหม่: backend สำหรับ TiRTC SDK ทางการทำเสร็จแล้ว** เหลือ credential,
การตั้งค่า production และงาน Flutter ตาม
[`../../flutter_boss_app/TIRTC_TALKBACK_TASKS.md`](../../flutter_boss_app/TIRTC_TALKBACK_TASKS.md)

### 4.1 ขอสิทธิ์จาก Tange

ใช้ข้อความที่เตรียมไว้ใน
[`../camera/TANGE_TIRTC_ACCESS_REQUEST.md`](../camera/TANGE_TIRTC_ACCESS_REQUEST.md)
ประเด็นสำคัญคือต้องให้ Tange ยืนยันว่ากล้อง iCam365 retail ตัวเดิมสามารถถูก
authorize เข้า developer application ของเราได้

### 4.2 ตั้งค่า production หลังได้ credential

ใส่ใน `backend/.env` บนเซิร์ฟเวอร์ (ห้าม commit):

```ini
CAMERA_TIRTC_ENABLED=true
CAMERA_TIRTC_APP_ID=<AppId>
CAMERA_TIRTC_ACCESS_KEY_ID=<AccessKeyId>
CAMERA_TIRTC_SECRET_KEY_ID=<SecretKeyId>
CAMERA_TIRTC_REMOTE_ID=<device_id-or-remote_id>
CAMERA_TIRTC_TOKEN_TTL_SECONDS=120
CAMERA_TIRTC_STREAM_ID=14
```

จากนั้น deploy/restart backend แล้วตรวจ `/openapi.json` ว่ามี:

```text
POST /camera/talkback/token
```

ล็อกอินบัญชีหัวหน้าแล้วเรียก `GET /camera/status` ต้องได้:

```json
{
  "talkback_ready": true,
  "talkback_transport": "tirtc",
  "talkback_token_path": "/camera/talkback/token",
  "talkback_stream_id": 14
}
```

ถ้ายังเป็น `false` ให้อ่าน `talkback_note`; ระบบจะบอกชื่อ env ที่ขาดโดยไม่
เปิดเผยค่า secret

### 4.3 ขอบเขตความปลอดภัย

- `SecretKeyId` อยู่ backend เท่านั้น ไม่ส่งให้ Flutter
- endpoint จำกัดเฉพาะ `require_manager`
- client เลือก `remote_id` เองไม่ได้ กล้องถูกตรึงจาก `.env`
- token มีอายุ 30–300 วินาที, nonce ใหม่ทุกครั้ง และ response ห้าม cache
- เสียงวิ่ง Flutter → TiRTC encrypted P2P/Cloud → กล้อง ไม่วิ่งผ่าน Python

ผลตรวจ RTSP/ONVIF เดิมและทาง packet-capture fallback เก็บไว้ใน
[`../camera/ICAM365_TALKBACK.md`](../camera/ICAM365_TALKBACK.md)

---

## ตรวจสุดท้ายว่าทุกอย่างเรียบร้อย

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\deploy\windows-server
.\deploy-update.ps1 -CheckOnly
```

แล้วเปิดแอปหัวหน้า ไปแท็บ "กล้องวงจรปิด" ต้องได้ครบ 3 อย่าง:

- [ ] เห็นภาพสด มีป้าย **LIVE** สีแดง (ไม่ใช่ "ภาพค้าง" สีส้ม)
- [ ] ปุ่มทิศทางกดแล้วกล้องหมุนจริง
- [ ] กด **"ฟังเสียงจากกล้อง"** แล้วได้ยินเสียงภายในราว 10 วินาที

ถ้าข้อ 3 ขึ้นว่า **"ต่อเสียงไม่ทัน — กล้องไม่ส่งเสียงมา"** ให้กลับไปทำ
[งานที่ 3](#งานที่-3-ตรวจว่า-iis-หน่วงสตรีมเสียงหรือเปล่า)

ถ้าปุ่มฟังเสียงไม่ขึ้นเลย แต่มีข้อความว่าเซิร์ฟเวอร์ยังส่งเสียงไม่ได้ ให้เช็ค ffmpeg:

```powershell
where.exe ffmpeg
```

ไม่เจอ = ยังไม่ได้ติดตั้ง ให้ลงด้วย `choco install ffmpeg -y`
(ลงแล้วไม่ต้อง restart backend — ระบบเช็คใหม่ทุกครั้งที่แอปถามสถานะ)

---

## เอกสารที่เกี่ยวข้อง

| ไฟล์ | เรื่อง |
|---|---|
| [`FIX_CAMERA_ROUTING.md`](FIX_CAMERA_ROUTING.md) | IIS ไม่ส่งต่อ `/camera/*` (แก้ไปแล้ว) + Location header หลุดที่อยู่ภายใน |
| [`../camera/CAMERA_SETUP.md`](../camera/CAMERA_SETUP.md) | ติดตั้งระบบกล้องครั้งแรก |
| [`../camera/ICAM365_TALKBACK.md`](../camera/ICAM365_TALKBACK.md) | สถาปัตยกรรม TiRTC และผลตรวจกล้องเดิม |
| [`../camera/TANGE_TIRTC_ACCESS_REQUEST.md`](../camera/TANGE_TIRTC_ACCESS_REQUEST.md) | อีเมลขอ credential/authorize กล้องตัวปัจจุบัน |
| [`../../flutter_boss_app/TIRTC_TALKBACK_TASKS.md`](../../flutter_boss_app/TIRTC_TALKBACK_TASKS.md) | งาน Flutter กดค้างเพื่อพูด |
| [`../../flutter_boss_app/ISSUE_CAMERA_AUDIO.md`](../../flutter_boss_app/ISSUE_CAMERA_AUDIO.md) | รายงานปัญหาปุ่มฟังเสียงไม่ขึ้น (ฝั่งแอปแก้แล้ว) |
