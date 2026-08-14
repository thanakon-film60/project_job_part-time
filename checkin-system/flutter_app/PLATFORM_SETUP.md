# การตั้งค่าสิทธิ์ (Android / iOS) สำหรับแอป Flutter

หลังรัน `flutter create .` ในโฟลเดอร์นี้เพื่อสร้าง `android/` และ `ios/` แล้ว
ให้เพิ่มสิทธิ์ต่อไปนี้

## Android — `android/app/src/main/AndroidManifest.xml`
เพิ่มก่อน `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

ภายใน `<application>` (สำหรับ flutter_background_service):

```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="location"
    android:exported="false" />
```

ตั้ง `minSdkVersion` เป็น 23 ขึ้นไปใน `android/app/build.gradle`
(ML Kit + background service ต้องการ 23+; แนะนำ 24+)

## iOS — `ios/Runner/Info.plist`
เพิ่ม:

```xml
<key>NSCameraUsageDescription</key>
<string>ใช้กล้องเพื่อสแกนใบหน้าตอนเช็คอิน</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>ใช้ตำแหน่งเพื่อยืนยันว่าอยู่ในเขตออฟฟิศ</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>ใช้ตำแหน่งตลอดเวลาเพื่อบันทึกการเข้างาน</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
</array>
```

## หมายเหตุ
- `Config.apiBase` ใน `lib/config.dart`: Android emulator ใช้ `http://10.0.2.2:8000`
  เครื่องจริงให้ใช้ IP ของเครื่องรัน backend เช่น `http://192.168.1.10:8000`
- โหมดตรวจใบหน้าเป็น **face detection + liveness** (ยืนยันว่ามีคนจริง)
  ไม่ได้จับคู่ว่าเป็นใคร ถ้าต้องการยืนยันตัวตน 1:1 ต้องเพิ่ม face embeddings ภายหลัง
