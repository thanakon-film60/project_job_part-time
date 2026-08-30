# THANAKON-BOX — แอปสำหรับหัวหน้า (Flutter)

แอปแยกตัวสำหรับ **หัวหน้า** โดยเฉพาะ ติดตั้งคู่กับแอปพนักงานในเครื่องเดียวกันได้
เพราะใช้ `applicationId` คนละตัว ยิงไปที่ backend ตัวเดียวกับแอปพนักงานและเว็บ
ไม่มี API ใหม่ที่ฝั่งเซิร์ฟเวอร์

| | แอปพนักงาน (`flutter_app/`) | แอปหัวหน้า (`flutter_boss_app/`) |
| --- | --- | --- |
| applicationId | `com.mardodi.mardodi_checkin` | `com.mardodi.mardodi_boss` |
| ชื่อบนเครื่อง | THANAKON-ROOM | THANAKON-BOX หัวหน้า |
| package (Dart) | `thanakon_box_checkin` | `thanakon_box_boss` |
| ล็อกอินได้ | ทุกบัญชี | เฉพาะบัญชี `is_manager = true` |
| ลงเวลา | ต้องสแกนใบหน้า + liveness ทุกครั้ง | **กดยืนยันได้เลย ไม่ต้องสแกนหน้า** |
| กล้อง | ใช้ (`camera`, `google_mlkit_face_detection`) | ไม่ใช้ — ถอด dependency และสิทธิ์ CAMERA ออกแล้ว |
| ลงทะเบียนใบหน้า | ได้ | ไม่มี (ดูรูปที่มีอยู่ได้อย่างเดียว) |

## เมนูในแอป

| แท็บ | ไฟล์ | เนื้อหา |
| --- | --- | --- |
| ภาพรวมทีม | `screens/tabs/overview_tab.dart` | หน้าแรก — วันนี้ใครมา ใครยังไม่ลงเวลา ใครอยู่บ้าน ใครกำลังส่งตำแหน่ง |
| เช็คอินเข้างาน | `screens/tabs/checkin_tab.dart` | ลงเวลาของหัวหน้าเอง (ไม่มีสแกนหน้า) |
| ปฏิทินทีม | `screens/tabs/team_tab.dart` | ปฏิทินรายเดือน ใครลงเวลาวันไหน กดวันเพื่อดูเวลาเข้า–ออก |
| ข้อมูลพนักงาน | `screens/tabs/employees_tab.dart` | รายชื่อ + สถานะวันนี้ · ตัวกรอง · ค้นหา · แฟ้มรายคน · ลงทะเบียนพนักงาน |
| แผนที่ติดตาม | `screens/tabs/live_map_tab.dart` | ตำแหน่งล่าสุดของทุกคน · วงเขต · เส้นทางย้อนหลัง |
| ประวัติการลงเวลา | `screens/tabs/history_tab.dart` | ของหัวหน้าเอง ย้อนหลัง 30 วัน |
| บัญชีของฉัน | `screens/tabs/profile_tab.dart` | ข้อมูลผู้ใช้ · รูปยืนยันตัวตนที่มีอยู่ · เวอร์ชันแอป |
| สถานที่ & สถานะระบบ | `screens/tabs/places_tab.dart` | รัศมีที่เช็คอินได้ · การติดตาม |

## การลงเวลาโดยไม่ต้องสแกนใบหน้า

แอปส่ง `face_detected=false` **ตามจริง** ไม่ได้โกหกเซิร์ฟเวอร์ว่าสแกนแล้ว
ตัวที่ยกเว้นให้คือ backend:

```python
# backend/app/routers/checkins.py
if not face_detected and not emp.is_manager:
    raise HTTPException(status_code=422, detail="ไม่พบใบหน้า/liveness ไม่ผ่าน เช็คอินไม่ได้")
```

พนักงานทั่วไปยังต้องสแกนหน้าทุกครั้งเหมือนเดิม และ **เงื่อนไขพิกัด (geofence)
ยังบังคับกับหัวหน้าเหมือนกันทุกประการ** — อยู่นอกเขตก็ยังลงเวลาไม่ได้

> ต้อง deploy backend ตัวใหม่ก่อน ไม่งั้นหัวหน้าจะกดยืนยันแล้วโดน 422
> "ไม่พบใบหน้า/liveness ไม่ผ่าน"

## บั๊กที่แก้ไปพร้อมกัน (มีผลทั้งสองแอป)

| อาการ | สาเหตุจริง | ที่แก้ |
| --- | --- | --- |
| แผนที่ติดตามเป็นพื้นเทาว่างเปล่า ไม่มีถนน ไม่มีวงเขต | ทุกคนอยู่จุดใกล้กันมาก `CameraFit.bounds` จึงคำนวณซูมได้ถึง **24** แต่ OSM มี tile ถึงแค่ 19 เหลือ tile เดียวถูกขยาย 32 เท่า และวงเขต 200 ม. ก็ใหญ่เกินจอจนไม่เห็นขอบ | `screens/tabs/live_map_tab.dart` — `MapOptions(maxZoom: 18)` + `CameraFit.bounds(maxZoom: 17)` |
| ช่องวันในปฏิทินขึ้นแถบเหลือง-ดำ "RenderFlex OVERFLOWED" ทุกช่อง (58 ครั้ง/จอ) | ป้าย `Tag` กว้างกว่าช่อง (ช่องกว้าง 1/7 จอ) และ `Column` ในช่องสูงกว่าที่มี | `widgets/app_forms.dart` — `Tag` ย่อข้อความด้วย `…`, เพิ่มโหมด `dense` สำหรับที่แคบ · `widgets/month_calendar.dart` — `OverflowBox` + `ClipRect` |
| หน้าล็อกอินล้น 56px ตอนคีย์บอร์ดเด้งขึ้น | ฟอร์มอยู่ใน `Center` ที่เลื่อนไม่ได้ | `screens/login_screen.dart` — `LayoutBuilder` + `SingleChildScrollView` (ยังจัดกลางจอเมื่อพื้นที่พอ) |

`errorTileCallback` ถูกใส่ไว้ถาวรในทั้งสองแอปแล้ว — คราวหน้าถ้าแผนที่ว่างอีกจะเห็นสาเหตุใน log ทันที
แทนที่จะเงียบเหมือนเดิม

## รันและ build

```bash
cd checkin-system/flutter_boss_app
flutter pub get
flutter run -d <device-id>          # ลงเครื่องแบบ debug
flutter build apk --release         # ได้ build/app/outputs/flutter-apk/app-release.apk
```

ทดสอบ: `flutter analyze` + `flutter test` (68 เทสต์ ใช้ชุดเดียวกับแอปพนักงาน)

## ไอคอนแอป

ตอนนี้ยังใช้ไอคอนชุดเดียวกับแอปพนักงาน ถ้าจะเปลี่ยนเป็นโลโก้หัวหน้า:

1. วางไฟล์โลโก้ทับที่ `assets/icon/app-icon.png` (สี่เหลี่ยมจัตุรัส ≥ 512×512)
   และ `assets/icon/app-icon-foreground.png` (โลโก้ย่อให้อยู่ในโซนปลอดภัย)
2. `flutter pub get && dart run flutter_launcher_icons`
3. build ใหม่

## โค้ดที่ใช้ร่วมกับแอปพนักงาน

โปรเจกต์นี้ **คัดลอกโค้ดมาทั้งชุด** ไม่ได้ import ข้ามโปรเจกต์ ดังนั้น
งานที่แก้ตรรกะร่วม (`models/`, `services/api_service.dart`,
`services/team_status.dart`, `widgets/`) **ต้องแก้ทั้งสองที่**
ไฟล์ที่ต่างกันจริง ๆ มีแค่:

- `lib/main.dart` — ชื่อแอป/คลาส
- `lib/screens/login_screen.dart` — กันบัญชีที่ไม่ใช่หัวหน้า
- `lib/screens/checkin_screen.dart` — หน้ายืนยันแบบไม่มีกล้อง
- `lib/screens/tabs/checkin_tab.dart`, `lib/screens/tabs/profile_tab.dart` — ตัดการลงทะเบียนใบหน้า
- `pubspec.yaml`, `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`
- ไฟล์ที่ถูกลบ: `widgets/face_scanner.dart`, `screens/face_enroll_screen.dart`, `services/face_service.dart`
