# ทำให้แอป Flutter รัน/บิลด์ได้

สรุปทุกอย่างที่ต้องมีและต้องรัน เพื่อให้ `flutter_app/` ทำงานได้จริง
พร้อมรายการที่ต้องตรวจหลังติดตั้งเสร็จ

เอกสารที่เกี่ยวข้อง: [PLATFORM_SETUP.md](PLATFORM_SETUP.md) (สิทธิ์ Android/iOS) ·
[README.md](README.md) (รายละเอียดแอปทั้งหมด)

---

## 1. สถานะตอนนี้ — ติดอะไรอยู่

| สิ่งที่ต้องมี | สถานะบนเครื่อง WIN-QRB8CPGC62I | ผลที่ตามมา |
|---|---|---|
| Flutter SDK | **ยังไม่มี** (`flutter` ไม่อยู่ใน PATH และหาไม่เจอในดิสก์) | `flutter analyze` / `build` / `test` รันไม่ได้เลย |
| Android SDK + JDK | ยังไม่ได้ตรวจ (ตรวจได้หลังลง Flutter) | build APK ไม่ได้ |
| โฟลเดอร์ `android/` | **ยังไม่มี** — ไม่ได้ commit ลง git โดยตั้งใจ | สร้างใหม่ได้ด้วย `flutter create` (สคริปต์ทำให้อัตโนมัติ) |
| โค้ด Dart | ครบ | แก้ล่าสุดยังไม่ผ่าน compiler — ดูข้อ 5 |

> `android/` อยู่ใน `.gitignore` เพราะเป็นไฟล์ที่สร้างใหม่ได้ ไม่ใช่ของหาย

---

## 2. ติดตั้งครั้งเดียว

### 2.1 Flutter SDK
ต้องการ Dart SDK `>=3.3.0 <4.0.0` และ Flutter `>=3.19.0` (ระบุไว้ใน `pubspec.yaml`)

1. โหลดจาก https://docs.flutter.dev/get-started/install/windows
2. แตกไฟล์ไว้ที่ path ที่**ไม่มีช่องว่างและไม่ต้องใช้สิทธิ์ admin** เช่น `C:\flutter`
   (อย่าวางใน `C:\Program Files` — Gradle จะพังเรื่อง path ที่มีช่องว่าง)
3. เพิ่ม `C:\flutter\bin` ลง PATH แล้วเปิด terminal ใหม่

```powershell
[Environment]::SetEnvironmentVariable(
    "Path", "$([Environment]::GetEnvironmentVariable('Path','Machine'));C:\flutter\bin", "Machine")
```

### 2.2 Android SDK + JDK
ลง **Android Studio** (มาพร้อม Android SDK + JDK) แล้วเปิด SDK Manager ติ๊ก:

- Android SDK Platform (API 34 ขึ้นไป)
- Android SDK Build-Tools
- Android SDK Command-line Tools ← **ตัวนี้ต้องมี** ไม่งั้น `flutter doctor` ไม่ผ่าน
- Android SDK Platform-Tools

### 2.3 ตรวจว่าครบ

```powershell
flutter doctor
flutter doctor --android-licenses   # กด y รับ license จนหมด
```

ต้องเห็น ✓ ที่ **Flutter** และ **Android toolchain** เป็นอย่างน้อย
(Visual Studio / Chrome ไม่จำเป็น — โปรเจ็กต์นี้ build เฉพาะ Android)

---

## 3. คำสั่งที่ใช้ประจำ

รันจากในโฟลเดอร์ `flutter_app/`

```powershell
flutter pub get        # ดึงแพ็กเกจ (ทำก่อนเสมอหลัง pull โค้ดใหม่)
flutter analyze        # ตรวจ error/lint ทั้งโปรเจ็กต์ — เร็วสุด ใช้ตรวจก่อน build
flutter test           # รันเทสต์ใน test/ (employee_logic, face_gallery, widget)
flutter run            # รันบนมือถือ/emulator ที่ต่ออยู่ (hot reload)
flutter devices        # ดูว่ามีเครื่องไหนต่ออยู่บ้าง
```

**ลำดับที่แนะนำหลังแก้โค้ด:** `pub get` → `analyze` → `test` → `run`

---

## 4. บิลด์ APK แจกพนักงาน

ใช้สคริปต์ อย่าสั่ง `flutter build apk` ตรง ๆ

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\deploy\windows-server
.\build-flutter-apk.ps1
.\build-flutter-apk.ps1 -Clean    # ใช้เมื่อไอคอนไม่ยอมเปลี่ยน
```

สคริปต์ทำให้ครบในรอบเดียว:

1. `flutter create --platforms=android .` ถ้ายังไม่มี `android/`
2. เติมสิทธิ์ทั้งหมดใน `AndroidManifest.xml` (ตาม [PLATFORM_SETUP.md](PLATFORM_SETUP.md))
   \+ `BackgroundService` ของ flutter_background_service + ตั้งชื่อแอป `THANAKON-ROOM`
3. ตั้ง `minSdk = 24` (ML Kit + background service ต้องการ 23+)
4. `flutter pub get` → `dart run flutter_launcher_icons` → `flutter build apk --release`
5. copy APK ไป `backend\storage\app\thanakon-checkin.apk` + เขียน `release.json`

พนักงานเห็นปุ่มดาวน์โหลดที่หน้าแรกของเว็บทันที **ไม่ต้อง deploy เว็บใหม่**

---

## 5. ต้องตรวจหลังลง Flutter เสร็จ — งานที่ยังไม่ผ่าน compiler

ฟีเจอร์ **"เตือนเมื่อยังไม่ได้ยืนยันตัวตน"** เขียนเสร็จแล้วแต่ยังไม่เคยผ่าน
`flutter analyze` เพราะเครื่องที่เขียนไม่มี SDK — ต้องรันตรวจก่อนใช้จริง

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\flutter_app
flutter pub get
flutter analyze     # ต้องได้ "No issues found!"
flutter test
```

ไฟล์ที่เกี่ยวข้อง:

| ไฟล์ | สถานะ | หน้าที่ |
|---|---|---|
| `lib/widgets/duty_warning_card.dart` | ใหม่ | การ์ดแดง + ข้อความเตือน + `DutyVerification` |
| `lib/screens/tabs/checkin_tab.dart` | แก้ | โหลด `/faces/me` แล้วโชว์การ์ดบนสุดของหน้าเช็คอิน |
| `lib/models/team_calendar.dart` | แก้ | รับ `missing` + `face_enrolled` จาก API |
| `lib/screens/tabs/team_tab.dart` | แก้ | ฝั่งหัวหน้า: การ์ดสรุป + ป้าย "ขาด N" + รายชื่อรายวัน |

**สิ่งที่ต้องเห็นตอนทดสอบจริง**

- เข้าแอปด้วยพนักงานที่ยังไม่ได้ลงเวลาวันนี้ → การ์ดแดงขึ้นบนสุดของแท็บเช็คอิน
- พนักงานที่ยังไม่เคยลงทะเบียนใบหน้า → มีปุ่ม "ลงทะเบียนใบหน้าตอนนี้" เพิ่มมาในการ์ด
- ลงเวลาเสร็จ → การ์ดหายไปเอง (ไม่ต้องปิดแอปเปิดใหม่)
- เข้าด้วยหัวหน้า → แท็บทีมมีการ์ดแดงสรุปคนที่ขาดของวันนี้ และช่องปฏิทินมีป้าย "ขาด N"

> ต้อง **restart backend** ก่อนทดสอบ ไม่งั้น `/reports/team-calendar` ยังไม่ส่ง
> `missing` มา แล้วแท็บทีมจะไม่ขึ้นอะไรเลย (กดปุ่ม "↻ รีสตาร์ต Production"
> ในแผงควบคุม `START_PART_TIME.bat`)

---

## 6. ชี้แอปไปที่ backend ตัวไหน

แก้ `Config.apiBase` ใน [lib/config.dart](lib/config.dart)

```dart
static const String apiBase = "https://thanakronpart-time.com";  // เว็บจริง (ค่าปัจจุบัน)
// static const String apiBase = "http://10.0.2.2:8002";         // dev บน Android emulator
```

- **Android emulator** → `http://10.0.2.2:<port>` (`10.0.2.2` = localhost ของเครื่องแม่)
- **มือถือจริงในวง LAN เดียวกัน** → `http://<IP เครื่องที่รัน backend>:8002`
  เช่น `http://192.168.1.10:8002` (ต้องเปิด firewall ให้พอร์ตนั้นด้วย)
- **มือถือจริงนอกวง** → ใช้ `https://thanakronpart-time.com` ผ่าน Cloudflare Tunnel

APK ที่แจกพนักงานต้องเป็นค่าเว็บจริงเสมอ อย่าเผลอ build ตอนตั้งเป็น dev

---

## 7. ปัญหาที่เจอบ่อย

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| `ไม่พบคำสั่ง flutter` | ยังไม่ได้เพิ่ม `C:\flutter\bin` ลง PATH หรือยังไม่ได้เปิด terminal ใหม่ |
| `Could not determine the dependencies of task ':jni_flutter:...'` | `path_provider_android` ถูกตรึงไว้ที่ `2.2.23` ใน `pubspec.yaml` แล้ว — อย่าถอด `dependency_overrides` ออกจนกว่าจะอัปเกรด AGP/Gradle |
| build ผ่านแต่ไอคอนเป็นตัวเดิม | `.\build-flutter-apk.ps1 -Clean` |
| ติดตั้ง APK บนมือถือไม่ได้ | เครื่องต่ำกว่า Android 7.0 (API 24) — ดูค่าจริงที่ `release.json` |
| แอปไม่ส่งพิกัดตอนพับหน้าจอ | ยังไม่ได้ให้สิทธิ์ "ตำแหน่ง — อนุญาตตลอดเวลา" หรือโหมดประหยัดแบตฆ่า service (ดู `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` ใน PLATFORM_SETUP.md) |
| `flutter doctor` ค้างที่ Android licenses | `flutter doctor --android-licenses` แล้วกด `y` ทุกข้อ |
| กล้องเปิดไม่ขึ้นตอนสแกนหน้า | ยังไม่ได้ให้สิทธิ์กล้อง หรือรันบน emulator ที่ไม่ได้ตั้งกล้องหน้าเป็น webcam |

---

## 8. iOS

`ios/` ไม่ได้อยู่ใน repo — build ได้เฉพาะบนเครื่อง Mac และต้องแก้ `Info.plist`
เองตาม [PLATFORM_SETUP.md](PLATFORM_SETUP.md) (`flutter_launcher_icons` ก็ตั้ง
`ios: false` ไว้ด้วย ถ้าจะทำ iOS ต้อง `flutter create --platforms=ios .` ก่อน)
