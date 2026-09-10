# สรุปงาน: ไมค์พูดออกลำโพงกล้อง + สถานะ deploy

**วันที่:** 6 ก.ย. 2026
**ขอบเขต:** แอปหัวหน้า (`flutter_boss_app`) v1.2.0+4, backend, และเรื่องกล้องไม่มีภาพ

---

## สรุป 30 วินาที

1. **ฟีเจอร์ไมค์เขียนเสร็จและทดสอบบนเครื่องจริงแล้ว** ทุกขั้นทำงาน ยกเว้นขั้นสุดท้าย
   ที่ต้องใช้ credential จริงจาก Tange
2. **ใช่ ต้องเอาขึ้นตัวจริงก่อน** และมี **3 อย่าง** ที่ต้อง deploy ไม่ใช่แค่ APK
3. **กล้องไม่มีภาพเพราะมือถือถูกชี้มาที่ backend ทดสอบบนเครื่องพัฒนา** (อยู่บ้านเพื่อน
   เอื้อมไปหากล้องที่บ้านไม่ถึง) ไม่ใช่กล้องเสียและไม่ใช่บั๊ก — ล็อกอินใหม่ก็ควรกลับมาปกติ
4. **Tailscale: production ไม่ต้องใช้** เพราะเซิร์ฟเวอร์อยู่วงเดียวกับกล้องที่บ้านอยู่แล้ว

---

## 1. ทำไมกล้องไม่มีภาพ

> **แก้คำวินิจฉัยเดิม (6 ก.ย. เย็น)** — ตอนแรกผมสรุปว่า "กล้องหลุดจากวงแลน"
> **ผิดครับ** ผมสแกน `192.168.1.0/24` ของ**บ้านเพื่อน** ที่เครื่องพัฒนาต่ออยู่
> ไม่ใช่วงแลนที่บ้านซึ่งกล้องกับเซิร์ฟเวอร์อยู่ — สองที่ใช้เลข `192.168.1.x`
> เหมือนกันพอดี ผลสแกนเลยดูเหมือนกล้องหาย ทั้งที่กล้องอยู่ที่บ้านตามปกติ
> อุปกรณ์ `.34` / `.35` ที่เจอเปิด RTSP คือกล้องของบ้านเพื่อน ไม่เกี่ยวกับระบบเรา

### สภาพจริง

| ที่ | มีอะไร | วงแลน |
|---|---|---|
| **บ้าน** | เซิร์ฟเวอร์ production (`WIN-QRB8CPGC62I`) + กล้อง `192.168.1.101` | `192.168.1.0/24` |
| **บ้านเพื่อน** | เครื่องพัฒนา (`X6IWR1OD`, `192.168.1.48`) | `192.168.1.0/24` (เลขชนกัน) |

**เซิร์ฟเวอร์กับกล้องอยู่วงเดียวกันที่บ้าน** จึงคุยกันได้ตามปกติ ไม่ต้องพึ่ง Tailscale

### แล้วทำไมตอนทดสอบถึงไม่มีภาพ

เพราะตอนนั้นมือถือถูกชี้มาที่ **backend ที่ผมรันบนเครื่องพัฒนา** (ผ่านสาย USB / `adb reverse`)
ซึ่งอยู่บ้านเพื่อน เอื้อมไปหากล้องที่บ้านไม่ถึง จึงขึ้น `URL error: timed out`

**ไม่ใช่บั๊ก และไม่ใช่กล้องเสีย** — เป็นผลข้างเคียงของสภาพแวดล้อมทดสอบ

ตอนนี้มือถือติดตั้งตัว production (ชี้ `thanakronpart-time.com`) กลับไปแล้ว
**ล็อกอินใหม่แล้วภาพกล้องควรกลับมาปกติ** ถ้ายังไม่มา ค่อยไปดูที่ตัวกล้องที่บ้าน

---

## 2. Tailscale ทำวงแลนถึงกันได้ไหม

**ได้ แต่ production ไม่ต้องใช้** เพราะเซิร์ฟเวอร์อยู่วงเดียวกับกล้องอยู่แล้ว
ใส่เข้าไปมีแต่เพิ่มความซับซ้อน

Tailscale จะคุ้มเมื่ออยากให้ **เครื่องพัฒนาที่อยู่นอกบ้าน เรียกกล้องที่บ้านได้**
(เช่นนั่งทำงานที่บ้านเพื่อนแล้วอยากทดสอบกับกล้องจริง)

### สถานะ tailnet ตอนนี้

| เครื่อง | Tailscale IP | สถานะ |
|---|---|---|
| `X6IWR1OD` (เครื่องพัฒนา, บ้านเพื่อน) | 100.66.123.60 | ออนไลน์ |
| `WIN-QRB8CPGC62I` (เซิร์ฟเวอร์, บ้าน) | 100.92.152.56 | ออนไลน์ |

ทดสอบแล้ว `tailscale ping` ทะลุถึงกันแบบ direct **13 ms** — เส้นทางดีมาก
ยังไม่มีใคร advertise route (`AdvertiseRoutes: None`) และเครื่องพัฒนาตั้ง `RouteAll: True` ไว้แล้ว

### กับดักที่ต้องรู้ก่อนทำ: เลขวงแลนชนกัน

ทั้งบ้านและบ้านเพื่อนใช้ `192.168.1.0/24` เหมือนกัน ถ้า advertise วงนี้ตรง ๆ
**จะใช้ไม่ได้** เพราะเครื่องพัฒนามีเส้นทางตรงไปวง `192.168.1.0/24` ของบ้านเพื่อนอยู่แล้ว
เส้นทางตรงชนะเสมอ — เรียก `192.168.1.101` ก็จะวิ่งไปหากล้องบ้านเพื่อนแทน

**ดูวิธีแก้ทั้ง 3 ทางพร้อมคำสั่งเต็มได้ที่หัวข้อ "คำสั่ง Tailscale" ด้านล่าง**

---

## 3. ต้อง deploy อะไรบ้าง (ตอบ "ต้องเอาขึ้นตัวจริงก่อนใช่ไหม")

**ใช่ครับ และมี 3 อย่าง ไม่ใช่แค่ APK**

| # | ของ | สถานะบน production ตอนนี้ | ทำไมต้องขึ้น |
|---|---|---|---|
| 1 | **APK แอปหัวหน้า** | `1.0.0+1` (build 30 ส.ค.) | ตัวใหม่คือ `1.2.0+4` มีทั้งโลโก้ใหม่และปุ่มไมค์ |
| 2 | **โค้ด backend** | เวอร์ชันเก่า **ยังไม่มีโค้ด TiRTC** | ไม่มี endpoint `/camera/talkback/token` แอปจึงพูดไม่ได้ |
| 3 | **credential ของ Tange ใน `.env`** | ยังไม่มี | ขาดอันนี้ ปุ่มพูดจะไม่โผล่เลย |

### หลักฐานว่า backend บน production ยังเก่า

ยิง `/camera/status` จากเครื่องจริงได้ note กลับมาว่า:

```
กล้องไม่มีช่องเสียงขาเข้าใน SDP (ไม่พบ a=sendonly)
```

ถ้าเป็นโค้ดใหม่ ข้อความจะมี prefix ของ TiRTC นำหน้าเสมอ เช่น:

```
ยังไม่ได้เปิด TiRTC ที่เซิร์ฟเวอร์ (CAMERA_TIRTC_ENABLED); กล้องไม่มีช่องเสียงขาเข้าใน SDP...
```

ไม่มี prefix = ยังรัน `camera.py` ตัวเก่าอยู่

### ลำดับที่ควรทำ

```
1. ขอ credential จาก Tange (business@tange.ai)   <- ตัวบล็อกที่นานสุด เริ่มก่อนได้เลย ไม่ต้องรอข้ออื่น
2. commit + push โค้ดจากเครื่องพัฒนา
3. ที่บ้าน: git pull -> deploy backend ตัวใหม่
4. ใส่ CAMERA_TIRTC_* ใน backend\.env แล้ว restart
5. ส่งไฟล์ APK 1.2.0+4 ไปเครื่องที่บ้าน -> publish
6. ส่งลิงก์ให้หัวหน้าโหลด (แอปไม่มีระบบเตือนอัปเดตในตัว)
```

> **สำคัญ:** คำสั่ง `publish-apk.ps1 -Boss` ที่ผมรันไป **เขียนลงเครื่องนี้เท่านั้น**
> (`C:\project_job_part-time\checkin-system\backend\storage\boss-app\`)
> ไม่ได้ขึ้น production เพราะ production เป็นคนละเครื่อง (`C:\apps\checkin-system`)
> ตอนนี้ `https://thanakronpart-time.com/boss-app/info` จึงยังตอบ `1.0.0+1` อยู่

### ที่ต้องขอจาก Tange

ส่งเมลไป `business@tange.ai` ขอ:

- `AppId`
- `AccessKeyId`
- `SecretKeyId`
- `device_id` / `remote_id` ของกล้องตัวที่ใช้อยู่
- **ยืนยันว่ากล้อง iCam365 ตัวปัจจุบันถูก authorize ให้เชื่อมจาก TiRTC client SDK ของเราได้**
  (ไม่ใช่ credential ของ test device คนละตัว)

`SecretKeyId` ใส่ได้เฉพาะ `backend\.env` **ห้ามใส่ในแอปหรือ commit ลง git**

---

## 4. ฟีเจอร์ไมค์ — ทำอะไรไปแล้ว

### ไฟล์ที่แก้/เพิ่ม

| ส่วน | ไฟล์ |
|---|---|
| SDK | `tirtc_flutter: 2.3.1` ใน `pubspec.yaml` |
| Maven ของ Tange | `android/build.gradle.kts` (ล็อก `includeGroup("com.tange.ai")` ไม่ให้ dependency อื่นวิ่งผ่าน http) |
| สิทธิ์ไมค์ | `RECORD_AUDIO` ใน `AndroidManifest.xml` |
| Model + API | `lib/models/camera.dart`, `lib/services/api_service.dart` |
| Service ครอบ SDK | `lib/services/camera_talkback_service.dart` **(ใหม่)** |
| ปุ่มกดค้าง | `lib/screens/tabs/camera_tab.dart` |
| เทสต์ | `test/camera_talkback_test.dart` **(ใหม่)**, `test/camera_tab_test.dart`, `test/support/` **(ใหม่)** |

**107 เทสต์ผ่านหมด** (เพิ่มใหม่ 29 ข้อ) · `flutter analyze` ไม่มี issue

### บั๊กที่เจอตอนทดสอบบนเครื่องจริง (แก้แล้ว)

ปุ่ม "กดค้างเพื่อพูด" **ไม่โผล่** ทั้งที่เซิร์ฟเวอร์บอกว่าพร้อม เพราะตอนแรกวางปุ่มไว้
ใต้เงื่อนไขเดียวกับปุ่ม "ฟังเสียงจากกล้อง" แต่สองอย่างนี้คนละเส้นทางกัน:

- **ฟังเสียง** — เซิร์ฟเวอร์ต้องมี `ffmpeg` แปลงสตรีมจากกล้องมาให้
- **พูดออกกล้อง** — มือถือยิงตรงไปกล้องผ่าน TiRTC ไม่ผ่าน ffmpeg เลย

เซิร์ฟเวอร์ที่ไม่มี ffmpeg แต่ตั้ง TiRTC ครบ จึงพูดไม่ได้ทั้งที่ควรได้
แยกเป็นสองส่วนอิสระกันแล้ว + เพิ่มเทสต์คุมไว้

> เทสต์เดิม 28 ข้อจับไม่ได้ เพราะตั้ง `audio_supported = true` ทุกข้อ

### ผลทดสอบบนเครื่องจริง (MTN NX1, Android 16)

รัน backend ในเครื่อง เปิด TiRTC ด้วย**ค่าปลอม** แล้วต่อผ่านสาย USB (`adb reverse`)

| ขั้น | ผล |
|---|---|
| ปุ่มโผล่เมื่อ `talkback_ready=true` | ผ่าน (หลังแก้บั๊ก) |
| ขอสิทธิ์ไมค์ตอนกดครั้งแรกเท่านั้น | ผ่าน — prompt ขึ้นตอนกด ไม่ใช่ตอนเปิดแอป |
| ขอ token จาก `/camera/talkback/token` | ผ่าน (`POST → 200`) |
| `TiRtc.initialize` | ผ่าน (`code=0`, native lib โหลดได้) |
| SDK ต่อเซิร์ฟเวอร์ Tange | ผ่าน — resolve `ep-tirtc.tange365.com` แล้วยิง `/v1/connect` |
| Tange ตอบกลับ | `40402 access credential not found` |
| แอปแสดง error ภาษาไทย | ผ่าน — กลับมากดใหม่ได้ ไม่ค้าง |
| token/credential รั่วลง log | ไม่พบเลย (0 hits) |

**`40402` คือคำตอบที่ถูกต้องสำหรับค่าปลอม** — Tange บอกว่าไม่รู้จัก app id ที่ส่งไป
แปลว่าทั้งเส้นทางทำงานหมด เหลือแค่ใส่ค่าจริง

### ยังทดสอบไม่ได้

- **พูดแล้วได้ยินที่ลำโพงกล้องจริง** — ต้องมี credential จาก Tange
- ตอนทดสอบกล้องต่อไม่ได้ ผมเลยใช้ stub คั่นเพื่อให้แผงควบคุมแสดงผล
  (เป็นไฟล์ชั่วคราวนอก repo ไม่ได้แตะโค้ดจริง)

---

## 5. เรื่องที่ต้องรู้

- **โทรศัพท์ถูก logout แล้ว** — ตอนติดตั้ง APK ทับ ระบบถอนตัวเก่าออกก่อน ข้อมูลในแอปเลยถูกล้าง
  ต้องล็อกอินใหม่ (เครื่องตอนนี้ลงตัว production ที่ชี้ `thanakronpart-time.com` เรียบร้อยแล้ว
  ไม่ได้ค้างตัวทดสอบไว้)
- **ยังไม่ได้ commit** — ไฟล์ที่แก้ยังอยู่ใน working tree
- **APK เซ็นด้วย debug key** เหมือนเดิม หัวหน้าอัปทับตัวเก่าได้ ไม่ต้องถอนติดตั้ง
- **ขนาด APK โตขึ้น** 53.3 MB → 73.8 MB เพราะ native library ของ TiRTC
- **Graph analysis ขึ้น HIGH risk** (12 ไฟล์ 39 symbols) เพราะ `camera_tab.dart` กับ
  `CameraStatus` เป็นจุดกลางของแท็บกล้อง ไม่ใช่ breaking change —
  ฟิลด์ที่เพิ่มมี default ครบ เซิร์ฟเวอร์รุ่นเก่าที่ไม่ส่งฟิลด์ใหม่มาก็ยังทำงานได้ (มีเทสต์คุม)

---

## คำสั่ง Tailscale

**เป้าหมาย:** ให้เครื่องพัฒนาที่อยู่นอกบ้าน เรียกกล้อง/เซิร์ฟเวอร์ที่บ้านได้
(production ไม่ต้องทำอะไร มันอยู่วงเดียวกับกล้องแล้ว)

มี 3 ทาง เรียงจากที่แนะนำที่สุด

---

### ทาง A (แนะนำ) — ไม่ต้องทำ subnet router เลย

ให้แอปคุยกับ **backend ที่บ้าน** ผ่าน Tailscale ตรง ๆ แล้วปล่อยให้เซิร์ฟเวอร์ที่บ้าน
เป็นคนเอื้อมไปหากล้องเหมือนเดิม — ไม่ต้องยุ่งกับ route ไม่เจอปัญหาเลขวงชนกัน

**บนเครื่องที่บ้าน (`WIN-QRB8CPGC62I`)** — เปิด backend ให้ tailnet เห็นผ่าน HTTPS:

```powershell
tailscale serve --bg 8001
tailscale serve status          # ดู URL ที่ได้ เช่น https://win-qrb8cpgc62i.<ชื่อ-tailnet>.ts.net
```

**บนเครื่องพัฒนา** — build แอปชี้ไป URL นั้น:

```powershell
cd checkin-system\flutter_boss_app
flutter build apk --release --dart-define=API_BASE=https://win-qrb8cpgc62i.<ชื่อ-tailnet>.ts.net
flutter install -d <device-id>
```

> **ทำไมต้อง `tailscale serve` ไม่ใช่ `http://100.92.152.56:8001` ตรง ๆ:**
> แอปบล็อก HTTP ที่ไม่เข้ารหัสทุกปลายทางยกเว้น localhost
> (ดู `android/app/src/main/res/xml/network_security_config.xml`)
> `tailscale serve` ให้ HTTPS พร้อมใบรับรองที่ถูกต้องมาเลย จึงผ่านกฎนี้โดยไม่ต้องแก้แอป

เลิกใช้เมื่อไรก็:

```powershell
tailscale serve --https=443 off
```

---

### ทาง B — subnet router + เปลี่ยนเลขวงที่บ้าน

ถ้าอยากให้เครื่องพัฒนาเรียก `192.168.1.101` ได้ตรง ๆ (เช่นรัน backend บนเครื่องพัฒนาเอง)

**ต้องเปลี่ยนเลขวงแลนที่บ้านก่อน** ให้ไม่ชนกับที่อื่น เช่นเปลี่ยนเป็น `192.168.50.0/24`
(ตั้งที่หน้า admin ของ router ที่บ้าน) แล้วกล้องจะกลายเป็น `192.168.50.101`

**บนเครื่องที่บ้าน:**

```powershell
tailscale up --advertise-routes=192.168.50.0/24
```

**อนุมัติ route:** เปิด https://login.tailscale.com/admin/machines
→ คลิกเครื่อง `win-qrb8cpgc62i` → **Edit route settings** → ติ๊กเปิด `192.168.50.0/24`

**บนเครื่องพัฒนา:**

```powershell
tailscale up --accept-routes
```

**ตรวจว่าใช้ได้:**

```powershell
tailscale status                # ควรเห็น route ใต้ชื่อเครื่องที่บ้าน
ping 192.168.50.101
```

อย่าลืมแก้ `backend\.env` ให้ตรง IP ใหม่ด้วย:

```
CAMERA_PTZ_HOST=192.168.50.101
CAMERA_RTSP_URL=rtsp://192.168.50.101:554
```

---

### ทาง C — subnet router แบบ 4via6 (ถ้าเปลี่ยนเลขวงไม่ได้)

Tailscale มีฟีเจอร์ **4via6** ทำมาเพื่อกรณีเลขวงชนกันโดยเฉพาะ
ให้เลข IPv6 เฉพาะตัวกับแต่ละไซต์ จึงไม่ชนกับวงที่เครื่องพัฒนาต่ออยู่

**สร้างเลข prefix (คำนวณไว้ให้แล้ว site id = 1):**

```powershell
tailscale debug via 1 192.168.1.0/24
# ได้: fd7a:115c:a1e0:b1a:0:1:c0a8:100/120
```

**บนเครื่องที่บ้าน:**

```powershell
tailscale up --advertise-routes=fd7a:115c:a1e0:b1a:0:1:c0a8:100/120
```

แล้วอนุมัติ route ใน admin console เหมือนทาง B

**บนเครื่องพัฒนา** — เรียกกล้องด้วยเลข IPv6 นี้แทน `192.168.1.101`:

```
fd7a:115c:a1e0:b1a:0:1:c0a8:165
```

(ผมคำนวณมาจาก `tailscale debug via 1 192.168.1.101/32` — `c0a8:165` คือ `192.168.1.101` ในเลขฐานสิบหก)

ตั้งใน `.env` ของ backend ที่รันบนเครื่องพัฒนา — **ต้องมีวงเล็บก้ามปูครอบ IPv6 ใน URL**:

```
CAMERA_PTZ_HOST=fd7a:115c:a1e0:b1a:0:1:c0a8:165
CAMERA_RTSP_URL=rtsp://[fd7a:115c:a1e0:b1a:0:1:c0a8:165]:554
```

> ทาง C ยุ่งกว่าและอ่านยากกว่ามาก ใช้เมื่อเปลี่ยนเลขวงที่บ้านไม่ได้จริง ๆ เท่านั้น

---

### คำสั่งตรวจสอบทั่วไป

```powershell
tailscale status                       # ดูเครื่องทั้งหมด + route ที่แชร์อยู่
tailscale ping 100.92.152.56           # ทดสอบถึงเครื่องที่บ้าน (ตอนนี้ได้ 13 ms แบบ direct)
tailscale netcheck                     # ตรวจคุณภาพเส้นทาง/NAT
tailscale debug prefs                  # ดูว่าเครื่องนี้ advertise/accept route อะไรอยู่
```

---

## คำสั่ง deploy ขึ้น production

### 1. บนเครื่องพัฒนา — commit + push

```powershell
cd c:\project_job_part-time
git status
git add checkin-system/flutter_boss_app checkin-system/HANDOVER_TALKBACK_2026-09-06.md
git commit -m "เพิ่มปุ่มกดค้างพูดออกลำโพงกล้องผ่าน TiRTC + เปลี่ยนโลโก้แอปหัวหน้า"
git push origin Film_dev_Part-Time
```

### 2. บนเครื่องที่บ้าน — ดึงโค้ดใหม่ + deploy

เปิด PowerShell แบบ **Run as Administrator**

```powershell
cd C:\apps\checkin-system
git pull

# ใส่ค่าจาก Tange (เปิดไฟล์แก้ด้วย notepad)
notepad backend\.env
#   CAMERA_TIRTC_ENABLED=true
#   CAMERA_TIRTC_APP_ID=<ค่าจาก Tange>
#   CAMERA_TIRTC_ACCESS_KEY_ID=<ค่าจาก Tange>
#   CAMERA_TIRTC_SECRET_KEY_ID=<ค่าจาก Tange>
#   CAMERA_TIRTC_REMOTE_ID=<device id ของกล้อง>

cd deploy\windows-server
.\deploy-update.ps1
```

`deploy-update.ps1` จะ build React → copy ขึ้น IIS → restart backend → ยิงทดสอบผ่านโดเมนจริงให้เอง

ตรวจอย่างเดียวไม่ deploy:

```powershell
.\deploy-update.ps1 -CheckOnly
```

ข้ามการ build หน้าเว็บ (แก้แต่ backend):

```powershell
.\deploy-update.ps1 -SkipFrontend
```

### 3. เอา APK ขึ้น production

**APK ไม่ได้ commit ลง git** (อยู่ใน `.gitignore`) ต้องส่งไฟล์ไปเอง —
copy ผ่าน Tailscale, AnyDesk, USB หรืออะไรก็ได้

ไฟล์ต้นทางบนเครื่องพัฒนา:

```
c:\project_job_part-time\checkin-system\flutter_boss_app\build\app\outputs\flutter-apk\app-release.apk
```

แล้วบนเครื่องที่บ้าน:

```powershell
cd C:\apps\checkin-system\deploy\windows-server
.\publish-apk.ps1 -Boss -ApkPath C:\Temp\app-release.apk
```

### 4. ตรวจว่าขึ้นจริง

```powershell
curl.exe https://thanakronpart-time.com/boss-app/info
```

ต้องได้ `"version":"1.2.0+4"` (ตอนนี้ยังเป็น `1.0.0+1`)

ถ้าจะ build APK ใหม่เองบนเครื่องพัฒนา:

```powershell
cd c:\project_job_part-time\checkin-system\flutter_boss_app
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release
```

---

## เอกสารที่เกี่ยวข้อง

- `flutter_boss_app/TIRTC_TALKBACK_TASKS.md` — รายละเอียดงานเต็ม + เกณฑ์รับงาน (อัปเดตแล้ว)
- `flutter_boss_app/BOSS_APK_PRODUCTION.md` — ขั้นตอน build/publish APK
- `deploy/windows-server/DEPLOY_WINDOWS_SERVER.md` — ขั้นตอน deploy backend
