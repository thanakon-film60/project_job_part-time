# งานปรับ async สำหรับเครื่องพัฒนา Flutter

เอกสารนี้เป็นรายการงานสำหรับเครื่องที่มี Flutter SDK พร้อมใช้งาน โดยยังไม่มีการแก้ไฟล์ `.dart` ใน repository จากเครื่องปัจจุบัน

## เป้าหมาย

ป้องกัน `Future` จาก network, GPS และ SharedPreferences ทำงานซ้อนกันเมื่อถูกเรียกผ่าน `Timer.periodic` หรือ callback ของ `Stream.listen`

โค้ด HTTP, การอัปโหลดไฟล์, GPS, SharedPreferences, กล้อง และ ML Kit ในปัจจุบันใช้ `await` แล้ว ไม่ต้องเปลี่ยน API layer ใหม่ทั้งหมด

## 1. ป้องกัน background ping ซ้อนกัน

ไฟล์: `lib/services/background_service.dart`

ปัญหาอยู่ที่ callback ของ `Timer.periodic` บรรทัดท้ายไฟล์ เพราะ Timer ไม่รอ `tick()` ให้เสร็จก่อนเริ่มรอบถัดไป หาก GPS หรือ API ช้ากว่าช่วงเวลา ping จะเกิดหลาย request พร้อมกัน

เพิ่มสถานะภายใน `onStart`:

```dart
bool tickInProgress = false;

Future<void> guardedTick() async {
  if (tickInProgress) return;
  tickInProgress = true;
  try {
    await tick();
  } finally {
    tickInProgress = false;
  }
}
```

แล้วเปลี่ยนส่วนเริ่มทำงานเป็น:

```dart
await guardedTick();
pingTimer = Timer.periodic(
  const Duration(seconds: Config.pingIntervalSeconds),
  (_) => unawaited(guardedTick()),
);
```

เพิ่ม `unawaited` จาก `dart:async` ซึ่งไฟล์ import อยู่แล้ว เพื่อประกาศให้ชัดเจนว่า callback ของ Timer เป็น fire-and-forget ที่มี guard ควบคุม

## 2. จัดการ Future จาก service event listeners

ไฟล์: `lib/services/background_service.dart`

callback ต่อไปนี้ปล่อย `Future` โดยไม่จัดการ error:

```dart
service.on('stopService').listen((_) => stop());
service.on('refreshSession').listen((_) => ApiService.loadToken());
```

เปลี่ยนเป็น callback ที่จัดการ Future อย่างชัดเจน:

```dart
service.on('stopService').listen((_) async {
  await stop();
});

service.on('refreshSession').listen((_) async {
  await ApiService.loadToken();
});
```

ถ้าต้องการให้ service ไม่เกิด unhandled asynchronous error ให้เพิ่ม `onError` หรือ `try/catch` พร้อมรายงานผ่าน `report(error: ...)`

## 3. ป้องกัน attendance refresh ซ้อนกัน

ไฟล์: `lib/screens/tabs/checkin_tab.dart`

`Timer.periodic` เรียก `_loadToday()` โดยไม่รอรอบก่อนหน้า ให้เพิ่ม field:

```dart
bool _attendanceLoadInProgress = false;
```

แล้ว guard ภายใน `_loadToday()`:

```dart
if (_attendanceLoadInProgress) return;
_attendanceLoadInProgress = true;
try {
  // โค้ดเดิมทั้งหมดของ _loadToday()
} finally {
  _attendanceLoadInProgress = false;
}
```

callback ของ Timer ใช้:

```dart
(_) => unawaited(_loadToday())
```

การเรียก `_loadToday()` จาก `initState` ควรใช้ `unawaited(_loadToday())` เช่นกัน เพื่อให้ analyzer เห็นว่าเป็นการไม่รอโดยตั้งใจ

## 4. ป้องกัน permission dialog ซ้อนกัน

ไฟล์: `lib/screens/app_shell.dart`

`Timer.periodic` อาจเรียก `_nagForAlwaysPermission()` ซ้ำระหว่างที่ permission dialog เดิมยังเปิดอยู่ ให้เพิ่ม flag เช่น `_permissionPromptInProgress` และคืนค่าทันทีหากกำลังทำงาน ก่อน reset flag ใน `finally`

การเรียกจาก Timer ควรใช้:

```dart
(_) => unawaited(_nagForAlwaysPermission())
```

## 5. ตรวจสอบหลังแก้

รันจากโฟลเดอร์ `flutter_app`:

```text
flutter pub get
dart format lib
flutter analyze
flutter test
```

ทดสอบบน Android จริงเพิ่มเติม:

1. เปิด background tracking แล้วทำให้ network ช้าหรือขาดช่วง
2. ยืนยันว่าไม่มี ping หลาย request ซ้อนกัน
3. กด logout ระหว่างกำลังดึง GPS และตรวจว่า service หยุดได้
4. เปิดหน้าเช็กอินค้างไว้นานกว่าหนึ่งรอบ refresh และตรวจว่า attendance ไม่กระพริบหรือย้อนกลับเป็นข้อมูลเก่า
5. ปฏิเสธ permission หลายครั้งและตรวจว่า dialog ไม่ซ้อนกัน
