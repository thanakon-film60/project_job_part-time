# แอปเช็คอิน THANAKON-ROOM (Flutter)

แอป Android สำหรับพนักงาน — เช็คอินด้วย GPS + สแกนใบหน้า
คุยกับ backend ตัวเดียวกับเว็บ (ตั้ง URL ที่ `lib/config.dart`)

## build เป็นไฟล์ APK ให้พนักงานโหลดจากเว็บ

รันบนเครื่องเซิร์ฟเวอร์ (ต้องมี Flutter SDK + Android SDK):

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

## ไอคอนแอป = โลโก้เดียวกับเว็บ

| ไฟล์ | ที่มา |
| --- | --- |
| `assets/icon/app-icon.png` | `frontend/public/logo-checkin.png` วางบนพื้นขาว |
| `assets/icon/app-icon-foreground.png` | โลโก้เดิมย่อให้อยู่ในโซนปลอดภัยของ adaptive icon (Android 8+) |

ตั้งค่าอยู่ในหัวข้อ `flutter_launcher_icons` ท้าย `pubspec.yaml`
ถ้าเปลี่ยนโลโก้ของเว็บ ให้สร้างสองไฟล์นี้ใหม่จากโลโก้ตัวใหม่ แล้ว build APK อีกครั้ง
(สคริปต์เรียก `flutter pub run flutter_launcher_icons` ให้อยู่แล้ว)

## รันตอนพัฒนา

```powershell
flutter pub get
flutter run
```
