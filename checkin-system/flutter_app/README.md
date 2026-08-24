# แอปเช็คอิน THANAKON-ROOM (Flutter)

แอป Android สำหรับพนักงาน — เช็คอินด้วย GPS + สแกนใบหน้า
คุยกับ backend ตัวเดียวกับเว็บ (ตั้ง URL ที่ `lib/config.dart`)

## build เป็นไฟล์ APK ให้พนักงานโหลดจากเว็บ

รันบนเครื่องที่มี Flutter SDK + Android SDK (เครื่อง production ไม่ต้องมี — ดูหัวข้อถัดไป):

```powershell
.\deploy\windows-server\build-flutter-apk.ps1
```

สคริปต์จะทำให้ทั้งหมดนี้เอง:

1. `flutter create --platforms=android .` ถ้ายังไม่มีโฟลเดอร์ `android/`
   (โฟลเดอร์นี้ไม่ได้ commit ลง git เพราะสร้างใหม่ได้)
2. เติมสิทธิ์กล้อง/ตำแหน่ง/แจ้งเตือน และตั้งชื่อแอปลง `AndroidManifest.xml`
   ตาม [PLATFORM_SETUP.md](PLATFORM_SETUP.md)
3. ตั้ง `minSdk = 23` (ML Kit + background service ต้องการ)
4. สร้างไอคอนแอปจาก **โลโก้ตัวเดียวกับเว็บ** (ดูหัวข้อถัดไป)
5. `flutter build apk --release`
6. copy ไฟล์ไปที่ `backend/storage/app/thanakon-checkin.apk`
   → พนักงานเห็นปุ่มดาวน์โหลดที่หน้าแรกของเว็บทันที ไม่ต้อง deploy เว็บใหม่

หรือสั่งพร้อม deploy เว็บในทีเดียว: `.\BUILD_DEPLOY.ps1 -BuildApk`

## ส่ง APK ขึ้นเครื่อง production

เครื่อง production ไม่มี Flutter SDK และ APK ก็ไม่ได้ commit ลง git (ไฟล์ 70+ MB)
จึงต้อง copy ไฟล์ `.apk` ไปเอง แล้วสั่งบนเซิร์ฟเวอร์:

```powershell
.\deploy\windows-server\publish-apk.ps1 -ApkPath D:\thanakon-checkin.apk
```

สคริปต์จะตรวจว่าไฟล์เป็น APK จริง วางลง `backend/storage/app/` แล้วเขียนเวอร์ชัน/วันที่ build
ลง `release.json` ให้หน้าเว็บ — ไม่ต้อง restart backend และไม่ต้อง deploy เว็บใหม่
เช็กผลที่ `https://thanakronpart-time.com/app/info` (ต้องได้ `"available": true`)

## ไอคอนแอป = โลโก้เดียวกับเว็บ

| ไฟล์ | ที่มา |
| --- | --- |
| `assets/icon/app-icon.png` | `frontend/public/logo-checkin.png` วางบนพื้นขาว |
| `assets/icon/app-icon-foreground.png` | โลโก้เดิมย่อให้อยู่ในโซนปลอดภัยของ adaptive icon (Android 8+) |

ตั้งค่าอยู่ในหัวข้อ `flutter_launcher_icons` ท้าย `pubspec.yaml`
ถ้าเปลี่ยนโลโก้ของเว็บ ให้สร้างสองไฟล์นี้ใหม่จากโลโก้ตัวใหม่ แล้ว build APK อีกครั้ง
(สคริปต์เรียก `flutter pub run flutter_launcher_icons` ให้อยู่แล้ว)

> ในไฟล์ตั้งค่าเปิดเฉพาะ `android: true` — `ios: false` เพราะ repo นี้ไม่มีโฟลเดอร์ `ios/`
> ถ้าเปิดไว้ flutter_launcher_icons จะล้มทั้งขั้นตอนตอนหาไฟล์ `Icon-App-*.png` ไม่เจอ
> (จะทำ iOS เมื่อไหร่ ให้ `flutter create --platforms=ios .` ก่อน แล้วค่อยสลับเป็น true)

## หมดเวลาใช้งานประจำวัน (4 ทุ่ม)

ทุกเครื่องจะถูกเด้งออกจากระบบตอน **22:00 น. เวลาไทย** แล้วต้องล็อกอินใหม่ในวันถัดไป
กันเคสลืมออกจากระบบแล้วเครื่องส่งพิกัด GPS ต่อทั้งคืน และกัน token ค้างในเครื่องที่ทำหาย

| ตอนนั้นแอปอยู่สถานะไหน | เกิดอะไรขึ้น |
| --- | --- |
| เปิดหน้าจอค้างไว้ | Timer ครบเวลา → หยุด background service → กลับไปหน้าล็อกอินพร้อมข้อความบอกเหตุผล |
| ถูกพักไว้เบื้องหลัง / เพิ่งเปิดขึ้นมาใหม่ | เช็กเวลาซ้ำตอน resume และตอนเปิดแอป (`ApiService.loadToken`) |
| ส่งพิกัดอยู่ใน background isolate | `sendPing` เรียก `ensureSession()` ก่อนทุกครั้ง เลยเวลาแล้วจะหยุดส่งเอง |

ตั้งค่าเวลาได้ที่ `lib/config.dart` → `sessionEndHour` / `sessionEndMinute`
(ยึดเวลาไทยด้วย `thaiUtcOffset` ไม่ใช่ timezone ของเครื่อง — มือถือที่ตั้งเวลาผิดจะได้หมดพร้อมกัน)

> เวอร์ชันแรกที่มีเงื่อนไขนี้คือ 1.1.0 — เครื่องที่อัปเดตจากตัวเก่าจะโดนให้ล็อกอินใหม่หนึ่งครั้ง
> เพราะ token เดิมไม่มีเวลาหมดอายุติดมาด้วย

> ฝั่ง backend ยังออก JWT อายุ 12 ชม. ตามเดิม (`access_token_expire_minutes`)
> เงื่อนไข 4 ทุ่มนี้บังคับที่ตัวแอป ถ้าต้องการให้ตัว token หมดอายุจริงตาม ต้องแก้ที่ backend ด้วย

## รันตอนพัฒนา

```powershell
flutter pub get
flutter run
```
