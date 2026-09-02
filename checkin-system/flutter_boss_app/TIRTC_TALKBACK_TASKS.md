# งานส่งต่อ Flutter: กดค้างเพื่อพูดออกลำโพง iCam365 ผ่าน TiRTC

**วันที่สรุป:** 2 ก.ย. 2026  
**ผู้รับงาน:** ทีม Flutter (`flutter_boss_app`)  
**สถานะ backend:** ทำเสร็จและทดสอบแล้ว  
**ตัวบล็อกของจริง:** ต้องได้ TiRTC credential และสิทธิ์เชื่อมกล้องตัวปัจจุบันจาก Tange

## เป้าหมาย

เพิ่มปุ่ม **“กดค้างเพื่อพูด”** ในแท็บกล้องของแอปหัวหน้า เมื่อกดค้าง แอปขอ
connection token อายุสั้นจาก backend แล้วใช้ Tange TiRTC Flutter SDK ส่งเสียง
ไมโครโฟนตรงไปยังลำโพง iCam365 เมื่อปล่อยปุ่มต้องหยุดไมค์และตัด connection ทันที

โฟลที่ต้องทำคือ:

```text
Flutter boss app ── POST /camera/talkback/token ──> Python backend
       │                      (ตรวจว่าเป็นหัวหน้า + เซ็น token)
       │
       └── Tange TiRTC SDK / encrypted P2P ───────> iCam365 speaker
```

**ห้าม** ทำ WebSocket ส่ง raw audio เข้า Python และ **ห้าม** ใส่
`CAMERA_TIRTC_SECRET_KEY_ID` ใน Flutter เพราะ TiRTC SDK จัดการ codec,
encryption และ P2P ให้อยู่แล้ว ส่วน secret ต้องอยู่ backend เท่านั้น

## สิ่งที่ backend ทำไว้แล้ว

### `GET /camera/status`

เพิ่มฟิลด์ต่อไปนี้โดยไม่ทำให้แอปรุ่นเก่าพัง:

```json
{
  "talkback_supported": true,
  "talkback_ready": true,
  "talkback_transport": "tirtc",
  "talkback_token_path": "/camera/talkback/token",
  "talkback_stream_id": 14,
  "talkback_note": null
}
```

- ใช้ `talkback_ready == true && talkback_transport == "tirtc"` เป็นเงื่อนไข
  แสดงปุ่มพูด
- `talkback_supported` อย่างเดียวไม่พอ เพราะอาจหมายถึงกล้องรองรับ RTSP
  backchannel แต่ระบบเรายังไม่มี transport แบบนั้น
- ถ้า `talkback_ready == false` ให้แสดง `talkback_note` และไม่เปิดไมค์

### `POST /camera/talkback/token`

- ต้องแนบ JWT เดิมใน `Authorization: Bearer ...`
- จำกัดด้วย `require_manager`; พนักงานทั่วไปได้ HTTP 403
- ไม่รับ `remote_id` จาก client เป้าหมายถูกล็อกใน `.env` ของ backend
- ถ้าปิด TiRTC หรือตั้งค่าไม่ครบได้ HTTP 503 พร้อม `detail` ภาษาไทย
- response มี `Cache-Control: no-store` และ `Pragma: no-cache`

ตัวอย่าง response:

```json
{
  "provider": "tirtc",
  "app_id": "<AppId>",
  "remote_id": "<device_id>",
  "token": "v1.<payload>.<signature>",
  "issued_at": 1788355200,
  "expires_at": 1788355320,
  "stream_id": 14,
  "audio_codec": "g711a",
  "sample_rate_hz": 16000,
  "channels": 1
}
```

ให้ขอ token ใหม่ทุกครั้งที่เริ่มพูด/เชื่อมใหม่ ห้ามเก็บใน
`SharedPreferences`, log, analytics หรือ crash report

## งานที่ต้องทำใน Flutter

### 1. เพิ่ม TiRTC SDK

ใน `pubspec.yaml`:

```yaml
dependencies:
  tirtc_flutter: 2.3.1
```

Android ต้องเพิ่ม Maven repository ตามคู่มือ Tange ในตำแหน่งที่เข้ากับ
`android/settings.gradle.kts` ของโปรเจกต์:

```kotlin
maven {
    url = uri("http://repo-sdk.tange-ai.com/repository/maven-public/")
    isAllowInsecureProtocol = true
    credentials {
        username = "tange_user"
        password = "tange_user"
    }
}
```

อย่าย้ายหรืออัปเกรด dependency ที่ถูกตรึงไว้เดิม (`just_audio`,
`audio_session`, `path_provider_android`) ระหว่างงานนี้โดยไม่จำเป็น

### 2. เพิ่มสิทธิ์ไมโครโฟน

เพิ่มใน `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

ใช้ `permission_handler` ที่มีอยู่แล้วขอ `Permission.microphone` ตอนผู้ใช้กดพูด
ครั้งแรกเท่านั้น ถ้าปฏิเสธให้ขึ้นข้อความพร้อมปุ่มไป App Settings; ห้ามเริ่ม
TiRTC audio input ก่อน permission เป็น `granted`

### 3. เพิ่ม model และ API

แก้ `lib/models/camera.dart`:

- `CameraStatus.talkbackReady`
- `CameraStatus.talkbackTransport`
- `CameraStatus.talkbackTokenPath`
- `CameraStatus.talkbackStreamId`
- model ใหม่ `CameraTalkbackSession` ให้ parse response ของ token endpoint

แก้ `lib/services/api_service.dart`:

```dart
static Future<CameraTalkbackSession> createCameraTalkbackSession()
```

ให้เรียก `POST /camera/talkback/token` ผ่านตัวกลาง `_jsonMap` เดิม เพื่อได้การ
เช็ก session, JWT, 401 และข้อความ `detail` แบบเดียวกับ API อื่น

### 4. สร้าง service ครอบ TiRTC

แนะนำสร้าง `lib/services/camera_talkback_service.dart` เพื่อไม่เอา lifecycle
ของ SDK ไปกองใน widget โดยตรง service ต้องรับผิดชอบ:

1. ขอ `CameraTalkbackSession` ใหม่
2. `TiRtc.initialize(TiRtcInitOptions(appId: session.appId))` เพียงครั้งเดียว
3. สร้าง `TiRtcConn` และตั้ง `onStateChanged`
4. `connect(remoteId: session.remoteId, token: session.token)`
5. รอ state `connected` โดยมี timeout และรองรับ cancel
6. สร้าง `TiRtcAudioInput`
7. ตั้งค่าตาม response/API contract
8. attach กับ connection และ `session.streamId`
9. เรียก `start()`
10. ตอนหยุด: `stop → detach → dispose audio input → disconnect → dispose conn`

ค่าตามคู่มือทางการ:

```dart
const TiRtcAudioInputOptions(
  codec: TiRtcAudioCodec.g711a,
  sampleRate: TiRtcAudioSampleRate.rate16k,
  channels: TiRtcAudioChannelCount.mono,
  aecMode: TiRtcAudioAecMode.enabled,
)
```

เมธอดอย่างน้อย:

```dart
Future<void> start();
Future<void> stop();
Future<void> dispose();
```

`stop()` และ `dispose()` ต้องเรียกซ้ำได้โดยไม่ throw และต้อง cleanup ทรัพยากร
ที่สร้างไปแล้วแม้ขั้นตอน connect/attach/start จะล้มกลางทาง

### 5. ทำปุ่มกดค้างใน `camera_tab.dart`

เพิ่มปุ่มใต้ “ฟังเสียงจากกล้อง”:

- idle: `กดค้างเพื่อพูด`
- ขอ permission/token/ต่อ SDK: `กำลังเชื่อมต่อไมค์...`
- กำลังส่งเสียง: `กำลังพูด — ปล่อยเพื่อหยุด`
- error: แสดงข้อความไทยและกลับมากดใหม่ได้

ใช้ gesture แบบ press-and-hold ไม่ใช่แตะเปิดค้าง:

- `onLongPressStart` → เริ่ม flow
- `onLongPressEnd` / `onLongPressCancel` → หยุดและ cleanup

กรณีผู้ใช้ปล่อยนิ้วระหว่างยังขอ token หรือกำลัง connect ต้องตั้ง cancel flag
ไว้ เมื่อ async step กลับมาต้องไม่เริ่มไมค์ต่อ และต้องปิด connection ที่สร้างแล้ว

เพื่อกันเสียงหอน/feedback ถ้ากำลัง “ฟังเสียงจากกล้อง” อยู่ ให้หยุด
`just_audio` ก่อนเริ่มพูด ไม่ต้องเปิดฟังกลับเองหลังปล่อยปุ่มจนกว่าผู้ใช้จะกดฟังใหม่

### 6. Lifecycle และความปลอดภัย

ต้องหยุด talkback ทันทีเมื่อเกิดอย่างใดอย่างหนึ่ง:

- ปล่อยนิ้วหรือ gesture ถูก cancel
- แอปเข้า `inactive`, `paused`, `detached` หรือถูกย่อ
- สลับออกจากแท็บกล้อง
- logout/session หมดอายุ
- widget/service dispose
- SDK connection error หรือ timeout

ห้ามอนุญาตไมค์ทำงานต่อเบื้องหลัง แม้ฟีเจอร์ “ฟังเสียงจากกล้อง” เดิมจะยอมให้
เล่นต่อเมื่อย่อแอปก็ตาม

ห้าม log ค่า `token`, JWT หรือข้อมูล credential ทุกชนิด log ได้เฉพาะ error code,
state และ `TiRtc.errorToString(code)`

## เทสต์ที่ต้องเพิ่ม

เพิ่ม widget/unit tests อย่างน้อย:

- parse status/response ใหม่โดยไม่ทำให้ JSON จาก backend รุ่นเก่าพัง
- `talkback_ready=false` ไม่แสดงปุ่มกดพูด และแสดง `talkback_note`
- ready + transport `tirtc` แสดงปุ่ม
- ปฏิเสธ permission แล้วไม่เรียก token/SDK
- ปล่อยนิ้วก่อน connect สำเร็จแล้วไมค์ไม่เริ่ม
- ปล่อยนิ้วหลังเริ่มแล้วเรียก cleanup ครบ
- SDK error/timeout กลับสู่ idle และกดใหม่ได้
- ย่อแอปหรือสลับแท็บระหว่างพูดแล้วหยุดทันที
- กำลังฟังเสียงอยู่ แล้วเริ่มพูด ต้อง dispose player ฟังก่อน

ควร inject adapter/interface ครอบ SDK เพื่อใช้ fake ในเทสต์ อย่าเรียก native
TiRTC จริงจาก widget test

คำสั่งตรวจ:

```powershell
flutter analyze
flutter test
flutter build apk --release
```

## เกณฑ์รับงานบนกล้องจริง

- [ ] บัญชีหัวหน้าเห็นปุ่มเมื่อ backend ตอบ `talkback_ready=true`
- [ ] ขอ permission ไมค์เฉพาะตอนเริ่มใช้ครั้งแรก
- [ ] กดค้างและพูดแล้วลำโพงกล้องได้ยินชัด
- [ ] ปล่อยปุ่มแล้วเสียงหยุดและสัญลักษณ์ไมค์ของ Android ดับ
- [ ] ปล่อยก่อนต่อสำเร็จแล้วไม่มีเสียงหลุดไปภายหลัง
- [ ] ย่อแอป/สลับแท็บ/เน็ตหลุดแล้วไมค์หยุดเสมอ
- [ ] กดซ้ำหลายรอบไม่เกิด connection หรือ audio input ค้าง
- [ ] APK ไม่มี `SecretKeyId` และ log ไม่มี token

## สิ่งที่ต้องได้จาก Tange ก่อนทดสอบจริง

ส่งอีเมล `business@tange.ai` ขอ:

- `AppId`
- `AccessKeyId`
- `SecretKeyId`
- `device_id`/`remote_id`
- ยืนยันว่ากล้อง iCam365 retail ตัวปัจจุบันถูก authorize ให้เชื่อมจาก TiRTC
  client SDK ของแอปเราได้ ไม่ใช่ credential สำหรับ test device คนละตัวเท่านั้น

ค่าทั้งหมดให้ทีม server ใส่ใน `backend/.env`; ทีม Flutter ต้องได้รับเพียง API
contract นี้ ไม่ต้องรับ `SecretKeyId`

เอกสารทางการ:

- [สมัครเปิด TiRTC](https://docs.tange.ai/products/tirtc/get-started/apply-for-access.html)
- [ติดตั้ง Flutter SDK](https://docs.tange.ai/products/tirtc/guides/sdk-integration/flutter.html)
- [เชื่อมอุปกรณ์และออก token](https://docs.tange.ai/products/tirtc/guides/connection.html)
- [Voice Talkback](https://docs.tange.ai/products/tirtc/guides/voice-talkback.html)

