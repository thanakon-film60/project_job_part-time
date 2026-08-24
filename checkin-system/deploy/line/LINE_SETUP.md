# แจ้งเตือนเข้ากลุ่ม LINE — คู่มือตั้งค่าทีละขั้น

> ⚠️ **LINE Notify ปิดบริการไปแล้วตั้งแต่ 1 เม.ย. 2025** (เว็บและ token เดิมใช้ไม่ได้แล้ว)
> ตอนนี้ต้องใช้ **LINE Messaging API** — คือสร้าง "LINE Official Account" (บัญชีบอท) แล้วเชิญเข้ากลุ่ม

ทำครั้งเดียวประมาณ 10–15 นาที ทำตามทีละข้อได้เลย

---

## ภาพรวม

```
พนักงานเช็คอิน  ─►  backend  ─►  LINE Messaging API  ─►  กลุ่มที่คุณอยู่
                                        ▲
                                  บอท (LINE Official Account)
                                  ต้องถูกเชิญเข้ากลุ่มก่อน
```

---

## ขั้นที่ 1 — สร้าง LINE Official Account

> ⚠️ **ต้องเริ่มจากตรงนี้เท่านั้น** — LINE เปลี่ยนกติกาแล้ว
> ถ้าเข้า LINE Developers Console แล้วกด Create a new channel → Messaging API
> จะเจอข้อความว่า *"It's no longer possible to create Messaging API channels
> directly from the LINE Developers Console"* แล้วมีปุ่มเด้งกลับมาที่หน้านี้อยู่ดี

1. เข้า **https://manager.line.biz** แล้วล็อกอินด้วยบัญชี LINE ของคุณ
   (หรือกดปุ่ม *Create a LINE Official Account* จากหน้า Developers Console ก็มาที่เดียวกัน)
2. ระบบจะขอ **ยืนยันตัวตนผ่าน SMS** — ใส่เบอร์มือถือแล้วรับ OTP
3. กรอกฟอร์ม 4 ช่อง:

   | ช่อง | ใส่อะไร |
   |---|---|
   | **ชื่อบัญชี** | `THANAKON-BOX เช็คอิน` ← ชื่อนี้จะโชว์เป็นชื่อบอทในกลุ่ม |
   | **อีเมล** | อีเมลของคุณ |
   | **ประเทศที่ตั้งบริษัท** | ไทย |
   | **ชื่อบริษัท/ธุรกิจ** | `THANAKON-BOX` |
   | **ประเภทธุรกิจ** | เลือกใกล้เคียง เช่น บริการ → อื่นๆ |

4. กด **ถัดไป** → ตรวจข้อมูล (ขั้น 2) → **เสร็จสิ้นการสมัคร** (ขั้น 3)

> ฟรี ไม่ต้องผูกบัตร · ใช้เวลาราว 2 นาที

---

## ขั้นที่ 2 — เปิด Messaging API

1. ใน LINE Official Account Manager ที่เพิ่งสร้าง → **ตั้งค่า (Settings)** → **Messaging API**
2. กด **เปิดใช้ Messaging API (Enable Messaging API)**
3. ระบบจะให้เลือก/สร้าง **Provider** — ตั้งชื่ออะไรก็ได้ เช่น `THANAKON-BOX`
4. เสร็จแล้วจะได้ **Channel ID** และ **Channel secret** — จดค่า **Channel secret** ไว้

---

## ขั้นที่ 3 — ปิดระบบตอบกลับอัตโนมัติ (สำคัญ)

ถ้าไม่ปิด บอทจะตอบข้อความอัตโนมัติกวนในกลุ่ม

ใน **ตั้งค่า → การตอบกลับ (Response settings)**:

| หัวข้อ | ตั้งเป็น |
|---|---|
| ข้อความตอบกลับ (Auto-reply) | **ปิด** |
| ข้อความทักทายเพื่อนใหม่ (Greeting) | **ปิด** |
| Webhook | **เปิด** |
| อนุญาตให้เข้ากลุ่ม (Allow bot to join group chats) | **เปิด** ← สำคัญมาก |

---

## ขั้นที่ 4 — เอา Channel Access Token

1. เข้า **https://developers.line.biz/console/**
2. เลือก Provider → เลือก Channel ที่เพิ่งสร้าง
3. แท็บ **Messaging API** → เลื่อนลงล่างสุด **Channel access token (long-lived)**
4. กด **Issue** แล้วคัดลอกค่ายาว ๆ ที่ได้มา

> 🔒 token นี้เท่ากับกุญแจบ้าน ห้ามส่งให้ใคร ห้าม commit ขึ้น Git
> (ไฟล์ `.env` ถูก gitignore ไว้แล้ว)

---

## ขั้นที่ 5 — ตั้ง Webhook URL

ยังอยู่ในแท็บ **Messaging API** ของ LINE Developers Console:

1. ช่อง **Webhook URL** ใส่:

   ```
   https://thanakronpart-time.com/line/webhook
   ```

2. กด **Update** แล้วกด **Verify** — ต้องขึ้น **Success**
3. เปิดสวิตช์ **Use webhook** ให้เป็นสีเขียว

> ถ้า Verify ไม่ผ่าน: ยังไม่ได้ใส่ `LINE_CHANNEL_SECRET` ใน `.env` (ทำในขั้นที่ 6) — ใส่แล้ว restart backend แล้วค่อยกด Verify ใหม่

---

## ขั้นที่ 6 — ใส่ค่าลงระบบ

เปิดไฟล์ `F:\GitHub\project_job_part-time\checkin-system\backend\.env` แล้วเติม 3 บรรทัดนี้
(ถ้ามีอยู่แล้วให้แก้ค่า)

```
LINE_NOTIFY_ENABLED=true
LINE_CHANNEL_ACCESS_TOKEN=<ค่าที่ได้จากขั้นที่ 4>
LINE_CHANNEL_SECRET=<ค่าที่ได้จากขั้นที่ 2>
LINE_TARGET_ID=
```

> ⚠️ ต้องบันทึกเป็น **UTF-8 ไม่มี BOM** (ถ้าเปิดด้วย VS Code ในโปรเจ็กต์นี้ตั้งไว้ให้แล้ว)

แล้ว restart backend — กดปุ่ม **อัปขึ้นเว็บจริง** ใน `START_PART_TIME.bat` หรือ:

```powershell
Stop-ScheduledTask -TaskName ThanakonBoxCheckinAPI
Start-ScheduledTask -TaskName ThanakonBoxCheckinAPI
```

---

## ขั้นที่ 7 — เชิญบอทเข้ากลุ่ม แล้วเอา Group ID

1. ใน LINE Official Account Manager → หน้าแรกจะมี **QR code** หรือ **LINE ID (@xxxx)** ของบอท
2. **เพิ่มบอทเป็นเพื่อน** ก่อน (สแกน QR)
3. เปิด **กลุ่มที่ต้องการให้แจ้งเตือน** → **เชิญ (Invite)** → เลือกบอทที่เพิ่งเพิ่ม

พอบอทเข้ากลุ่ม **บอทจะทักในกลุ่มพร้อมบอก Group ID ให้เลย** หน้าตาประมาณนี้:

```
สวัสดีครับ ผมคือบอทแจ้งเตือนเข้างาน THANAKON-BOX

ID ของห้องนี้คือ:
Cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

เอาค่านี้ไปใส่ LINE_TARGET_ID ใน .env ของระบบ แล้ว restart backend เป็นอันเสร็จ
```

> ถ้าพลาดข้อความนั้นไป — **พิมพ์คำว่า `id` ในกลุ่ม** บอทจะตอบ Group ID ให้อีกครั้ง

4. เอาค่า `Cxxxx...` ไปใส่ใน `.env`:

   ```
   LINE_TARGET_ID=Cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

5. restart backend อีกครั้ง

---

## ขั้นที่ 8 — ทดสอบ

ล็อกอินเป็นผู้จัดการ (`BOSS001`) แล้วเรียก:

```
POST https://thanakronpart-time.com/line/test
```

หรือเช็คสถานะการตั้งค่า:

```
GET https://thanakronpart-time.com/line/status
```

ถ้าเห็นข้อความทดสอบเด้งเข้ากลุ่ม = เสร็จเรียบร้อย 🎉

---

## สิ่งที่ระบบจะแจ้งเข้ากลุ่ม

**1. ทุกครั้งที่มีคนเช็คอิน/เช็คเอาท์**

```
🟢 เข้างาน
👤 Thanakon (EMP001)
🕐 08:32 น. · 15/08/2026
📍 BJH Bangkok (ห่าง 0.12 กม.)
```

**2. สรุปประจำวัน** (ต้องติดตั้งเพิ่ม 1 คำสั่ง)

```powershell
cd F:\GitHub\project_job_part-time\checkin-system\deploy\line
.\install-daily-summary-task.ps1            # ส่งทุกวัน 20:00
.\install-daily-summary-task.ps1 -Time "17:30"
```

จะได้ข้อความประมาณนี้ทุกเย็น:

```
📋 สรุปการเข้างาน 15/08/2026

✅ มาทำงาน 2 คน
  • Thanakon  08:32–17:05  (BJH Bangkok)
  • สมชาย  09:01–18:12  (THANAKON-BOX)

⛔ ไม่มีบันทึก 1 คน
  • สมหญิง
```

ส่งทดสอบทันที: `Start-ScheduledTask -TaskName MardodiDailySummary`

---

## ข้อจำกัดที่ต้องรู้

- **โควตาข้อความฟรีมีจำกัดต่อเดือน** (LINE ปรับเปลี่ยนเป็นระยะ — ดูใน LINE Official Account Manager → สถิติ)
  ถ้าพนักงานเยอะและเช็คอินวันละหลายครั้ง อาจใช้โควตาเร็ว — ถ้าเป็นแบบนั้นแนะนำปิดการแจ้งรายคน แล้วใช้แค่สรุปประจำวัน
  (ปิดได้โดยตั้ง `LINE_NOTIFY_ENABLED=false` แล้ว restart — แต่สรุปประจำวันจะไม่ส่งด้วย)
- บอทเห็นเฉพาะกลุ่มที่ถูกเชิญเข้าไป ไม่เห็นแชตอื่น
- ถ้าเตะบอทออกจากกลุ่ม การแจ้งเตือนจะหยุดทันที

---

## แก้ปัญหา

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| Verify webhook ไม่ผ่าน | ยังไม่ได้ใส่ `LINE_CHANNEL_SECRET` หรือยังไม่ได้ restart backend · เช็คว่า `https://thanakronpart-time.com/line/webhook` เข้าถึงได้ |
| บอทเข้ากลุ่มแล้วแต่ไม่ทัก | ยังไม่เปิด **Use webhook** หรือ Webhook URL ผิด · ลองพิมพ์ `id` ในกลุ่ม |
| เชิญบอทเข้ากลุ่มไม่ได้ | ยังไม่เปิด **Allow bot to join group chats** (ขั้นที่ 3) |
| `/line/test` ตอบ `sent: false` | token ผิด/หมดอายุ หรือ `LINE_TARGET_ID` ผิด · ดู log ของ backend |
| ไม่มีข้อความเข้าเลยทั้งที่ status ready | โควตาข้อความหมด · เช็คใน LINE Official Account Manager |
| บอทตอบข้อความอัตโนมัติกวน | ยังไม่ได้ปิด Auto-reply / Greeting (ขั้นที่ 3) |

---

## Endpoint ที่เกี่ยวข้อง

| Method | Path | ใช้ทำอะไร |
|---|---|---|
| POST | `/line/webhook` | LINE เรียกเข้ามา (ตรวจลายเซ็นก่อนเสมอ) |
| GET | `/line/status` | ดูว่าตั้งค่าครบหรือยัง (ผู้จัดการ) |
| POST | `/line/test` | ส่งข้อความทดสอบเข้ากลุ่ม (ผู้จัดการ) |

**Sources:** [End of service for LINE Notify](https://notify-bot.line.me/closing-announce) · [Messaging API reference](https://developers.line.biz/en/reference/messaging-api/)
