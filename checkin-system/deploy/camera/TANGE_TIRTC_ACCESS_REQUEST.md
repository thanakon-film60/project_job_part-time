# ข้อความขอเปิด TiRTC สำหรับกล้อง iCam365 ตัวปัจจุบัน

ส่งถึง: `business@tange.ai`  
สำเนาได้ที่: `service@tange.ai`

ก่อนส่ง ให้แทนค่าที่อยู่ใน `<...>` เท่านั้น อย่าแนบรหัสผ่านกล้อง, JWT ของระบบ
หรือ `.env`

## Subject

```text
TiRTC Flutter SDK access for an existing iCam365 retail camera
```

## Email body

```text
Hello Tange team,

We operate an existing iCam365 retail camera and would like to integrate its
two-way talk function into our private Android management app built with Flutter.

Our intended architecture follows your TiRTC documentation:
- Flutter client SDK: tirtc_flutter 2.3.1
- Our Python business backend authenticates the manager and issues a short-lived
  v1 connection token using AccessKeyId / SecretKeyId.
- The Flutter client connects to the camera remote_id and sends microphone audio
  using G.711A, 16 kHz mono, stream_id 14.

Existing device information:
- Product/app: iCam365
- Model reported by ONVIF: cloudCam
- Firmware: 43.4.0.0
- Device SN shown in iCam365: <DEVICE_SN>
- iCam365 account/cloud region: <REGION_OR_ACCOUNT_COUNTRY>

Please confirm the following before activation:
1. Can this existing retail iCam365 device be authorized to a third-party TiRTC
   developer application without replacing its firmware or factory credentials?
2. Can you map/grant its current device_id/remote_id to our application?
3. Which stream_id and microphone codec/sample rate does this exact firmware
   accept for talkback?
4. Are account binding, user consent, licensing, or commercial fees required?
5. Please provide the onboarding steps and test credentials:
   AppId, AccessKeyId, SecretKeyId, and the authorized device_id/remote_id.

The SecretKeyId will remain only on our controlled backend and will not be
embedded in the mobile application.

Thank you.

Best regards,
<NAME>
<COMPANY>
<CONTACT_EMAIL_OR_PHONE>
```

## สิ่งที่ต้องตรวจในคำตอบ

- ต้องตอบเจาะจงว่า **กล้อง retail ตัวที่มีอยู่** ใช้ได้ ไม่ใช่แค่ส่ง credential
  ของ test device คนละตัว
- ต้องบอก `device_id`/`remote_id` ที่ client SDK ใช้เชื่อม
- ต้องมี `AppId`, `AccessKeyId`, `SecretKeyId` หรือขั้นตอนรับค่าทั้งสาม
- ถ้าให้ `device_secret_key` มาด้วย ห้ามส่งต่อเข้า Flutter; เก็บตามคำแนะนำ
  Tange และถามก่อนว่าจำเป็นกับ retail camera หรือไม่
- ยืนยัน codec, sample rate และ stream ID อีกครั้งก่อนทดสอบเสียงจริง

