# แจก APK แอป Boss บน Production

เอกสารนี้ใช้สำหรับนำไฟล์ `.apk` ของแอปหัวหน้า (`flutter_boss_app`) ไปวางบน
production เพื่อให้หัวหน้าเปิดลิงก์จากมือถือ Android แล้วดาวน์โหลดได้

> สำคัญ: `/app/download` ในระบบปัจจุบันเป็น APK ของแอปพนักงาน
> (`thanakon-checkin.apk`) เท่านั้น ห้ามเอา APK ของ Boss ไปทับไฟล์นั้น

## 1. Build APK จากเครื่อง dev

ก่อน build ให้ตรวจว่าแอปชี้ไป production URL จริง:

```dart
// flutter_boss_app/lib/config.dart
static const String apiBase = "https://thanakronpart-time.com";
```

จากนั้น build:

```powershell
cd C:\project_job_part-time\checkin-system\flutter_boss_app
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
```

ไฟล์ที่ได้:

```text
flutter_boss_app\build\app\outputs\flutter-apk\app-release.apk
```

แนะนำให้ copy/rename เป็นชื่อที่อ่านรู้เรื่องก่อนส่งให้ production:

```powershell
Copy-Item .\build\app\outputs\flutter-apk\app-release.apk C:\Temp\thanakon-boss.apk -Force
```

## 2. ส่งไฟล์ไปเครื่อง production

ส่ง `thanakon-boss.apk` ไปที่เครื่อง production ด้วยวิธีใดก็ได้ เช่น Remote
Desktop, shared folder, USB, หรือ cloud drive ชั่วคราว

ห้าม commit ไฟล์ `.apk` เข้า git เพราะไฟล์ใหญ่และเป็น build artifact

## 3. วางไฟล์ให้ IIS ดาวน์โหลดได้

บนเครื่อง production ให้วาง APK ไว้ใต้โฟลเดอร์เว็บที่ IIS เสิร์ฟอยู่:

```powershell
$site = "C:\apps\checkin-system\frontend\dist"
New-Item -ItemType Directory -Path "$site\downloads" -Force | Out-Null
Copy-Item "D:\thanakon-boss.apk" "$site\downloads\thanakon-boss.apk" -Force
```

ลิงก์สำหรับส่งให้หัวหน้า:

```text
https://thanakronpart-time.com/downloads/thanakon-boss.apk
```

ถ้าโหลดแล้วได้ 404.3 หรือ IIS ไม่ยอมเสิร์ฟ `.apk` ให้เพิ่ม MIME type นี้ใน IIS:

```text
Extension: .apk
MIME type: application/vnd.android.package-archive
```

## 4. ตรวจหลังวางไฟล์

จากเครื่องใดก็ได้:

```powershell
curl.exe -I https://thanakronpart-time.com/downloads/thanakon-boss.apk
```

ควรเห็น:

- HTTP status เป็น `200`
- มี `Content-Length` และขนาดมากกว่า 0
- `Content-Type` เป็น `application/vnd.android.package-archive`

จากมือถือ Android ให้เปิดลิงก์ ดาวน์โหลดไฟล์ แล้วติดตั้ง หากเครื่องถามสิทธิ์
"ติดตั้งแอปที่ไม่รู้จัก" ให้เปิดอนุญาตเฉพาะ browser ที่ใช้ดาวน์โหลด

## 5. หลัง deploy เว็บใหม่

ถ้า deploy React ใหม่แล้วล้างโฟลเดอร์ `frontend\dist` ไฟล์ใน
`frontend\dist\downloads` จะหายไปด้วย ต้อง copy
`thanakon-boss.apk` กลับไปวางใหม่อีกครั้ง

ถ้าต้องการให้ไฟล์อยู่รอดข้าม deploy แบบเดียวกับแอปพนักงาน ควรเพิ่ม endpoint
ใหม่แยกจาก `/app/download` เช่น `/boss-app/download` แล้วให้ backend เสิร์ฟไฟล์
จาก `backend\storage\app\thanakon-boss.apk`

## 6. Checklist ก่อนส่งลิงก์

- `flutter_boss_app/lib/config.dart` ชี้ `https://thanakronpart-time.com`
- `flutter_boss_app/pubspec.yaml` เพิ่ม `version:` แล้วเมื่อปล่อยเวอร์ชันใหม่
- `flutter_boss_app/lib/config.dart` ค่า `Config.appVersion` ตรงกับเวอร์ชันที่ปล่อย
- APK ที่ส่งให้ production มาจาก `flutter_boss_app` ไม่ใช่ `flutter_app`
- ลิงก์ Boss คือ `/downloads/thanakon-boss.apk`
- ลิงก์พนักงาน `/app/download` ยังดาวน์โหลด `thanakon-checkin.apk` เหมือนเดิม
