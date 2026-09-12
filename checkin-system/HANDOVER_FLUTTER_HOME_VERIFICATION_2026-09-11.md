# ส่งต่องานฝั่งแอป — ยืนยันตัวตนรายวันตอนอยู่บ้าน (Flutter)

> **วันที่:** 11 กันยายน 2026
> **ถึง:** ทีมพัฒนาแอป Flutter (`flutter_app` = พนักงาน, `flutter_boss_app` = หัวหน้า)
> **ข้อกำหนดต้นทาง:** `DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` (อ่านหัวข้อ 2, 5, 9, 10 ก่อนเริ่ม)

---

## ⚠️ สถานะล่าสุด — งานฝั่งแอปทำเสร็จแล้ว (อัปเดตเย็น 11 ก.ย. 2026)

เอกสารนี้เขียนขึ้นตอนที่ฝั่งแอปยังไม่เริ่ม **แต่ตอนนี้ทำเสร็จและทดสอบบนเครื่องจริงแล้ว**

| ส่วน | สถานะ |
|---|---|
| แอปพนักงาน `1.6.0+8` | ✅ เสร็จ |
| แอปหัวหน้า `1.3.0+5` | ✅ เสร็จ (พอร์ตชุดกล้อง/สแกนหน้าเข้าไปครบ) |
| ทดสอบบน MTN NX1 | ✅ ผ่านครบวงจร |
| deploy ขึ้น production | ❌ **ยังไม่ได้ทำ** — ดูหัวข้อ 7.2 |

**รายละเอียดสิ่งที่ทำจริงอยู่ที่ `DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` หัวข้อ 17**

เอกสารนี้ยังมีประโยชน์ในฐานะ **คู่มืออ้างอิงสัญญา API + กฎธุรกิจ + เกณฑ์ทดสอบ** (หัวข้อ 2, 3, 6, 8) สำหรับคนที่มาแก้ต่อ — แต่หัวข้อ 4, 5 ที่บอกว่า "ต้องสร้าง/ต้องพอร์ต" **ทำไปแล้ว** อย่าทำซ้ำ

---

## ⚡ อ่าน 60 วินาที

| # | เรื่อง | สรุป |
|---|---|---|
| 1 | **โจทย์** | ทุกวันที่ไม่ได้ไปทำงาน ผู้ใช้ต้อง**สแกนใบหน้าสด + อยู่ในเขตบ้าน** จึงจะยืนยันสถานะ "อยู่บ้าน / ไม่ได้ไปทำงาน" ได้ |
| 2 | **backend พร้อมแล้ว** | 5 endpoint ใต้ `/home-verifications` ใช้ได้จริง ผ่าน 29 tests — สัญญาอยู่หัวข้อ 3 |
| 3 | **งานของทีมแอป** | ทำหน้ายืนยันบ้าน + service + model **ในทั้ง 2 แอป** และย้ายรายการบ้านออกจาก `POST /checkins` |
| 4 | **งานหนักสุด** | **แอปหัวหน้าไม่มีกล้อง/สแกนหน้าเลย** ต้องพอร์ตทั้งชุดเข้าไป ดูหัวข้อ 5 |
| 5 | **กฎเหล็ก** | อยู่บ้าน **ไม่มีเวลาเข้า-ออก ไม่มีสาย/ตรงเวลา ไม่มีชั่วโมงทำงาน** · **หัวหน้าก็ต้องสแกน ไม่มีข้อยกเว้น** |
| 6 | **ตัวบล็อกก่อนทดสอบ** | backend ยัง**ไม่ได้ deploy ขึ้น production** — ต้องรันเองบนเครื่อง ดูหัวข้อ 7 |

**ลำดับที่แนะนำ:** อ่านหัวข้อ 3 (สัญญา API) → ทำ model+service (หัวข้อ 4) → หน้าจอในแอปพนักงาน (หัวข้อ 4.3) → พอร์ตกล้องเข้าแอปหัวหน้า (หัวข้อ 5) → เทส (หัวข้อ 8) → build (หัวข้อ 9)

---

## 1. ทำไมต้องมีของใหม่ ทั้งที่เดิมก็กด "อยู่บ้าน" ได้อยู่แล้ว

ของเดิมแอปส่ง `POST /checkins` ด้วย `kind=in` แล้วให้ server เดาจากพิกัดว่าเป็นบ้าน ปัญหาคือ:

| ปัญหาของเส้นทางเดิม | ของใหม่แก้ยังไง |
|---|---|
| แอปส่ง `face_detected=true` มาเอง — server เชื่อ client | endpoint ใหม่ **ไม่มีฟิลด์นี้เลย** ต้องแนบรูปจริง |
| **บัญชีหัวหน้าถูกยกเว้นการตรวจใบหน้า** (`if not face_detected and not emp.is_manager`) | endpoint ใหม่ **ไม่ยกเว้นใคร** |
| ส่งรูปเก่า/รูปเดิมซ้ำได้ | ผูกกับ challenge อายุสั้นใช้ครั้งเดียว + ไบต์รูปห้ามซ้ำทั้งระบบ |
| เน็ตหลุดแล้วกดซ้ำ = ได้ 2 รายการ | `request_id` กันซ้ำ ส่งซ้ำได้รายการเดิม |
| รายการบ้านอยู่ตาราง `checkins` เดียวกับงาน เสี่ยงหลุดเข้าสูตรเวลางาน | แยกตาราง `home_verifications` ต่างหาก |

> ⚠️ **`POST /checkins` ของเดิมไม่ถูกแตะ** ยังทำงานเหมือนเดิมทุกอย่าง แอปรุ่นเก่าจึงไม่พัง
> แต่**รายการบ้านที่ยิงผ่าน `/checkins` จะไม่ถือว่าผ่านการยืนยันแบบใหม่**

---

## 2. กฎที่ห้ามพลาด (ย่อจากข้อกำหนดต้นทาง)

1. **อยู่บ้าน = ไม่ได้ไปทำงาน** → ไม่มีเวลาเข้างาน ไม่มีเวลาออกงาน ไม่ต้องกดออกงาน
2. **ห้ามแสดงป้ายใด ๆ ที่สื่อเวลางาน** ในการ์ด/ประวัติของรายการบ้าน — สาย, ตรงเวลา, มาก่อนเวลา, ออกก่อนเวลา, ครบเวลางาน, ทำงานเกินเวลา
3. **ห้ามมีช่องเวลาเข้า–ออกแม้เป็นช่องว่างหรือขีด** ในสรุปสถานะบ้าน
4. ถ้าจะโชว์เวลา ให้เรียกว่า **"เวลายืนยันตัวตน"** เท่านั้น ห้ามเรียกเวลาเข้างาน
5. **ยืนยันใหม่ทุกครั้ง = ขอ challenge ใหม่ + สแกนใหม่** ห้ามใช้ผลเดิม/รูปลงทะเบียน/ผลเมื่อวาน
6. **เปิดหน้าประวัติ เปลี่ยนแท็บ เปิดแชท → ไม่ต้องสแกน และไม่สร้างรายการ**
7. **login อย่างเดียวไม่ใช่การยืนยัน** และ **มีรูปลงทะเบียนแล้วก็ไม่ใช่การยืนยัน**
8. **บัญชีหัวหน้าที่รายงานสถานะตัวเอง ต้องสแกนเหมือนพนักงาน**
9. โหลดผลไม่ได้ → แสดง "ยังตรวจสอบผลการยืนยันไม่ได้" **ห้ามสรุปว่าผู้ใช้ไม่รับผิดชอบ**
10. ใช้ **วันจาก server** (`server_date`) จัดกลุ่มรายวัน ห้ามเชื่อนาฬิกาเครื่อง

---

## 3. สัญญา API ที่มีจริงแล้ว

Base URL: `https://thanakronpart-time.com` — **ไม่มี `/api` นำหน้า** · ทุก endpoint ต้องมี `Authorization: Bearer <token>`

### 3.1 `POST /home-verifications/challenges` — ขอโจทย์ก่อนเปิดกล้อง

ไม่มี body. ตอบ `200`:

```json
{
  "challenge_id": "0f7c…",
  "action": "หันหน้าไปทางซ้ายช้า ๆ",
  "expires_at": "2026-09-11T08:12:30Z",
  "server_time": "2026-09-11T08:10:30Z",
  "ttl_seconds": 120,
  "timezone": "Asia/Bangkok",
  "face_enrolled": true,
  "evidence": {
    "photo_required": true,
    "formats": ["image/jpeg", "image/png"],
    "min_pixels": 160,
    "max_bytes": 8000000
  }
}
```

- `action` = คำสั่งให้ผู้ใช้ทำตอนสแกน **แสดงบนหน้าจอ** และใช้เป็นโจทย์ liveness ฝั่งอุปกรณ์
  ⚠️ **server ตรวจไม่ได้ว่าทำจริงไหม** (ดูหัวข้อ 6) การบังคับให้ทำตามอยู่ที่แอปล้วน ๆ
- `face_enrolled: false` → **พาไปหน้าลงทะเบียนใบหน้าก่อน** อย่าปล่อยให้สแกนแล้วค่อยโดนปฏิเสธ
- อายุแค่ 120 วิ → **ขอ challenge ตอนกดปุ่มเริ่ม ไม่ใช่ตอนเปิดหน้า**

### 3.2 `POST /home-verifications` — ส่งหลักฐาน (multipart/form-data)

| field | ชนิด | จำเป็น | หมายเหตุ |
|---|---|---|---|
| `request_id` | string ≤36 | ✅ | UUID ที่ **แอปสร้างเอง 1 ค่าต่อ 1 รอบการยืนยัน** และ**เก็บไว้จนรู้ผล** |
| `challenge_id` | string | ✅ | จาก 3.1 |
| `latitude` / `longitude` | float | ✅ | พิกัดสด ณ ตอนส่ง |
| `location_accuracy_m` | float | — | ความแม่นของ GPS |
| `photo` | file | ✅ | **JPEG/PNG เท่านั้น** ด้านสั้น ≥160 px, ≤8 MB |

ตอบ `200` (ใช้รูปแบบเดียวกันทุก endpoint ที่คืนผลการยืนยัน):

```json
{
  "id": 12,
  "request_id": "client-generated-uuid",
  "status": "verified",
  "category": "home",
  "office_name": "ถึงบ้านแล้ว",
  "verified_at": "2026-09-11T08:11:02Z",
  "local_date": "2026-09-11",
  "timezone": "Asia/Bangkok",
  "distance_km": 0.0631,
  "location_accuracy_m": 12.5
}
```

> `verified_at` เป็น **UTC** (ลงท้าย `Z`) → แปลงเป็น `Asia/Bangkok` ก่อนแสดง และเรียกว่า **"เวลายืนยันตัวตน"**
> ✅ ไม่มี `late_minutes` / `expected_check_in` / `expected_check_out` / ชั่วโมงทำงาน / `kind` โดยตั้งใจ — **อย่าเพิ่มเอง**

### 3.3 `GET /home-verifications/requests/{request_id}` — กู้ผลตอนเน็ตหลุด

ตอบ `200` ด้วยรูปแบบเดียวกับ 3.2 หรือ `404 request_not_found`

> ⚠️ **`404` ไม่ได้แปลว่าคำขอแรกล้มเหลวแน่นอน** อาจกำลังประมวลผลอยู่
> ทางที่ปลอดภัยกว่าคือ **ส่ง `POST` ด้วย `request_id` เดิมซ้ำ** — ถ้าบันทึกไปแล้วจะได้รายการเดิมกลับมา

### 3.4 `GET /home-verifications/me?date=YYYY-MM-DD` — สถานะรายวันของตัวเอง

`date` ไม่ส่ง = วันนี้ตามเวลาไทยของ server

```json
{
  "date": "2026-09-11",
  "server_date": "2026-09-11",
  "server_time": "2026-09-11T08:20:00Z",
  "timezone": "Asia/Bangkok",
  "verified": true,
  "verifications": [ { …เหมือน 3.2… } ]
}
```

- ใช้ `verified` ตัดสินว่าวันนี้ยืนยันแล้วหรือยัง
- **เทียบ `server_date` กับวันที่แอปคิดเอง** ถ้าไม่ตรงให้เชื่อ server

### 3.5 `GET /home-verifications/employee/{id}?date=` — หัวหน้าดูของพนักงาน

เฉพาะบัญชี `is_manager` (ไม่ใช่ → `403`) · ตอบเหมือน 3.4 บวก `employee_id`

### 3.6 error ทั้งหมด

ทุก error ตอบรูปแบบเดียวกัน — **ใช้ `code` เลือกวิธีแก้ อย่า match ข้อความ**

```json
{ "detail": { "code": "challenge_expired", "message": "โจทย์การยืนยันหมดอายุแล้ว กรุณาสแกนใหม่" } }
```

| HTTP | `code` | ความหมาย | แอปควรทำ |
|---|---|---|---|
| 401 | — | session หมดอายุ | พาไป login ใหม่ |
| 422 | `request_invalid` | `request_id` ผิดรูปแบบ | bug ฝั่งแอป |
| 422 | `evidence_invalid` | ไฟล์ไม่ใช่รูป / เล็กไป / ใหญ่ไป | ให้สแกนใหม่ |
| 422 | `evidence_reused` | รูปนี้เคยใช้ยืนยันแล้ว | **ถ่ายใหม่** อย่าส่งรูปเดิม |
| 422 | `challenge_invalid` | ไม่พบโจทย์ หรือเป็นของบัญชีอื่น | ขอ challenge ใหม่ |
| 409 | `challenge_used` | โจทย์นี้ใช้ยืนยันไปแล้ว | ขอ challenge ใหม่ + สแกนใหม่ |
| 422 | `challenge_expired` | เกิน 120 วิ | ขอ challenge ใหม่ + สแกนใหม่ |
| 422 | `face_not_enrolled` | ยังไม่มีใบหน้าอ้างอิง | พาไปหน้าลงทะเบียนใบหน้า |
| 422 | `outside_home` | อยู่นอกเขตบ้าน | บอกตามจริง **ห้ามรายงานว่าสำเร็จ** |
| 409 | `request_conflict` | `request_id` เดิมแต่เนื้อหาต่าง | เริ่มรอบใหม่ด้วย `request_id` ใหม่ |
| 404 | `request_not_found` | ยังไม่พบผลคำขอ | ดู 3.3 |
| 422 | `date_invalid` | `date` ไม่ใช่ `YYYY-MM-DD` | bug ฝั่งแอป |

---

## 4. งานในแอป (ทำทั้ง 2 แอป เว้นที่ระบุ)

### 4.1 ไฟล์ใหม่ที่ต้องสร้าง

| ไฟล์ | หน้าที่ |
|---|---|
| `lib/models/home_verification.dart` | โมเดลผลการยืนยัน + parse JSON จาก 3.2 · `verifiedAt` เป็น UTC ที่มี timezone ชัดเจน |
| `lib/services/home_verification_service.dart` | เรียก 4 endpoint + จัดการ error code + เก็บ `request_id` ค้างไว้กู้ผล |
| `lib/screens/home_verification_screen.dart` | หน้าสแกน + ส่ง + หน้าผลสำเร็จ |
| `lib/widgets/home_verification_card.dart` | การ์ดสถานะรายวันบนหน้าแรก |

### 4.2 ไฟล์เดิมที่ต้องแก้

| ไฟล์ | ต้องทำอะไร |
|---|---|
| `lib/services/api_service.dart` | เพิ่มเมธอดใหม่ · **อย่าแปลงผลบ้านเป็นข้อความ "บันทึกเข้างานสำเร็จ"** |
| `lib/screens/tabs/checkin_tab.dart` | แยกปุ่มบ้านออกจากปุ่มเข้างาน · เปิดปุ่ม **"ยืนยันสถานะอีกครั้ง"** หลังมีรายการแล้ว (ตอนนี้โค้ดปิดปุ่มถาวรที่ `onPressed: homeRecordedAt == null ? … : null`) · ปิดปุ่มเฉพาะระหว่างส่ง |
| `lib/widgets/today_attendance_card.dart` | การ์ดบ้านแสดงผลยืนยัน+สถานที่ **ไม่มีช่องเวลาเข้า–ออกแม้เป็นขีด** |
| `lib/screens/checkin_screen.dart` | แยกบริบทบ้านกับงานตั้งแต่ต้นจนหน้าสำเร็จ (ตอนนี้ยังมีข้อความเข้างาน/ออกงานปนอยู่) |
| `lib/services/attendance_service.dart` | คงการแยก `homeRecords`/`workRecords` · ไม่จับคู่บ้านเป็นรอบงาน |
| `lib/services/work_schedule.dart` | **คงการข้ามบ้าน** ห้ามส่งรายการบ้านเข้าสูตรสาย/ชั่วโมงทำงาน |
| `lib/services/location_service.dart` | โหลดพื้นที่จาก server ใช้ `category=home` · ให้ server ตัดสินขั้นสุดท้าย |

### 4.3 state machine ที่ต้องทำ

```text
loading → unverified / verified / loadFailed
unverified หรือ verified → preparing → scanning → submitting → verified
preparing หรือ scanning → blocked / cancelled
submitting → rejected / resultUnknown
resultUnknown → ตรวจด้วย request_id เดิม → verified / rejected / รอตรวจต่อ
```

| state | เงื่อนไข | ต้องทำ |
|---|---|---|
| `loadFailed` | โหลด `/me` ไม่ได้ | "ยังตรวจสอบผลการยืนยันไม่ได้" + ปุ่มลองใหม่ · **ห้าม**แสดงว่ายังไม่ยืนยัน |
| `blocked` | กล้อง/GPS ถูกปฏิเสธ, นอกเขตบ้าน | บอกสาเหตุ + ทางไปตั้งค่า |
| `rejected` | server ปฏิเสธแน่นอน | แสดงตาม `code` แล้วให้เริ่มรอบใหม่ |
| `resultUnknown` | timeout/เน็ตหลุด**หลังส่ง** | **เก็บ `request_id` ไว้** แล้วกู้ผลตาม 3.3 · ห้ามบอกว่าล้มเหลว |

### 4.4 เรื่อง lifecycle ที่มักพลาด

- แอปถูกพักระหว่างสแกน → **หยุดกล้องและทิ้งหลักฐานที่ยังไม่ส่ง** กลับมาเริ่มรอบใหม่
- แต่ถ้า**ส่งไปแล้ว**ยังไม่รู้ผล → **รักษา `request_id` ไว้** เพื่อกู้ผลเดิม
- ออกจากหน้า → `dispose()` กล้องและ subscription, เช็ค `mounted` ก่อน `setState`
- **logout → ล้าง `request_id` และหลักฐานค้างทั้งหมด** สลับบัญชีแล้วต้องไม่เห็นของบัญชีก่อน
- **ห้ามเขียน token / รูปใบหน้า / หลักฐาน ลง log** และล้างไฟล์กล้องชั่วคราวหลังส่ง

### 4.5 ตัวอย่างการยิง multipart (ตามแบบที่โปรเจ็กต์ใช้อยู่)

อิงรูปแบบเดียวกับ `ApiService.checkIn()` ที่ `api_service.dart:455`

```dart
final req = http.MultipartRequest('POST', _uri('/home-verifications'))
  ..headers.addAll(_authHeaders)
  ..fields['request_id'] = requestId      // เก็บไว้ก่อนส่ง กู้ผลได้ถ้าเน็ตหลุด
  ..fields['challenge_id'] = challengeId
  ..fields['latitude'] = lat.toString()
  ..fields['longitude'] = lng.toString();
if (accuracyM != null) req.fields['location_accuracy_m'] = accuracyM.toString();
req.files.add(await http.MultipartFile.fromPath('photo', photo.path));
```

อ่าน error code:

```dart
final body = jsonDecode(utf8.decode(res.bodyBytes));
final code = (body['detail'] is Map) ? body['detail']['code']?.toString() : null;
```

---

## 5. ⚠️ งานเฉพาะแอปหัวหน้า — ต้องพอร์ตกล้องเข้าไปทั้งชุด

`flutter_boss_app` **ไม่มีความสามารถสแกนใบหน้าเลย** ตรวจแล้วขาดครบทุกชั้น:

### 5.1 dependency ที่ขาดใน `pubspec.yaml`

```yaml
  camera: ^0.10.6
  google_mlkit_face_detection: ^0.11.0
```

> ⚠️ เพิ่มแล้ว**ต้องลอง `flutter build apk --release` ทันที** — โปรเจ็กต์นี้ตรึง `path_provider_android: 2.2.23`, `just_audio: 0.9.46`, `audio_session: 0.1.25` ไว้เพราะชนกับ AGP อยู่แล้ว (อ่านคอมเมนต์ยาวใน `pubspec.yaml`) แพ็กเกจใหม่อาจลากเวอร์ชันที่ชนเพิ่ม
> แอปหัวหน้ามี `tirtc_flutter: 2.3.1` (native lib ของ TiRTC) ซึ่งแอปพนักงานไม่มี — **การชนกันอาจไม่เหมือนกัน**

### 5.2 permission ที่ขาด

- `android/app/src/main/AndroidManifest.xml` → **ไม่มี `android.permission.CAMERA`** ต้องเพิ่ม
  (มี `RECORD_AUDIO` อยู่แล้วจากฟีเจอร์ไมค์พูดออกกล้อง)
- `ios/Runner/Info.plist` → **ไม่มี `NSCameraUsageDescription`** ต้องเพิ่มถ้าจะส่ง iOS

### 5.3 ไฟล์ที่ต้องพอร์ตจากแอปพนักงาน

| ไฟล์ต้นทาง | บรรทัด | หมายเหตุ |
|---|---|---|
| `flutter_app/lib/widgets/face_scanner.dart` | 249 | widget `FaceScanner` รับ `confirmLabel` + `onCapture` |
| `flutter_app/lib/services/face_service.dart` | 90 | `analyze()` คืน `(faceFound, livenessOk)` ผ่าน ML Kit |
| `flutter_app/lib/screens/face_enroll_screen.dart` | 111 | หน้าลงทะเบียนใบหน้าอ้างอิง (จำเป็น เพราะ `face_not_enrolled` จะบล็อกหัวหน้าด้วย) |

> 💡 **ทางเลือกที่ควรพิจารณา:** แทนที่จะก๊อป 3 ไฟล์ไปไว้ 2 ที่แล้วต้องแก้ 2 รอบตลอดไป ให้ยกเป็น **shared package** (เช่น `packages/checkin_face/`) แล้วให้ทั้งสองแอป `path:` เข้าไป — ข้อกำหนดต้นทางหัวข้อ 9.1 เปิดทางเลือกนี้ไว้แล้ว
> ถ้าเลือกก๊อป ให้จดไว้ในเอกสารว่า**ต้องแก้ 2 ที่เสมอ** (โปรเจ็กต์นี้มีปัญหานี้อยู่แล้วกับ `work_schedule.dart` ที่ต้องตรงกัน 3 ที่)

### 5.4 อย่าลืม

เส้นทางส่ง check-in เดิมของแอปหัวหน้าส่ง `faceDetected: false` อยู่ — **ห้ามยกเว้นด้วยบทบาทหัวหน้าใน flow บ้าน** backend ไม่ยกเว้นให้แล้ว ถ้าแอปไม่แนบรูปจะโดนปฏิเสธทันที

---

## 6. ⚠️ ข้อจำกัดของ backend ที่ต้องรู้ก่อนออกแบบ UI

verifier ฝั่ง server ตกลงขอบเขตไว้ที่ **กันปลอม/กันใช้ซ้ำ ไม่ทำ face matching**

| server ตรวจได้ | server ตรวจ**ไม่ได้** |
|---|---|
| หลักฐานถูกส่งในรอบนี้ ไม่ใช่ของเก่า | ❌ ใบหน้าในรูปเป็นเจ้าของบัญชีจริงไหม |
| ไฟล์เป็นรูป JPEG/PNG จริงและใหญ่พอ | ❌ **ในรูปมีใบหน้าอยู่ไหม** |
| อยู่ในเขตบ้านตามพิกัดที่ส่งมา | ❌ ทำตาม `action` (หันซ้าย/กะพริบตา) จริงไหม |

**แปลว่า:** liveness และการมีใบหน้าจริง **ยังพึ่งฝั่งแอปทั้งหมด** → `FaceService.analyze()` ต้องผ่านก่อนถึงจะส่งขึ้น server และ**อย่าส่งรูปที่ผู้ใช้เลือกจากแกลเลอรี**

> ถ้าภายหลังตัดสินใจทำ face matching 1:1 จริง จุดต่อขยายอยู่ที่ `verify_evidence()` ใน `backend/app/home_verification.py` — **สัญญา API ไม่เปลี่ยน แอปไม่ต้องแก้**

---

## 7. 🔴 ตัวบล็อก — backend ยังไม่ขึ้น production

โค้ด backend อยู่บนเครื่อง dev เท่านั้น ยิง `https://thanakronpart-time.com/home-verifications/me` ตอนนี้จะ **404**

### 7.1 ทดสอบระหว่างรอ deploy — รัน backend เองบนเครื่อง

```powershell
cd checkin-system\backend
.\venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8002
```

แล้วชี้แอปมาที่เครื่องตัวเอง **โดยไม่ต้องแก้ `config.dart`**:

```powershell
adb reverse tcp:8002 tcp:8002
flutter run --dart-define=API_BASE=http://localhost:8002
```

### 7.2 สิ่งที่ทีม deploy ต้องทำ (ไม่ใช่งานทีมแอป แต่ต้องรู้ว่าติดตรงไหน)

1. `git pull` บนเครื่อง production
2. **คัดลอก `deploy/windows-server/web.config` ตัวใหม่ขึ้น IIS ด้วย** — เติม `home-verifications` ในกฎ `ProxyToBackend` แล้ว **ถ้าลืมข้อนี้ endpoint จะ 404 ทั้งที่ backend มีแล้ว**
3. `Start-ScheduledTask -TaskName MardodiCheckinAPI` (restart backend)
4. ตาราง `home_verifications` / `home_verification_challenges` **สร้างเองอัตโนมัติ** ตอนสตาร์ต ไม่ต้องรัน migration
5. ตรวจ: `curl https://thanakronpart-time.com/home-verifications/me` ต้องได้ **401 ไม่ใช่ 404**

---

## 8. เกณฑ์ตรวจรับก่อนส่งงาน

ทำเป็น test จริงตามความเสี่ยง: unit test (โมเดล/วันไทย/แยกบ้านออกจากงาน), widget test (ข้อความ/ปุ่ม), integration test (กล้อง/GPS/เน็ตหลุด)

| # | กรณี | ผลที่ต้องได้ |
|---|---|---|
| 1 | ยืนยันตอนเช้า บ่าย หรือกลางคืน | ผลเหมือนกันหมด **ไม่มีสาย/ตรงเวลา/เวลาเข้า–ออก/ชั่วโมงทำงาน** |
| 2 | การ์ดบ้าน + ประวัติ | ไม่มีช่องเข้า–ออกแม้เป็นขีด · timestamp เรียก "เวลายืนยันตัวตน" |
| 3 | login อย่างเดียว | ไม่กลายเป็นยืนยันสำเร็จ |
| 4 | มีรูปลงทะเบียนแล้ว | ไม่กลายเป็นยืนยันสำเร็จ |
| 5 | **บัญชีหัวหน้ายืนยันบ้าน** | ต้องสแกนสดเหมือนพนักงาน |
| 6 | ยืนยันซ้ำในวันเดิม | ปุ่มเปิดได้ ต้องขอ challenge ใหม่ + สแกนใหม่ |
| 7 | เปิดหน้าซ้ำ/เปิดแชท | ไม่บังคับสแกน ไม่เพิ่มรายการ |
| 8 | ส่งรูปเดิมซ้ำ | ได้ `evidence_reused` แล้วให้ถ่ายใหม่ |
| 9 | GPS ปิด / นอกเขตบ้าน | บอกสาเหตุ **ไม่รายงานสำเร็จ** |
| 10 | เน็ตหลุดหลังส่ง แล้วกดซ้ำ | **เหลือรายการเดียว** และไม่บอกว่าล้มเหลวทั้งที่ยังไม่รู้ผล |
| 11 | ปิด-เปิดแอประหว่างรอผล | กู้ผลด้วย `request_id` เดิมได้ |
| 12 | ตั้งเวลาเครื่องผิด / ส่งข้ามเที่ยงคืน | อิง `server_date` ไม่ใช้รายการเมื่อวานแทนวันนี้ |
| 13 | อยู่บ้านแล้วไปสำนักงานวันเดียวกัน | แสดง 2 เหตุการณ์แยกกัน เวลางานนับจากสำนักงานเท่านั้น |
| 14 | logout แล้วสลับบัญชี | ไม่เห็นผล/หลักฐาน/คำขอค้างของบัญชีก่อน |
| 15 | backend ยังไม่พร้อม (404/401) | แสดง error ที่แก้ได้ **ห้าม fallback ไป `/checkins` แล้วบอกว่ายืนยันแล้ว** |

> ข้อ 15 สำคัญมาก: ข้อกำหนดต้นทางหัวข้อ 12 ระบุชัดว่า **ห้าม fallback ไป `face_detected=true` แล้วแสดงว่าผ่านการยืนยันสดแบบใหม่**

---

## 9. ก่อนออก APK

```powershell
# รันในแต่ละโฟลเดอร์ flutter_app และ flutter_boss_app
flutter pub get
flutter analyze          # ต้อง No issues found
flutter test             # ปัจจุบัน: พนักงาน 81 · หัวหน้า 120 — ห้ามน้อยลง
flutter build apk --release
```

- [ ] **bump version** ใน `pubspec.yaml` **และ `lib/config.dart` (`Config.appVersion`)** — โปรเจ็กต์นี้เก็บเวอร์ชันไว้ 2 ที่ ต้องตรงกัน
- [ ] ตรวจเวอร์ชัน+ลายเซ็นใน APK ก่อนส่ง (build-tools 36.1.0):
      `aapt2 dump badging <apk>` · `apksigner verify --print-certs <apk>` → ต้องได้ SHA-256 `41c0464d…9625e269`
- [ ] **ติดตั้งทับ = ผู้ใช้ถูก logout** ต้องแจ้งให้ล็อกอินใหม่
- [ ] publish ด้วย `deploy/windows-server/publish-apk.ps1` **บนเครื่อง production เท่านั้น** แล้วตรวจ `/app/info` + `/boss-app/info` บนโดเมนจริง
- [ ] อัปเดต `DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` หัวข้อ 0 และ 16.4 ว่าข้อใดเสร็จแล้ว

---

## 10. เอกสารและโค้ดที่ควรเปิดคู่กัน

| ไฟล์ | ใช้ดูอะไร |
|---|---|
| `DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` | ⭐ ข้อกำหนดต้นทาง — หัวข้อ 0 (สถานะ), 9–10 (งาน Flutter), 16 (backend ที่ทำแล้ว) |
| `backend/app/routers/home_verifications.py` | ความจริงของสัญญา API (ถ้าเอกสารขัดกับโค้ด **ให้เชื่อโค้ด**) |
| `backend/test_home_verifications.py` | 29 กรณีที่ backend รับประกันไว้ — ใช้เป็นสเปคพฤติกรรม |
| `backend/app/home_verification.py` | ขอบเขต verifier + จุดต่อขยายถ้าจะทำ face matching |
| `flutter_app/lib/services/api_service.dart:455` | แบบแผนการยิง multipart ของโปรเจ็กต์ |
| `HANDOVER_COMPANY_AND_WORK_2026-09-10.md` | ภาพรวมระบบทั้งหมด + กับดักที่เคยเจอ (หัวข้อ 12) |

---

## 11. สรุปสิ่งที่ต้องตัดสินใจก่อนเริ่ม

1. **shared package หรือก๊อปไฟล์?** (หัวข้อ 5.3) — กระทบว่าจะต้องแก้ 1 ที่หรือ 2 ที่ไปตลอด
2. **รายการบ้านเก่าใน `checkins` จะทำยังไง?** ข้อกำหนดหัวข้อ 12 บอกให้รองรับข้อมูลเก่าผ่าน `office_name` + `LocationService.isHomeName` ต่อไปจนกว่าจะย้ายข้อมูล → ต้องกำหนด**แหล่งข้อมูลหลัก**ให้ชัด ไม่งั้นวันเดียวกันจะแสดงซ้ำ 2 รายการ
3. **จะทำ face matching 1:1 ไหม** (หัวข้อ 6) — ถ้าทำ เป็นงานแยกฝั่ง backend แอปไม่ต้องแก้
4. **iOS เอาด้วยไหม** — ต้องมีเครื่อง macOS + signing และต้องเติม `NSCameraUsageDescription` ในแอปหัวหน้า
