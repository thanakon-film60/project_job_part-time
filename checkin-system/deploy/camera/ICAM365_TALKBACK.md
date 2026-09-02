# iCam365 Talkback: ทำให้ระบบเราพูดออกกล้อง

> ## สถานะล่าสุด 2 ก.ย. 2026
>
> พบ **TiRTC Flutter SDK ทางการของ Tange** ที่รองรับ Voice Talkback แล้ว
> แนวทางหลักจึงไม่ต้องถอด proprietary packet และไม่ต้องส่ง raw audio ผ่าน Python
>
> - ✅ backend ออก token อายุสั้น: `POST /camera/talkback/token`
> - ✅ จำกัดเฉพาะหัวหน้าและไม่รับ `remote_id` จาก client
> - ✅ token ใช้ HMAC-SHA256 ตามสัญญา Tange และห้าม cache
> - ✅ มีสถานะ `talkback_ready`, transport และ stream ID ใน `/camera/status`
> - ⬜ Flutter: งานส่งต่ออยู่ที่
>   [`../../flutter_boss_app/TIRTC_TALKBACK_TASKS.md`](../../flutter_boss_app/TIRTC_TALKBACK_TASKS.md)
> - ⬜ Production: รอ `AppId`, `AccessKeyId`, `SecretKeyId`, `device_id` และ
>   การยืนยันว่ากล้อง retail ตัวปัจจุบันเข้า developer application ของเราได้

เหตุผลไม่ใช่ว่ากล้องไม่มีลำโพง แอป iCam365 ของผู้ผลิตพูดออกกล้องได้จริง แปลว่ากล้องมีทางรับเสียงเข้าอยู่แล้ว เพียงแต่ทางที่เปิดให้เราใช้ตอนนี้ผ่าน ONVIF/RTSP ไม่ได้ประกาศช่องส่งเสียงกลับ

## สถาปัตยกรรมที่เลือก

```text
Flutter boss app ──ขอ token──> Python backend
       │                       (ตรวจสิทธิ์ + เซ็นอายุสั้น)
       └──── TiRTC encrypted P2P/Cloud ────> iCam365 speaker
```

เสียงไม่วิ่งผ่าน Python และ `SecretKeyId` ไม่ออกจาก backend

## สิ่งที่ยืนยันแล้ว

จากกล้อง `192.168.1.101`:

| ทางที่ลอง | ผล |
| --- | --- |
| RTSP `OPTIONS` พอร์ต 554 | มี `DESCRIBE, PLAY, SETUP, TEARDOWN, SET_PARAMETER` แต่ไม่มี `ANNOUNCE`/`RECORD` |
| RTSP `DESCRIBE` + `Require: www.onvif.org/ver20/backchannel` | ไม่มี audio track ที่เป็น `a=sendonly` |
| RTSP พอร์ต 8001 | เป็น TAS-Tech video stream ไม่มี audio backchannel |
| พอร์ตเฉพาะผู้ผลิต | เปิดอยู่ เช่น `3201`, `3576`, `6670`, `8200`, `20202` แต่ไม่ตอบ HTTP/RTSP ปกติ |

แปลว่า:

- ระบบเราฟังเสียงได้ผ่าน `/camera/audio`
- ระบบเรายังส่งเสียงเข้ากล้องไม่ได้ผ่าน ONVIF/RTSP มาตรฐาน
- ถ้าจะให้พูดกลับกับกล้อง iCam365 ตัวนี้ ต้องทำผ่านโปรโตคอลของ Tange/iCam365 หรือใช้ SDK/credential จากผู้ผลิต

## หลักฐานจากเอกสารผู้ผลิต

เอกสารทางการของ iCam365 ระบุว่า permission ไมโครโฟนใช้สำหรับ Two-Way Talk: ผู้ใช้พูดผ่านแอปแล้วเสียงไปออกลำโพงกล้อง

เอกสาร Tange Cloud for Device มี callback ฝั่งอุปกรณ์สำหรับ talkback:

- `on_talkback_start`
- `talkback(TCMEDIA at, const uint8_t *audio, int len)`
- `on_talkback_stop`

นี่ชี้ว่าทางพูดกลับอยู่ในช่อง SDK/P2P ของ Tange ไม่ใช่ RTSP endpoint ธรรมดาที่เราเรียกด้วย ffmpeg ได้ทันที

## ทางทำให้ได้จริง

### ทาง A (เลือกใช้): TiRTC SDK/credential จาก Tange

ถามผู้ขาย/ผู้ผลิตว่าขอข้อมูลสำหรับ client integration ได้ไหม:

- `AppId`
- `access_id`
- `secret_key`
- `device_id` หรือ `remote_id`
- วิธีออก connect token สำหรับกล้อง iCam365 ที่ขายอยู่
- SDK Flutter/Android ที่รองรับ talkback กับ iCam365 retail device

backend สำหรับข้อมูลชุดนี้ทำเสร็จแล้ว โฟลจริงคือ:

1. backend ออก short-lived token ให้เฉพาะหัวหน้า
2. boss app ใช้ `tirtc_flutter` ต่อเข้ากล้อง
3. SDK เปิดไมค์แบบ G.711 A-law 16 kHz mono และส่งไป stream ID 14

### ทาง B (fallback): จับแพ็กเก็ตตอนกดพูด แล้วถอดโปรโตคอล

ใช้เมื่อผู้ผลิตไม่ให้ SDK/API

รันบน Windows ที่ traffic มือถือผ่านเครื่องนี้จริง เช่น เปิด Mobile Hotspot บน Windows แล้วให้มือถือที่มี iCam365 ต่อ Wi-Fi จากเครื่องนี้:

```powershell
cd C:\project_job_part-time\checkin-system\deploy\camera
.\capture-icam365-talkback.ps1 -CameraIp 192.168.1.101 -Seconds 45
```

ตอนสคริปต์ขึ้น `START TALKING`:

1. กดปุ่มพูดใน iCam365 ค้างประมาณ 10 วินาที
2. พูดประโยคสั้น ๆ ซ้ำ ๆ เช่น "test one two three"
3. ปล่อยปุ่มพูด
4. รอจนสคริปต์จบ

ไฟล์ที่ได้จะอยู่ใน:

```text
checkin-system\deploy\camera\captures\icam365-talkback-*.pcapng
```

หลังได้ไฟล์ `.pcapng` ให้ดู 3 อย่าง:

- กดพูดแล้วมี traffic ไปพอร์ตไหนเพิ่มขึ้น
- เป็น local ตรงไป `192.168.1.101` หรือวิ่งออก cloud ของ Tange ก่อน
- payload เสียงเป็น G.711 A-law 8 kHz, PCM, Opus, หรือถูกเข้ารหัส

ถ้า payload ไม่เข้ารหัสและเห็น framing ชัด เราค่อยเขียน backend talkback bridge ได้

## งานโค้ดกรณี TiRTC ใช้กับกล้อง retail ตัวนี้ไม่ได้

หัวข้อนี้ใช้เฉพาะเมื่อ Tange ยืนยันว่า TiRTC developer credential ไม่สามารถ
authorize กล้อง retail ตัวปัจจุบันได้ และต้องย้อนกลับไปถอด protocol เอง:

1. เพิ่ม endpoint เช่น `POST /camera/talkback/start`, stream/chunk, และ `POST /camera/talkback/stop`
2. จำกัดสิทธิ์ด้วย `require_manager` เหมือน `/camera/audio`
3. ใน boss app เพิ่ม permission ไมค์และปุ่มกดค้างเพื่อพูด
4. encode เสียงมือถือให้ตรงที่กล้องรับ เช่น G.711 A-law 8 kHz mono
5. ทดสอบ latency, ตัดสายเมื่อปล่อยปุ่ม, และกันหลายคนพูดพร้อมกัน

## ข้อสรุป

ระบบทำ backend ทาง SDK ทางการเสร็จแล้ว เหลือสองเงื่อนไขก่อนใช้งานจริง:

1. Tange ออก credential และอนุญาตกล้องตัวปัจจุบันให้ developer app ของเรา
2. ทีม Flutter ทำตาม `TIRTC_TALKBACK_TASKS.md`

ส่วน ONVIF/RTSP ยังใช้พูดกลับไม่ได้เหมือนเดิม แต่ไม่ใช่เส้นทางหลักแล้ว
