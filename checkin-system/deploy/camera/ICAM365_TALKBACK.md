# iCam365 Talkback: ทำให้ระบบเราพูดออกกล้อง

สถานะตอนนี้: **ทำได้ในเชิงเทคนิค แต่ยังทำไม่ได้ด้วยโค้ดปัจจุบันโดยตรง**

เหตุผลไม่ใช่ว่ากล้องไม่มีลำโพง แอป iCam365 ของผู้ผลิตพูดออกกล้องได้จริง แปลว่ากล้องมีทางรับเสียงเข้าอยู่แล้ว เพียงแต่ทางที่เปิดให้เราใช้ตอนนี้ผ่าน ONVIF/RTSP ไม่ได้ประกาศช่องส่งเสียงกลับ

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

### ทาง A: ขอ SDK/credential จาก Tange หรือผู้ขาย

ถามผู้ขาย/ผู้ผลิตว่าขอข้อมูลสำหรับ client integration ได้ไหม:

- `AppId`
- `access_id`
- `secret_key`
- `device_id` หรือ `remote_id`
- วิธีออก connect token สำหรับกล้อง iCam365 ที่ขายอยู่
- SDK Flutter/Android ที่รองรับ talkback กับ iCam365 retail device

ถ้าได้ข้อมูลชุดนี้ เราทำในระบบเราได้สะอาดที่สุด:

1. backend ออก short-lived token ให้เฉพาะหัวหน้า
2. boss app ใช้ SDK ต่อเข้ากล้อง
3. app เปิดไมค์และส่งเสียงผ่าน SDK ไปกล้อง

### ทาง B: จับแพ็กเก็ตตอนกดพูด แล้วถอดโปรโตคอล

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

## งานโค้ดหลังรู้โปรโตคอล

เมื่อรู้วิธีส่งเสียงเข้ากล้องแล้ว งานในระบบเราจะเป็น:

1. เพิ่ม endpoint เช่น `POST /camera/talkback/start`, stream/chunk, และ `POST /camera/talkback/stop`
2. จำกัดสิทธิ์ด้วย `require_manager` เหมือน `/camera/audio`
3. ใน boss app เพิ่ม permission ไมค์และปุ่มกดค้างเพื่อพูด
4. encode เสียงมือถือให้ตรงที่กล้องรับ เช่น G.711 A-law 8 kHz mono
5. ทดสอบ latency, ตัดสายเมื่อปล่อยปุ่ม, และกันหลายคนพูดพร้อมกัน

## ข้อสรุป

คำพูดว่า "ทำไม่ได้" เดิมต้องอ่านให้แคบลง:

> ทำไม่ได้ผ่าน ONVIF/RTSP มาตรฐานที่ระบบเราใช้ตอนนี้

แต่ถ้ายอมไปทาง SDK/credential ของ Tange หรือถอดโปรโตคอลจาก packet capture ได้ ระบบเราก็ทำปุ่มพูดออกกล้องได้
