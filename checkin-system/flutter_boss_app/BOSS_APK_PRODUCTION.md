# แจก APK แอปหัวหน้าบน production

ใช้ตอนแก้โค้ดแอปหัวหน้า (`flutter_boss_app`) เสร็จแล้วอยากให้หัวหน้าได้ของใหม่

> **แอปหัวหน้ากับแอปพนักงานเป็นคนละไฟล์ คนละลิงก์ ห้ามทับกัน**
>
> | | แอปพนักงาน | แอปหัวหน้า |
> |---|---|---|
> | โฟลเดอร์โค้ด | `flutter_app` | `flutter_boss_app` |
> | ไฟล์บนเซิร์ฟเวอร์ | `backend\storage\app\thanakon-checkin.apk` | `backend\storage\boss-app\thanakon-boss.apk` |
> | ลิงก์ดาวน์โหลด | `/app/download` | `/boss-app/download` |
> | applicationId | `com.mardodi.mardodi_checkin` | `com.mardodi.mardodi_boss` |
>
> คนละ applicationId แปลว่าติดตั้งอยู่ในเครื่องเดียวกันได้ทั้งคู่
> แต่ถ้าหัวหน้าเผลอโหลดตัวพนักงานมา จะเปิดแล้วเข้าไม่ได้เพราะเป็นคนละแอป

---

## ⚠️ แอปหัวหน้าไม่มีระบบเตือนอัปเดต

ต่างจากแอปพนักงาน — แอปหัวหน้า **ไม่เช็คเวอร์ชันใหม่ให้เอง โดยตั้งใจ**
([`profile_tab.dart`](lib/screens/tabs/profile_tab.dart) อธิบายไว้ว่าถ้าไปเทียบกับ
`/app/info` หัวหน้าจะกดโหลด APK ของ *แอปพนักงาน* มาทับ)

**แปลว่าปล่อยของใหม่แล้วต้องเดินไปบอกเอง** ไม่งั้นหัวหน้าจะใช้ตัวเก่าต่อไปโดยไม่รู้ตัว
และเข้าใจผิดว่าของที่แก้ไปแล้ว "ยังไม่หาย"

---

## 1. ขยับเลขเวอร์ชันก่อน build

**ต้องแก้ 2 ที่ให้ตรงกันเสมอ** — แอปอ่านเลขจาก `pubspec.yaml` ตอนรันไม่ได้
(ต้องเพิ่ม `package_info_plus` ซึ่งไม่คุ้มกับการเพิ่ม native plugin แค่โชว์ตัวเลข)

```yaml
# pubspec.yaml บรรทัด 4
version: 1.1.0+2
```

```dart
// lib/config.dart
static const String appVersion = "1.1.0";
```

ถ้าไม่ขยับ ทุกเครื่องจะโชว์เลขเดียวกันหมด เวลามีปัญหาจะไล่ไม่ถูกว่าใครอัปแล้วบ้าง

---

## 2. Build

```powershell
cd <โฟลเดอร์ repo>\checkin-system\flutter_boss_app
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
```

> **ไม่ต้องแก้ `apiBase` ก่อน build** — [`lib/config.dart`](lib/config.dart) ใช้
> `String.fromEnvironment("API_BASE")` ที่มีค่าเริ่มต้นเป็น
> `https://thanakronpart-time.com` อยู่แล้ว จะชี้ production ให้เองถ้าไม่ส่ง `--dart-define`
>
> (ตอนทดสอบกับ backend ในเครื่องถึงค่อยส่ง `--dart-define=API_BASE=http://localhost:8002`)

ได้ไฟล์ที่ `build\app\outputs\flutter-apk\app-release.apk`

---

## 3. วางไฟล์บนเซิร์ฟเวอร์

### วิธีที่แนะนำ — ใช้สคริปต์

```powershell
cd <โฟลเดอร์ repo>\checkin-system\deploy\windows-server
.\publish-apk.ps1 -Boss
```

สคริปต์จะทำให้ครบทั้งชุด:

- ตรวจว่าไฟล์เป็น APK จริง (ขึ้นต้นด้วย `PK`) — กันเคส copy มาไม่ครบ
- copy ไปที่ `backend\storage\boss-app\thanakon-boss.apk`
- เขียน `release.json` ให้เอง โดยอ่านเวอร์ชันจาก `pubspec.yaml`
  และใช้เวลา build จริง (ไม่ใช่เวลาที่ copy)

ถ้า build ที่เครื่อง dev แล้วส่งไฟล์มาเครื่อง production ให้ระบุที่อยู่ไฟล์:

```powershell
.\publish-apk.ps1 -Boss -ApkPath D:\thanakon-boss.apk
```

> **ไม่ต้อง restart backend** — `/boss-app/info` อ่านไฟล์จากดิสก์ใหม่ทุกครั้ง
>
> **ไฟล์อยู่รอดข้าม deploy หน้าเว็บ** เพราะอยู่ใน `backend\storage\`
> ไม่ใช่โฟลเดอร์ของ IIS ที่ถูกล้างทุกครั้งที่ deploy React ใหม่

### ถ้าจะทำเอง (ไม่แนะนำ — พลาดง่าย)

```powershell
$dir = "<โฟลเดอร์ repo>\checkin-system\backend\storage\boss-app"
New-Item -ItemType Directory $dir -Force | Out-Null
Copy-Item .\build\app\outputs\flutter-apk\app-release.apk "$dir\thanakon-boss.apk" -Force
```

แล้วเขียน `release.json` ในโฟลเดอร์เดียวกัน:

```json
{
  "version": "1.1.0+2",
  "built_at": "2026-09-02T09:37:05Z",
  "min_android": "7.0 (API 24)"
}
```

> ⚠️ **ต้องเป็น UTF-8 ไม่มี BOM** — `Set-Content -Encoding UTF8` ของ PowerShell 5.1
> ใส่ BOM ให้ ซึ่งเคยทำให้เวอร์ชันหายไปจากหน้าเว็บ
> (ตอนนี้ backend อ่านแบบ `utf-8-sig` แล้วจึงทนได้ แต่สคริปต์เขียนถูกให้อยู่แล้ว)
>
> ⚠️ **`built_at` ต้องเป็นเวลา UTC แบบ ISO 8601** ถ้าเครื่องตั้งภาษาไทย
> การ format วันที่เองจะได้ปี พ.ศ. (2569) แล้วหน้าเว็บจะโชว์เพี้ยนไปห้าร้อยปี

---

## 4. ตรวจว่าขึ้นแล้ว

```powershell
curl.exe -s https://thanakronpart-time.com/boss-app/info
```

ต้องเห็น `version` ตรงกับที่เพิ่งปล่อย และ `built_at` เป็นเวลาที่เพิ่ง build:

```json
{"available":true,"filename":"thanakon-boss.apk","download_url":"/boss-app/download",
 "size_bytes":55789840,"built_at":"2026-09-02T09:37:05Z","version":"1.1.0+2",
 "min_android":"7.0 (API 24)"}
```

ถ้า `version` ยังเป็นเลขเก่า แปลว่าไฟล์ยังไม่ได้ถูกวางทับ

---

## 5. ส่งให้หัวหน้า

ลิงก์: **https://thanakronpart-time.com/boss-app/download**

บอกหัวหน้าด้วยว่า:

1. เปิดลิงก์จากมือถือ Android แล้วกดดาวน์โหลด
2. ถ้าเครื่องถามสิทธิ์ "ติดตั้งแอปที่ไม่รู้จัก" ให้เปิดอนุญาตเฉพาะเบราว์เซอร์ที่ใช้โหลด
3. ติดตั้งทับตัวเดิมได้เลย ข้อมูลการล็อกอินไม่หาย

> ถ้าติดตั้งทับแล้วขึ้น "แอปยังไม่ได้ติดตั้ง" ให้ถอนตัวเก่าออกก่อนแล้วติดตั้งใหม่
> (เกิดตอนเปลี่ยน signing key ซึ่งจะทำให้ต้องล็อกอินใหม่ครั้งเดียว)

---

## 6. Checklist

- [ ] ขยับเลขเวอร์ชันแล้วทั้ง `pubspec.yaml` และ `lib/config.dart` ให้ตรงกัน
- [ ] build จาก `flutter_boss_app` ไม่ใช่ `flutter_app`
- [ ] `.\publish-apk.ps1 -Boss` รันผ่าน และรายงานเวอร์ชันถูกต้อง
- [ ] `/boss-app/info` โชว์เวอร์ชันใหม่
- [ ] ส่งลิงก์ `/boss-app/download` ให้หัวหน้าแล้ว **และบอกให้อัปเดต**
- [ ] ลิงก์พนักงาน `/app/download` ยังเป็น `thanakon-checkin.apk` เหมือนเดิม
- [ ] ไม่ได้ commit ไฟล์ `.apk` เข้า git (`backend/storage/*` อยู่ใน `.gitignore` แล้ว)

---

## ทดสอบหลังหัวหน้าอัปเดต

เปิดแท็บ "กล้องวงจรปิด" ต้องได้ครบ:

- [ ] เห็นภาพสด มีป้าย **LIVE** สีแดง (ไม่ใช่ "ภาพค้าง" สีส้ม)
- [ ] ปุ่มทิศทางกดแล้วกล้องหมุนจริง
- [ ] เห็นปุ่ม **"ฟังเสียงจากกล้อง"** (ไม่ใช่ข้อความสีจาง)
- [ ] กดแล้วได้ยินเสียงภายในราว 10 วินาที
- [ ] สลับไปแท็บอื่นแล้วกลับมา สถานะยังถูกต้อง ไม่ค้างค่าเก่า

ถ้า 3 ข้อท้ายไม่ผ่าน ปัญหาอยู่ฝั่งเซิร์ฟเวอร์ ไม่ใช่แอป —
ดู [`SERVER_TASKS_CAMERA_AUDIO.md`](../deploy/windows-server/SERVER_TASKS_CAMERA_AUDIO.md)
