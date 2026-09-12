# ส่งต่อฝั่งเซิร์ฟเวอร์: deploy ระบบยืนยันตัวตนประจำวัน (home verification)

> **วันที่:** 12 กันยายน 2026
> **ถึง:** ผู้ดูแลเครื่อง production
> **ที่มา:** `LOGIN_STATUS_HANDOFF_2026-09-12.md` — ผู้ใช้แจ้งว่าแอปขึ้น "ยังตรวจสอบผลการยืนยันไม่ได้"
> **สถานะล่าสุด:** ✅ deploy backend + IIS แล้ว และตรวจ authenticated GET ผ่าน — ⏳ เหลือ APK ใหม่และการทดสอบสแกนบนมือถือ
> **ต้องทำบนเครื่อง production เท่านั้น** (เครื่อง dev ไม่มี IIS / ไม่มี backend รันอยู่)

---

## ผลดำเนินงานจริง — 12 กันยายน 2026 เวลา 14:27 น. (ไทย)

ส่วนนี้เป็นสถานะล่าสุด ส่วนหลักฐานและขั้นตอนด้านล่างเป็นเอกสารส่งต่อก่อน deploy

- นำไฟล์ backend, ชุดทดสอบ และ `web.config` จาก `origin/Film_dev_Part-Time` commit `bd5989c` มาใช้บน `master` ที่ฐานเดิม `71ae02f` โดยเลือกเฉพาะงาน server ไม่ได้ merge ทั้ง branch หรือเปลี่ยน source Flutter
- พบข้อผิดพลาดเพิ่มเติมที่เอกสารเดิมไม่ได้ระบุ: `Settings` ไม่มี `home_verification_challenge_ttl_seconds`, `home_verification_max_photo_bytes`, `home_verification_min_photo_pixels` ทำให้ชุดทดสอบ 29 กรณีเกิด error 20 กรณี (`AttributeError`)
- เพิ่มค่าทั้งสามใน `backend/app/config.py`: default `120`, `8_000_000`, `160` และกำหนดให้มากกว่า 0 สามารถ override ผ่าน environment ได้
- หลังแก้ รัน `python -W ignore::DeprecationWarning -m unittest test_home_verifications test_payroll test_chat test_support -q` ผ่าน **108/108** บน SQLite แยกและปิดการส่ง LINE
- ทดสอบ startup/OpenAPI บน SQLite แยกผ่าน จากนั้นรัน `deploy-update.ps1 -SkipFrontend` บน production สำเร็จ: copy กฎ IIS และ restart `MardodiCheckinAPI`
- สำรองโค้ดเดิมและ IIS config ไว้ที่ `F:\GitHub\deploy-backups\home-verification-20260912` ก่อน deploy (ไม่ได้สำรองฐานข้อมูลในรอบนี้)

### ผลตรวจบน production

| รายการ | ผลจริง |
|---|---|
| `GET /home-verifications/me` ไม่ส่ง token | **401 + application/json** |
| `GET /home-verifications/me` มีสิทธิ์พนักงาน | **200 + JSON** โครงสร้างสถานะรายวันถูกต้อง, `Cache-Control: no-store` |
| `GET /home-verifications/me` มีสิทธิ์หัวหน้า | **200 + JSON** โครงสร้างสถานะรายวันถูกต้อง, `Cache-Control: no-store` |
| `/openapi.json` | **56 paths** รวม home verification ครบ **5 paths** |
| PostgreSQL | มี `home_verifications` และ `home_verification_challenges` ครบ |
| Home geofence | พบสถานที่ประเภทบ้าน 1 แห่ง |
| หน้าเว็บ, `/health`, `/reports/geofence` | **200** |
| ตัวตรวจ proxy ของ deploy script | ผ่านทุก router รวม `home-verifications` |

การตรวจบัญชีจริงใช้ token อายุ 30 วินาทีในหน่วยความจำและ GET เท่านั้น ไม่บันทึก token/ข้อมูลบุคคลลง log ไม่สร้างรายการยืนยันหรือส่ง LINE ใน production การเขียนข้อมูลและการกู้คำขอซ้ำทดสอบด้วยฐานข้อมูลแยก

### สิ่งที่ยังเหลือให้ทีมแอพ

- ยัง **ไม่ได้ publish APK ใหม่**: เครื่องนี้ไม่พบ employee release ที่เอกสารระบุ ส่วน boss release ที่พบเป็นไฟล์เก่า 31 สิงหาคม ขนาด 56,736,191 ไบต์ ไม่ใช่ artifact ใหม่ที่ระบุไว้
- `/app/info` ยังเป็น `1.2.0+3` และ `/boss-app/info` ยังเป็น `1.0.0+1` ไม่ได้เปลี่ยน metadata ให้แสดงรุ่นใหม่โดยไม่มี APK จริง
- ให้ส่ง APK พนักงาน `1.6.1+9` และหัวหน้า `1.3.1+6` ที่ build จาก source ที่ผ่านทดสอบ พร้อม checksum และข้อมูลลายเซ็น แล้วจึงตรวจ artifact/publish
- ยังไม่ได้ทดสอบกล้อง/GPS/การสแกนบนมือถือจริง ผู้ใช้ที่ติดตั้งแอพรุ่นที่เรียก API นี้อยู่แล้วสามารถกด “ลองอีกครั้ง” ได้; หากขึ้นเซสชันหมดอายุให้ login ใหม่
- ขอบเขต verifier ตาม source ที่ส่งมา: ตรวจ challenge, ขนาด/หัวไฟล์รูป, การใช้หลักฐานซ้ำ และ geofence; ไม่ได้ทำ face matching หรือยืนยัน liveness ฝั่ง server จึงไม่ควรอ้างผลทดสอบนี้ว่าเป็นการรับรองความสามารถดังกล่าว

### ผลตรวจผลกระทบ

GitNexus ของ `F:\GitHub\project_job_part-time` อัปเดต index ที่ฐาน `71ae02f` ก่อนแก้: `Settings` มีผลกระทบ **HIGH**, 37 รายการ, 17 direct importers ครอบคลุม database, security, geofence, reports และ router ต่าง ๆ จึงเพิ่มเฉพาะ field ใหม่และตรวจชุดทดสอบที่เกี่ยวข้อง กราฟไม่พบ caller ของ `main.root` (UNKNOWN); ตรวจ source และ Scheduled Task ยืนยันว่าโหลดผ่าน `app.main:app` การเปลี่ยน `main.py` มีเพียง import/include router ใหม่

## ⚡ สรุปปัญหาก่อน deploy

แอปในมือถือเรียก `/home-verifications/*` แต่ **เซิร์ฟเวอร์ยังไม่มี endpoint นั้นเลย** ฟีเจอร์จึงใช้ไม่ได้

ต้องแก้ **2 ชั้น** ถ้าทำแค่ชั้นเดียวจะยังไม่หาย:

| ชั้น | ปัญหา | วิธีแก้ |
|---|---|---|
| 1. backend | router `home_verifications` ยังไม่ได้ deploy | `git pull` + restart backend |
| 2. IIS | `web.config` ไม่มี `home-verifications` ในกฎ proxy | copy `web.config` ตัวใหม่ขึ้น IIS |

**คำสั่งเดียวจบ:** `deploy-update.ps1` ทำให้ทั้ง 2 ชั้น (ดูหัวข้อ 3)

---

## 1. หลักฐานว่าตอนนี้ยังพังอยู่

```text
GET https://thanakronpart-time.com/home-verifications/me
HTTP 200   content-type: text/html        ← ได้หน้า React ไม่ใช่ API
```

IIS ไม่รู้จักเส้นทางนี้ จึงตกไปเข้ากฎ `StaticFiles` แล้วตอบ `index.html` กลับมา **พร้อมรหัส 200**

> ⚠️ **ระวังกับดักนี้** — เช็คแค่รหัสสถานะจะเห็นเป็น "ผ่าน" ทั้งที่ API เส้นนั้นใช้ไม่ได้เลย
> **ต้องดู `content-type` ด้วยเสมอ** ต้องเป็น `application/json` ไม่ใช่ `text/html`

ยืนยันซ้ำจาก OpenAPI ของ backend ที่รันอยู่จริง:

```text
GET https://thanakronpart-time.com/openapi.json
→ 51 endpoints
→ prefixes: addresses, app, auth, boss-app, camera, chat, checkins,
            employee-management, employment-options, faces, health,
            line, locations, payroll, reports, support
→ home-verifications: ไม่มีเลย
```

**นี่คือบั๊กตัวเดียวกับ `/payroll` ที่เคยเกิดเมื่อ 12 ก.ย.** (บันทึกไว้ใน `CLAUDE.md` Work Log) —
เพิ่ม router ใหม่ใน backend แล้วลืมเติมชื่อในกฎ `ProxyToBackend`

---

## 2. สิ่งที่ฝั่งโค้ดทำเสร็จแล้ว (ไม่ต้องทำอะไรเพิ่ม)

| ส่วน | สถานะ |
|---|---|
| `backend/app/routers/home_verifications.py` (5 endpoints) | ✅ อยู่ใน git แล้ว |
| `backend/app/home_verification.py` + `home_verification_models.py` | ✅ อยู่ใน git แล้ว |
| `backend/app/main.py` ลงทะเบียน router | ✅ อยู่ใน git แล้ว |
| `deploy/windows-server/web.config` เติม `home-verifications` | ✅ **แก้แล้วรอบนี้** |
| `backend/test_home_verifications.py` | ✅ 29 tests ผ่าน |
| แอป Flutter ทั้ง 2 ตัว | ✅ `1.6.1+9` / `1.3.1+6` |

**ตารางฐานข้อมูลสร้างเองอัตโนมัติ** ตอน backend สตาร์ต (`Base.metadata.create_all`)
→ **ไม่ต้องรัน migration เอง** และไม่ต้องแตะ `_ADDED_COLUMNS`

ตารางที่จะถูกสร้าง: `home_verifications`, `home_verification_challenges`

---

## 3. ขั้นตอน deploy

เปิด **PowerShell แบบ Run as Administrator** บนเครื่อง production

```powershell
cd <path ที่ clone repo ไว้>\project_job_part-time
git pull

cd checkin-system\deploy\windows-server
.\deploy-update.ps1
```

`deploy-update.ps1` ทำให้ครบทุกอย่าง: build React → copy ขึ้น `C:\inetpub\checkin` →
copy `web.config` → restart backend → **ตรวจว่าทุก router ของ backend อยู่ในกฎ proxy จริง**

> 💡 สคริปต์มีตัวตรวจ router ↔ web.config ในตัวอยู่แล้ว (เขียนไว้หลังเคสของ `/camera/*`)
> ถ้ามันเตือนว่ามี router ที่ไม่อยู่ในกฎ **อย่าข้าม** ให้เติมใน `web.config` ก่อน

ถ้าอยากดูสถานะอย่างเดียวไม่ deploy: `.\deploy-update.ps1 -CheckOnly`

---

## 4. ตรวจว่า deploy สำเร็จจริง

### 4.1 endpoint ต้องเป็น JSON ไม่ใช่ HTML

```powershell
curl.exe -i https://thanakronpart-time.com/home-verifications/me
```

| ผล | แปลว่า |
|---|---|
| ✅ `401` + `content-type: application/json` | **สำเร็จ** (401 ถูกต้อง เพราะยังไม่ได้ส่ง token) |
| ❌ `200` + `content-type: text/html` | web.config ยังไม่ได้ copy ขึ้น IIS |
| ❌ `404` + `application/json` | IIS proxy ถูกแล้ว แต่ backend ยังไม่ได้ restart |

### 4.2 backend มี router ครบ

```powershell
curl.exe -s https://thanakronpart-time.com/openapi.json | Select-String "home-verifications"
```

ต้องเจอ 5 เส้น: `/challenges`, `""`, `/requests/{request_id}`, `/me`, `/employee/{employee_id}`
และจำนวน endpoint รวมควรเพิ่มจาก **51 → 56**

### 4.3 ตารางถูกสร้างแล้ว

```powershell
# ใน venv ของ production
.\venv\Scripts\python.exe -c "from app.database import engine; from sqlalchemy import inspect; print([t for t in inspect(engine).get_table_names() if 'home' in t])"
```

ต้องได้ `['home_verification_challenges', 'home_verifications']`

### 4.4 ทดสอบบนมือถือ

เปิดแอปพนักงานตอนอยู่ในเขตบ้าน → การ์ดต้องเปลี่ยนจาก
**"ฟีเจอร์นี้ยังไม่พร้อมใช้งาน"** → **"วันนี้ยังไม่ได้ยืนยันตัวตน"** พร้อมปุ่มสแกน

---

## 5. ⚠️ เรื่องที่ต้องระวัง

### 5.1 ห้ามลืม web.config

`web.config` **ไม่ได้ถูก copy อัตโนมัติจาก git** — มันอยู่ใน repo แต่ IIS อ่านจาก `C:\inetpub\checkin\web.config`
`deploy-update.ps1` copy ให้ แต่ถ้า deploy ด้วยมือต้อง copy เอง ไม่งั้น endpoint จะ 404 ทั้งที่ backend มีแล้ว

กฎที่ถูกต้องต้องมี `home-verifications` อยู่ด้วย:

```xml
<match url="^(app|boss-app|addresses|auth|camera|chat|checkins|employee-management|employment-options|faces|home-verifications|line|locations|payroll|reports|support|health|docs|redoc|openapi\.json)(/.*)?$" />
```

### 5.2 ไม่ต้อง reboot และไม่ต้องแตะ WebSocket

ฟีเจอร์นี้ใช้ **REST + multipart ธรรมดา** ไม่ใช้ WebSocket
จึงไม่เกี่ยวกับเรื่อง `IIS-WebSockets` ที่ยังค้าง `InstallPending` อยู่ และไม่ต้องแตะ cloudflared

### 5.3 ไม่ต้องเพิ่ม dependency ใด ๆ

verifier เขียนให้อ่านหัวไฟล์ JPEG/PNG เอง **จงใจไม่ใช้ Pillow/OpenCV**
เพราะทั้งคู่ไม่ได้ประกาศใน `requirements-base.txt` ถ้า import แล้วเครื่องไม่มี **backend จะไม่สตาร์ตทั้งระบบ**
→ `pip install -r requirements.txt` ไม่จำเป็นสำหรับงานนี้ (แต่ทำก็ไม่เสียหาย)

### 5.4 ค่า .env ที่เพิ่มได้ (ไม่ใส่ก็ทำงาน มีค่า default ครบ)

```env
HOME_VERIFICATION_CHALLENGE_TTL_SECONDS=120    # อายุโจทย์ กันส่งหลักฐานเก่า
HOME_VERIFICATION_MAX_PHOTO_BYTES=8000000      # เพดานไฟล์หลักฐาน
HOME_VERIFICATION_MIN_PHOTO_PIXELS=160         # ด้านสั้นที่สุดของภาพ
```

> ⚠️ `HOME_VERIFICATION_CHALLENGE_TTL_SECONDS` **ไม่ใช่เส้นตายว่าพนักงานต้องยืนยันก่อนกี่โมง**
> อยู่บ้านไม่มีสถานะสาย ค่านี้มีไว้กันการนำรูปเก่ามาส่งซ้ำเท่านั้น

### 5.5 ต้องมีพิกัดบ้านใน OFFICES

ตรวจแล้วว่า production มีอยู่ถูกต้อง — ถ้าถูกลบไป ฟีเจอร์จะปฏิเสธทุกคำขอด้วย `outside_home`

```json
{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2,"allow_checkout":false,"category":"home"}
```

---

## 6. publish APK ใหม่ (ทำหลัง deploy สำเร็จแล้ว)

ตอนนี้เว็บยังแจก APK เก่ามาก: `/app/info` = `1.2.0+3` · `/boss-app/info` = `1.0.0+1`

```powershell
cd checkin-system
.\deploy\windows-server\publish-apk.ps1 -ApkPath '<employee-release.apk>' -Version '1.6.1+9' -MinSdk 24
.\deploy\windows-server\publish-apk.ps1 -Boss -ApkPath '<boss-release.apk>' -Version '1.3.1+6' -MinSdk 24
```

ไฟล์ต้นทางอยู่บนเครื่อง dev:

```text
checkin-system\flutter_app\build\app\outputs\flutter-apk\app-release.apk        80.3 MB  1.6.1+9
checkin-system\flutter_boss_app\build\app\outputs\flutter-apk\app-release.apk  101.0 MB  1.3.1+6
```

ตรวจหลัง publish (ต้องเห็นเวอร์ชันเปลี่ยนบน**โดเมนจริง** ไม่ใช่ localhost):

```powershell
curl.exe -s https://thanakronpart-time.com/app/info
curl.exe -s https://thanakronpart-time.com/boss-app/info
```

> ⚠️ ติดตั้งทับ = **ผู้ใช้ถูก logout** ต้องแจ้งให้ล็อกอินใหม่
> ลายเซ็นเป็น debug keystore `41C0464D…9625E269` ตรงกับของเดิม ติดตั้งทับได้ไม่ต้องถอน

---

## 7. ถ้า deploy แล้วยังไม่หาย — ไล่ตามนี้

| อาการในแอป | สาเหตุที่น่าจะเป็น | ตรวจยังไง |
|---|---|---|
| "ฟีเจอร์นี้ยังไม่พร้อมใช้งาน" | web.config ยังไม่ขึ้น IIS หรือ backend ยังไม่ restart | `curl.exe -i .../home-verifications/me` ดู content-type |
| "เซสชันหมดอายุ" | token หมดอายุจริง | ล็อกอินใหม่ในแอป |
| "ยังตรวจสอบผลการยืนยันไม่ได้" | เน็ต/timeout จริง ๆ | ลองจากเครือข่ายอื่น |
| กดยืนยันแล้วได้ `outside_home` | อยู่นอกรัศมีบ้าน 0.2 กม. หรือ `OFFICES` ไม่มี `category=home` | `curl.exe -s .../reports/geofence` |
| กดยืนยันแล้วได้ `face_not_enrolled` | บัญชีนั้นยังไม่มีใบหน้าอ้างอิง | ให้ลงทะเบียนใบหน้าในแอปก่อน |

**เก็บ log อย่างไร:** ดู log ของ backend ในช่วงเวลาที่กด แล้วแยกให้ได้ว่าเป็น 401/404/422/5xx/timeout
**ห้ามบันทึก token, รหัสผ่าน, ภาพใบหน้า หรือ `evidence_sha256` ลง log**

---

## 8. สรุปเช็คลิสต์

- [x] นำไฟล์ server จาก `origin/Film_dev_Part-Time` (`bd5989c`) มาบน production และเติม Settings ที่ขาด
- [x] รัน `deploy-update.ps1 -SkipFrontend` (สิทธิ์ Administrator)
- [x] `curl.exe -i .../home-verifications/me` → **401 + application/json**
- [x] `/openapi.json` มี `home-verifications` ครบ 5 เส้น (รวม 56 paths)
- [x] ตาราง `home_verifications` + `home_verification_challenges` ถูกสร้าง
- [ ] publish APK `1.6.1+9` และ `1.3.1+6` แล้วตรวจ `/app/info` + `/boss-app/info`
- [ ] แจ้งผู้ใช้ให้โหลดตัวใหม่ **และล็อกอินใหม่**
- [ ] ทดสอบจริงบนมือถือตอนอยู่บ้าน → การ์ดขึ้น "วันนี้ยังไม่ได้ยืนยันตัวตน"
- [x] อัปเดต `LOGIN_STATUS_HANDOFF_2026-09-12.md` และ `CLAUDE.md` ว่า deploy แล้ว พร้อมข้อจำกัด

---

## 9. เอกสารที่เกี่ยวข้อง

| ไฟล์ | ใช้ดูอะไร |
|---|---|
| `LOGIN_STATUS_HANDOFF_2026-09-12.md` | รายงานปัญหาต้นทาง + ผลวินิจฉัยเต็ม |
| `DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` | ข้อกำหนดฟีเจอร์ · หัวข้อ 16 = backend · หัวข้อ 17 = แอป |
| `backend/app/routers/home_verifications.py` | ความจริงของสัญญา API (ถ้าเอกสารขัดกับโค้ด ให้เชื่อโค้ด) |
| `backend/test_home_verifications.py` | 29 กรณีที่ backend รับประกันไว้ |
| `CLAUDE.md` Work Log | ประวัติการแก้ทั้งหมด รวมเคส `/payroll` ที่เป็นบั๊กแบบเดียวกัน |
