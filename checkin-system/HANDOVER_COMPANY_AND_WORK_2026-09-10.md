# สรุปบริบทบริษัท + งานทั้งหมด (ฝั่งเว็บ & ฝั่งแอป) — ส่งต่อให้ระบบ/เอเจนต์ตัวถัดไป

> **วันที่:** 10 กันยายน 2026
> **ขอบเขต:** บริบทธุรกิจของบริษัทปลายทาง + งานพัฒนาทั้งหมดที่มีอยู่ในเครื่องนี้ (`F:\GitHub`)
> **จุดประสงค์:** ให้คน/AI ตัวถัดไปอ่านไฟล์เดียวแล้วทำงานต่อได้ทันที โดยไม่ต้องไล่โค้ดใหม่
> **วิธีอ่าน:** ทุกหัวข้อพับเก็บไว้ (collapsible) — กดที่หัวข้อเพื่อกาง

---

## ⚡ TL;DR — อ่าน 60 วินาที

| # | เรื่อง | สรุป |
|---|---|---|
| 1 | **บริษัทปลายทาง** | `Motta & Montipa` — **แบรนด์แฟชั่นไทย** (กางเกง/เสื้อผ้า/เครื่องประดับ/กระเป๋า) ขายผ่านเคาน์เตอร์ในห้าง 23–30+ สาขา + ออนไลน์ สำนักงานใหญ่ปากเกร็ด นนทบุรี — ⚠️ **ยังไม่ยืนยัน** ดูหัวข้อ 1 |
| 2 | **ระบบหลัก** | `checkin-system` — ลงเวลาเข้างานด้วย GPS geofence + สแกนหน้า, เว็บ React (PWA) + Flutter 2 แอป + FastAPI/PostgreSQL |
| 3 | **ฝั่งเว็บ** | ✅ เสร็จและ deploy แล้วบน `https://thanakronpart-time.com` (8 หน้า, ป้ายสาย/ตรงเวลา, ปฏิทิน, แผนที่สด, แชท) |
| 4 | **ฝั่งแอป** | ✅ **build เสร็จและติดตั้งบนเครื่องจริงแล้ว** (11 ก.ย.) — พนักงาน `1.5.0+7`, หัวหน้า `1.2.0+4` ทดสอบบน MTN NX1 (Android 16) ผ่าน · ⚠️ แต่ **ที่แจกบนเว็บยังเป็นตัวเก่า** `1.2.0+3` / `1.0.0+1` |
| 5 | **ตัวบล็อกใหญ่สุด** | เหลือ 2 ตัว: **publish APK ขึ้น production** (ต้องทำบนเครื่อง production ซึ่งเป็นคนละเครื่องกับ dev) + ฟีเจอร์ไมค์รอ credential จาก Tange (`business@tange.ai`) |
| 6 | **ของที่ยังไม่ commit** | ✅ ของเก่า commit หมดแล้ว (`c627aab`, `1161a2d`) · รอบ 11 ก.ย. มีแก้ `checkin_tab.dart` ทั้ง 2 แอป ดูหัวข้อ 9.3 |

**สิ่งที่ควรทำก่อนอย่างอื่น:** publish APK 2 ตัวขึ้น production (หัวข้อ 10.1) → ขอ credential Tange (หัวข้อ 10.2) → ยืนยันข้อมูลบริษัทกับ HR (หัวข้อ 1.4)

---

<details>
<summary><b>1. บริษัทที่กำลังจะไปเริ่มงาน — Motta &amp; Montipa ทำธุรกิจอะไร</b></summary>

### 1.0 ระดับความน่าเชื่อถือของหัวข้อนี้

> ⚠️ **อ่านก่อน** — เจ้าของงานให้ข้อมูลว่า *"montipa น่าจะเป็นชื่อบริษัทที่ฉันกำลังจะไปเริ่มงาน"*
> คำว่า **"น่าจะ"** แปลว่ายังไม่ยืนยัน ข้อมูลด้านล่างมาจาก 2 แหล่ง แยกป้ายกำกับไว้ชัดเจน:
>
> | ป้าย | ความหมาย |
> |---|---|
> | 🟢 **ยืนยันแล้ว** | อ่านจากไฟล์ในโปรเจกต์นี้โดยตรง |
> | 🟡 **จากแหล่งสาธารณะ** | ค้นเว็บเมื่อ 10 ก.ย. 2026 — ตรงกันหลายแหล่งแต่ยังไม่ได้ยืนยันกับบริษัท |
> | 🔴 **ยังไม่รู้** | ต้องถาม HR |

### 1.1 🟢 หลักฐานที่มีในโค้ด

จาก `backend/.env` และ `/reports/geofence` บน production:

```json
{"name":"Motta & Montipa (Head office)","lat":13.9040518,"lng":100.5391995,"radius_km":0.5,"category":"work"}
```

| รายการ | ค่า |
|---|---|
| ชื่อสถานที่ในระบบ | `Motta & Montipa (Head office)` |
| พิกัด | `13.9040518, 100.5391995` (ย่านปากเกร็ด/บางตลาด นนทบุรี) |
| รัศมี geofence | 0.5 กม. |
| เวลาทำงานที่ตั้งไว้ | **08:30 – 17:30** ผ่อนผัน 0 นาที |
| วันที่ย้ายเข้าระบบ | 10 ก.ย. 2026 (commit `73e6a2e` "update code location Company") |
| ที่มาพิกัด | https://maps.app.goo.gl/pnmwajnaByj1UBMn8 |

### 1.2 🟡 ธุรกิจของบริษัท (จากแหล่งสาธารณะ)

**ประเภทธุรกิจ: แบรนด์แฟชั่น — เจ้าของสินค้าเอง ผลิตเอง ขายเอง (retail + wholesale)**

เป็นกลุ่มที่ทำ **2 แบรนด์คู่กัน** ภายใต้ร่มเดียวกัน:

| แบรนด์ | สินค้าหลัก | ช่องทาง |
|---|---|---|
| **Montipa** | กางเกงผ้า/ยีนส์ผู้หญิงเป็นตัวชูโรง (จุดขาย: *"ใส่สวยไม่ต้องรีด"*) แยกทรงเป็นรหัส — `S` สลิม, `W` ขากระบอก, `N` ขา 5 ส่วน, `H` ขาสั้น, `J` ยีนส์ + เสื้อ | เคาน์เตอร์/ช็อปในห้าง **23 สาขาทั่วประเทศ** (Central, Robinson Lifestyle) + เว็บแบรนด์ + Shopee (`montipabrand`) + TikTok (`@montipa_official`) + LINE |
| **Motta** | เครื่องประดับ กระเป๋า เสื้อผ้า สินค้าแฟชั่น | เคาน์เตอร์ในห้าง **30+ สาขา** (Central, The Mall, Robinson) + ออนไลน์ |

**โมเดลธุรกิจโดยสรุป:**

```
ผลิต/จัดหาสินค้าเอง ──► กระจายเข้าเคาน์เตอร์ในห้างสรรพสินค้าทั่วประเทศ (ช่องทางหลัก)
                     └─► ขายออนไลน์เอง (เว็บแบรนด์ / Shopee / TikTok / LINE)
```

- รายได้หลักมาจาก **การขายปลีกหน้าร้านในห้าง** โดยมี **PC (พนักงานขายประจำเคาน์เตอร์)** เป็นกำลังหลัก — มีประกาศรับ PC ประจำสาขา เช่น เซ็นทรัลพระราม 3 และตำแหน่ง Area Manager คุมหลายสาขา
- มีทีม **การตลาด/ขายออนไลน์** แยกต่างหาก (ประกาศรับ "ผู้จัดการทีมการตลาด การขาย ออนไลน์" อ้างถึง `www.mottashop.com`)
- ประกาศรับสมัครงานของทั้งสองแบรนด์ออกในนามนิติบุคคล **บริษัท แอ็ท เฟเวอริท จำกัด (AT Favorite Co., Ltd.)**

### 1.3 🟡 ข้อมูลนิติบุคคลที่ค้นเจอ

| รายการ | ค่า |
|---|---|
| ชื่อไทย | บริษัท **มนทิพาดีไซน์** จำกัด |
| ชื่ออังกฤษ | MONTIPA DESIGN CO., LTD. |
| เลขทะเบียน | `0105565157489` |
| วันจดทะเบียน | 26 กันยายน 2565 |
| ทุนจดทะเบียน | 1,000,000 บาท |
| TSIC | `46103` — ขายส่งสิ่งทอ เสื้อผ้า รองเท้า เครื่องหนัง และของใช้ในครัวเรือน |
| ที่ตั้ง | 59/37 ม.3 ต.คลองเกลือ อ.ปากเกร็ด จ.นนทบุรี 11120 |
| โทร | 02-575-2287 |

> **ที่ตั้งนี้สอดคล้องกับพิกัด geofence ในระบบ** (ปากเกร็ด นนทบุรี) — เป็นหลักฐานเสริมว่าตีความถูกทาง
> แต่ยังมีอีกนิติบุคคลที่โผล่ในประกาศงาน (**แอ็ท เฟเวอริท**) จึงยังสรุปไม่ได้ว่าตัวไหนเป็นนายจ้างจริง

### 1.4 🔴 สิ่งที่ต้องถาม HR ให้ชัดในวันเริ่มงาน

- [ ] นิติบุคคลที่ **จ้างจริง** คือ *มนทิพาดีไซน์* หรือ *แอ็ท เฟเวอริท* หรือคนละบริษัท
- [ ] ที่อยู่ออฟฟิศแบบตัวอักษรเต็ม (ยังว่างอยู่ในระบบ — ฟิลด์ `address` ใน `OFFICES`)
- [ ] จำนวนสาขา/เคาน์เตอร์ปัจจุบัน และมีพนักงานกี่คนที่ต้องลงเวลา
- [ ] เวลาทำงานจริงของแต่ละกลุ่ม — ออฟฟิศ 08:30–17:30 แต่ **PC หน้าร้านทำตามรอบห้าง (ราว 10:00–22:00)** ซึ่งไม่ตรงกับค่าที่ตั้งไว้ตอนนี้
- [ ] วันหยุด/วันลา ใช้ปฏิทินแบบไหน (ระบบยังไม่รู้จักวันหยุดเลย — ดูหัวข้อ 6.4)

### 1.5 ⚠️ ผลกระทบต่อการออกแบบระบบ (สำคัญกับคนทำต่อ)

ถ้าระบบลงเวลานี้จะถูกใช้กับบริษัทจริง ธุรกิจแบบ "เคาน์เตอร์ในห้างหลายสิบสาขา" ชนกับ assumption เดิม 3 จุด:

| assumption เดิม | ความจริงของธุรกิจนี้ | ต้องแก้อะไร |
|---|---|---|
| ออฟฟิศเดียว รัศมี 0.5 กม. | 23–30+ เคาน์เตอร์กระจายทั่วประเทศ | เติม `OFFICES` เป็นหลายรายการ (โค้ดรองรับอยู่แล้ว ไม่ต้อง build ใหม่) — แต่เคาน์เตอร์ในห้างอยู่ใกล้กันมาก อาจต้องลดรัศมีเหลือ 0.1–0.2 กม. หรือแยกด้วยชั้น/โซนแทน |
| เวลางาน 08:30–17:30 ชุดเดียวทั้งบริษัท | ออฟฟิศกับหน้าร้านคนละกะ | ต้องทำ **ตารางเวลารายกลุ่ม/รายคน** — ตอนนี้ `WORK_START_TIME` เป็นค่าเดียวทั้งระบบ (งานคนละก้อน) |
| กะกลางวันวันเดียวจบ | ห้างปิด 22:00 กะเย็นอาจคาบเกี่ยว | ตรรกะปัจจุบันเทียบ "เวลาในวัน" ไม่ดูวันที่ — กะข้ามคืนจะคำนวณผิด (หัวข้อ 6.4) |

### 1.6 แหล่งอ้างอิงภายนอก

- [Montipa_Brand — เว็บแบรนด์](https://www.montipa-design.com/) · [หน้าเกี่ยวกับเรา](https://www.montipa-design.com/%E0%B9%80%E0%B8%81%E0%B8%B5%E0%B9%88%E0%B8%A2%E0%B8%A7%E0%B8%81%E0%B8%B1%E0%B8%9A%E0%B9%80%E0%B8%A3%E0%B8%B2) · [หมวดสินค้า](https://www.montipa-design.com/%E0%B8%AB%E0%B8%A1%E0%B8%A7%E0%B8%94%E0%B8%AA%E0%B8%B4%E0%B8%99%E0%B8%84%E0%B9%89%E0%B8%B2)
- [MONTIPA SHOP Thailand](https://www.montipashopthailand.com/)
- [Shopee — montipabrand](https://shopee.co.th/montipabrand) · [TikTok — @montipa_official](https://www.tiktok.com/@montipa_official)
- [ข้อมูลนิติบุคคล มนทิพาดีไซน์ (Creden)](https://data.creden.co/company/general/0105565157489)
- [ประกาศงาน PC ประจำสาขา — แอ็ท เฟเวอริท (jobbkk)](https://www.jobbkk.com/jobs/detail/171621/1006202/%E0%B8%AB%E0%B8%B2%E0%B8%87%E0%B8%B2%E0%B8%99,%E0%B8%9E%E0%B8%99%E0%B8%B1%E0%B8%81%E0%B8%87%E0%B8%B2%E0%B8%99%E0%B8%82%E0%B8%B2%E0%B8%A2%20%E0%B9%80%E0%B8%8B%E0%B9%87%E0%B8%99%E0%B8%97%E0%B8%A3%E0%B8%B1%E0%B8%A5%20%E0%B8%9E%E0%B8%A3%E0%B8%B0%E0%B8%A3%E0%B8%B2%E0%B8%A13) · [Area Manager](https://www.jobbkk.com/jobs/detail/171621/866333) · [ผู้จัดการทีมการตลาด/ขายออนไลน์ (อ้าง mottashop.com)](https://jobbkk.com/jobs/detail/171621/862621/www.mottashop.com)

</details>

---

<details>
<summary><b>2. แผนที่งานทั้งหมดในเครื่องนี้ — มี 3 ระบบ ไม่ใช่ระบบเดียว</b></summary>

| # | ระบบ | โฟลเดอร์ | ทำอะไร | สถานะ |
|---|---|---|---|---|
| 1 | **ระบบลงเวลาเข้างาน** ⭐ ตัวหลัก | `F:\GitHub\project_job_part-time\checkin-system` | GPS geofence + สแกนหน้า + ปฏิทินหัวหน้า + แผนที่สด + แชท + กล้องวงจรปิด | 🟢 ใช้งานจริงบน `thanakronpart-time.com` — เว็บอัปแล้ว **แอปยังค้าง** |
| 2 | **บันทึกเส้นทางไรเดอร์ บางบัวทอง** | `F:\GitHub\frontend_film_dev` (ตัวหลัก) / `F:\GitHub\backend_film_dev` (สำเนาเก่า) | ไรเดอร์บันทึกจุดส่งของ + GPS + แผนที่ + สมุดที่อยู่ลูกค้า + **OCR อ่านชื่อในวงกลมสีแดง** | 🟡 โค้ดครบ รันบนเครื่อง ไม่ได้ deploy เป็น production |
| 3 | **CCTV Smart System** | `F:\GitHub\frigate-dev` | Frigate NVR + สั่งกล้องเล่นเสียงออกลำโพง | 🟢 แก้จบแล้ว 7 ก.ย. 2026 — กล้องพูดได้จริง ดู `CCTV_SYSTEM_HANDOFF.md` |

**ความสัมพันธ์:** ระบบ 1 กับ 3 เกี่ยวกัน — แท็บกล้องในแอปหัวหน้าคุยกับกล้องตัวเดียวกับที่ระบบ 3 ดูแล ส่วนระบบ 2 แยกอิสระ (คนละงาน คนละ stack, SQLite)

> เอกสารนี้เน้นระบบ 1 เป็นหลักตามที่ร้องขอ (ฝั่งเว็บ + ฝั่งแอป) ระบบ 2 และ 3 สรุปไว้ในหัวข้อ 11

</details>

---

<details>
<summary><b>3. สถาปัตยกรรมระบบหลัก (checkin-system)</b></summary>

```
┌─────────────────┐   GPS ทุก 60 วิ + สแกนหน้า   ┌──────────────────┐
│ Flutter แอป      │ ──────────────────────────► │                  │
│ พนักงาน v1.5.0+7 │                              │   FastAPI :8001  │──► PostgreSQL
└─────────────────┘                              │   (uvicorn)      │
┌─────────────────┐   ดูทีม/แผนที่/กล้อง/ไมค์    │                  │──► LINE Messaging API
│ Flutter แอป      │ ──────────────────────────► │                  │
│ หัวหน้า v1.2.0+4 │                              │                  │──► กล้อง CCTV (PTZ/RTSP/TiRTC)
└─────────────────┘                              └──────────────────┘
┌─────────────────┐   REST + JWT                          ▲
│ React PWA (เว็บ) │ ─────────────────────────────────────┘
│ + ติดตั้งลงมือถือ│
└─────────────────┘
        ▲
        │ HTTPS
┌───────┴──────────────────────────────────────────────┐
│ Cloudflare Tunnel → IIS :80 → static React           │
│                            └→ ARR proxy → uvicorn :8001│
│ โดเมน: thanakronpart-time.com / www / api (ชี้ที่เดียวกัน) │
└──────────────────────────────────────────────────────┘
```

**หลักการสำคัญ 3 ข้อ:**

1. **backend เป็นผู้ตัดสินเสมอ** — แอป/เว็บแค่แสดงผลล่วงหน้า จะเช็คอินผ่านหรือไม่ backend ชี้ขาด
2. **API ไม่มี `/api` นำหน้า** — เรียก `/auth/login` ตรง ๆ (production ยังรองรับ `/api/...` ให้ client เก่า) → **ชื่อ route ของหน้าเว็บห้ามซ้ำกับ path ของ API** เช่นหน้าเว็บใช้ `/face-records` เพราะ `/faces` เป็นของ API
3. **config อยู่ที่ `.env` ไม่ได้ฝังในโค้ด** — เปลี่ยนสถานที่/เวลางานแล้ว restart backend พอ **ไม่ต้อง build แอปใหม่** (แอปดึงจาก `/reports/geofence`)

**Stack ต่อชั้น**

| ชั้น | เทคโนโลยี | โฟลเดอร์ |
|---|---|---|
| Backend | FastAPI + SQLAlchemy + PostgreSQL 16 | `backend/` |
| เว็บ | React + Vite + Ant Design + vite-plugin-pwa | `frontend/` |
| แอปพนักงาน | Flutter + ML Kit face detection + background GPS | `flutter_app/` |
| แอปหัวหน้า | Flutter + TiRTC SDK (ไมค์พูดออกกล้อง) | `flutter_boss_app/` |
| Deploy | IIS + URL Rewrite + ARR + Cloudflare Tunnel + Scheduled Task | `deploy/` |
| Dev env | Docker Compose (db :5433, api :8010 — แยกจาก production) | `docker-compose.yml` |

</details>

---

<details>
<summary><b>4. ฝั่งเว็บ (React PWA) — ทำอะไรไปแล้วบ้าง</b></summary>

### 4.1 หน้าเว็บทั้งหมด (จาก `frontend/src/App.jsx`)

| Path | ไฟล์ | ใครเข้าได้ | ทำอะไร |
|---|---|---|---|
| `/login` | `LoginPage.jsx` | ทุกคน | ล็อกอินด้วยรหัสพนักงาน/อีเมล → ได้ JWT เก็บใน localStorage |
| `/` | `DashboardPage.jsx` | ล็อกอินแล้ว | **หัวหน้า:** ปฏิทินรายเดือน เลือกพนักงาน/เดือน กดวันเพื่อดูรายละเอียด · **พนักงาน:** การ์ดสรุปวันนี้ + สถานะสาย/ตรงเวลา |
| `/employees` | `EmployeesPage.jsx` | หัวหน้า | รายชื่อพนักงาน + แก้ไขข้อมูล |
| `/employees/register` | `EmployeeRegistrationPage.jsx` | หัวหน้า | ลงทะเบียนพนักงานใหม่ (บัตรประชาชน + ที่อยู่ + แผนก/ตำแหน่ง) |
| `/employees/:id/history` | `EmployeeHistoryPage.jsx` | หัวหน้า | ประวัติรายบุคคล + **สรุปรายเดือน: มาสายกี่วัน / ออกก่อนกี่วัน** |
| `/live-map` | `LiveMapPage.jsx` | หัวหน้า | แผนที่ตำแหน่งพนักงานแบบสด |
| `/face-records` | `FaceRecordsPage.jsx` | ล็อกอินแล้ว | เปิดกล้องเว็บบันทึกใบหน้า + แกลเลอรีรูป (หัวหน้าดูของทุกคนได้) |
| `/install-boss-app` | `BossAppDownloadPage.jsx` | ล็อกอินแล้ว | หน้าโหลด APK แอปหัวหน้า |
| อื่น ๆ | — | — | redirect กลับ `/` |

### 4.2 Component ที่ทำไว้

| ไฟล์ | หน้าที่ |
|---|---|
| `components/WorkSchedule.jsx` 🆕 | โหลดเกณฑ์เวลา+สถานที่จาก API แสดงสถานะ มีปุ่มลองใหม่เมื่อ API ล่ม (**ไม่ใช้ค่าเดา**) |
| `lib/work-schedule.js` 🆕 | สมองของการตัดสิน สาย/ตรงเวลา/ออกก่อน ฝั่งเว็บ + สรุปครั้งแรก–ครั้งสุดท้ายรายวัน |
| `components/MonthCalendar.jsx` | ปฏิทินรายเดือน |
| `components/ChatWidget.jsx` 🆕 | แชทระหว่างพนักงาน–หัวหน้า |
| `components/EmployeeFaceAvatar.jsx` | รูปประจำตัวจากใบหน้าใบแรกที่จัดลำดับไว้ |
| `components/UnverifiedDutyAlert.jsx` | เตือนเมื่อลงเวลาไม่ผ่านการยืนยัน |
| `components/AppDownloadCard.jsx` | การ์ดโหลด APK บนหน้าแรก |
| `components/EmployeeEditDialog.jsx` · `employee-registration/` | ฟอร์มจัดการพนักงาน |
| `components/ErrorBoundary.jsx` · `AppLayout.jsx` · `ui/` | โครงและ error handling |

🆕 = เพิ่มรอบล่าสุด **ยังไม่ commit**

### 4.3 PWA

เว็บนี้ติดตั้งลงมือถือได้เหมือนแอป (`vite-plugin-pwa` ใน `frontend/vite.config.js`)

- Android/Chrome: เมนู ⋮ → ติดตั้งแอป · iPhone: **ต้องเป็น Safari** → แชร์ → เพิ่มไปยังหน้าจอโฮม
- **จงใจไม่ cache คำขอที่ยิงไป API** เพื่อให้ข้อมูลเช็คอินสดเสมอ
- ข้อดีเทียบ APK: อัปเดตทันทีที่ deploy ไม่ต้องให้พนักงานลงไฟล์ใหม่ + ใช้ได้ทั้ง Android/iOS ด้วยโค้ดชุดเดียว + ไม่ต้องมี Flutter SDK บนเซิร์ฟเวอร์
- ⚠️ กล้องเว็บใช้ได้เฉพาะ **HTTPS** หรือ `localhost`

### 4.4 ผลทดสอบฝั่งเว็บ (10 ก.ย. 2026)

| รายการ | ผล |
|---|---|
| `node --test tests/work-schedule.test.mjs` | ✅ 16 tests ผ่าน |
| `node tests/work-schedule-parity.mjs` (เทียบกับ Python backend) | ✅ **11,520 กรณีตรงกันหมด** — ทุกนาที × 2 ตารางเวลา × 2 ช่วงผ่อนผัน × เข้า/ออก |
| `npm run build` | ✅ ผ่าน รวม PWA (⚠️ เตือน bundle > 500 kB) |
| Edge headless 390px + 1440px, timezone `America/Los_Angeles` | ✅ ไม่มี page error ไม่ล้นแนวนอน |

> การทดสอบ parity สำคัญมาก: มันพิสูจน์ว่า **เว็บกับ backend ตัดสินสาย/ตรงเวลาตรงกันเป๊ะ** ถ้าแก้ตรรกะฝั่งใดฝั่งหนึ่งต้องรันซ้ำ

### 4.5 สถานะฝั่งเว็บ

✅ **เสร็จและ deploy แล้ว** — build ขึ้น IIS site `checkin` ที่ `C:\inetpub\checkin` เมื่อ ~10:20 น. 10 ก.ย. 2026
วาง assets ก่อนเปลี่ยน `index.html` + service worker และเก็บ assets hash เดิมไว้รองรับแท็บที่ยังเปิดค้าง

</details>

---

<details>
<summary><b>5. ฝั่งแอป (Flutter 2 ตัว) — ทำอะไรไปแล้วบ้าง</b></summary>

### 5.1 มี 2 แอป แยก codebase

| | **แอปพนักงาน** | **แอปหัวหน้า** |
|---|---|---|
| โฟลเดอร์ | `flutter_app/` | `flutter_boss_app/` |
| เวอร์ชันใน source | `1.5.0+7` | `1.2.0+4` |
| **เวอร์ชันที่แจกจริงบน production** | ⚠️ `1.2.0+3` (build 25 ส.ค.) | ⚠️ `1.0.0+1` (build 30 ส.ค.) |
| **เวอร์ชันที่ติดตั้งบนเครื่องทดสอบ (MTN NX1)** | ✅ `1.5.0+7` (11 ก.ย.) | ✅ `1.2.0+4` (11 ก.ย.) |
| จุดเด่นเฉพาะตัว | `face_enroll_screen.dart`, `widgets/face_scanner.dart` — **สแกน/บันทึกใบหน้า** | `services/camera_talkback_service.dart` — **กดค้างพูดออกลำโพงกล้อง (TiRTC)** |
| ลายเซ็น APK | คนละใบกับแอปหัวหน้า | debug key (อัปทับตัวเก่าได้ ไม่ต้องถอนติดตั้ง) |
| ขนาด | ~53 MB | 73.8 MB (โตขึ้นเพราะ native lib ของ TiRTC) |
| endpoint แจกไฟล์ | `/app/info`, `/app/download` | `/boss-app/info`, `/boss-app/download` |

### 5.2 แท็บในแอป (เหมือนกันทั้ง 2 ตัว — `lib/screens/tabs/`)

| แท็บ | ทำอะไร |
|---|---|
| `overview_tab` | ภาพรวม + การ์ดสรุปวันนี้ + ป้ายสาย/ตรงเวลา |
| `checkin_tab` | กดเข้า–ออกงาน (ตรวจ geofence + ใบหน้า) |
| `history_tab` | ประวัติลงเวลาของตัวเอง + ปฏิทินรายเดือน |
| `team_tab` | สถานะทีมวันนี้ ใครเข้าแล้ว/ยังไม่เข้า |
| `employees_tab` | รายชื่อ/จัดการพนักงาน (สิทธิ์หัวหน้า) |
| `live_map_tab` | แผนที่ตำแหน่งทีมแบบสด |
| `places_tab` | รายการสถานที่ + รัศมี (ดึงจาก `/reports/geofence`) |
| `camera_tab` | ดูภาพสด CCTV + หมุนกล้อง PTZ + ฟังเสียง + **ปุ่มกดค้างพูด** (เฉพาะแอปหัวหน้า) |
| `profile_tab` | โปรไฟล์ + รูปใบหน้า + ออกจากระบบ |

### 5.3 Service ในแอป (`lib/services/`)

| ไฟล์ | หน้าที่ |
|---|---|
| `api_service.dart` | คุยกับ backend ทุก endpoint |
| `location_service.dart` + `background_service.dart` | **GPS ต่อเนื่อง ส่งพิกัดทุก 60 วินาที** แม้แอปอยู่เบื้องหลัง |
| `tracking_controller.dart` | คุมเปิด/ปิดการติดตาม |
| `face_service.dart` (แอปพนักงาน) | ML Kit face detection + liveness |
| `attendance_service.dart` + `work_schedule.dart` | ตัดสินสาย/ตรงเวลาฝั่งแอป (ต้องตรงกับ backend) |
| `team_status.dart` | สรุปสถานะทีม |
| `employee_registration.dart` + `employee_form_data.dart` + `thai_id.dart` | ลงทะเบียนพนักงาน + ตรวจเลขบัตรประชาชนไทย |
| `camera_talkback_service.dart` (แอปหัวหน้า) | ครอบ TiRTC SDK — ขอ token จาก backend แล้วยิงเสียงตรงไปกล้อง |

### 5.4 ฟีเจอร์ไมค์พูดออกลำโพงกล้อง — สถานะละเอียด

**เขียนเสร็จ + ทดสอบบนเครื่องจริงแล้ว (MTN NX1, Android 16) ผ่านทุกขั้นยกเว้นขั้นสุดท้าย**

| ขั้น | ผล |
|---|---|
| ปุ่มโผล่เมื่อ `talkback_ready=true` | ✅ (หลังแก้บั๊ก) |
| ขอสิทธิ์ไมค์ตอนกดครั้งแรกเท่านั้น | ✅ |
| `POST /camera/talkback/token` | ✅ 200 |
| `TiRtc.initialize` | ✅ `code=0` |
| SDK ต่อเซิร์ฟเวอร์ Tange | ✅ resolve `ep-tirtc.tange365.com` |
| Tange ตอบกลับ | `40402 access credential not found` ← **ถูกต้องแล้วสำหรับค่าปลอม** |
| token รั่วลง log | ✅ ไม่พบเลย (0 hits) |
| **พูดแล้วได้ยินที่ลำโพงกล้องจริง** | ❌ **ยังทดสอบไม่ได้ — รอ credential จริง** |

**บั๊กที่แก้ไปแล้ว (บันทึกไว้กันพลาดซ้ำ):** ปุ่ม "กดค้างเพื่อพูด" เคยไม่โผล่เพราะวางไว้ใต้เงื่อนไขเดียวกับปุ่ม "ฟังเสียง" ทั้งที่เป็นคนละเส้นทาง — **ฟังเสียง** ต้องมี `ffmpeg` บนเซิร์ฟเวอร์, **พูดออกกล้อง** ยิงตรงผ่าน TiRTC ไม่ผ่าน ffmpeg เลย แยกเป็นสองส่วนอิสระแล้ว + มีเทสต์คุม

**เทสต์:** 107 tests ผ่านหมด (เพิ่มใหม่ 29 ข้อ) · `flutter analyze` ไม่มี issue

### 5.5 สถานะฝั่งแอป — build เสร็จแล้ว เหลือแค่ publish

**อัปเดต 11 ก.ย. 2026:** build ทั้ง 2 แอปสำเร็จบนเครื่อง dev (`C:\project_job_part-time`, user `Pac-Man45`, Flutter 3.38.2 / Dart 3.10.0) และ **ติดตั้ง + ทดสอบบน MTN NX1 (Android 16, API 36) ผ่านแล้ว** — ดูผลทดสอบหัวข้อ 5.6

| | แอปพนักงาน | แอปหัวหน้า |
|---|---|---|
| ไฟล์ที่ build ได้ | `flutter_app\build\app\outputs\flutter-apk\app-release.apk` (80.2 MB) | `flutter_boss_app\build\app\outputs\flutter-apk\app-release.apk` (74.0 MB) |
| เวอร์ชันใน APK | `1.5.0+7` (verify ด้วย `aapt2 dump badging`) | `1.2.0+4` |
| ลายเซ็น | debug keystore SHA-256 `41C0464D…9625E269` | ใบเดียวกัน |

> ✅ **ลายเซ็นตรงกับ APK ชุดเดิม** → ติดตั้งทับได้เลย ไม่ต้องถอนติดตั้ง
> ⚠️ แต่ **ผู้ใช้จะถูก logout** ทุกครั้งที่ติดตั้งทับ (ยืนยันแล้วรอบนี้ — แอปหัวหน้าเด้งกลับหน้า login) ต้องบอกผู้ใช้ให้ล็อกอินใหม่

**ตัวบล็อกที่เหลือ: publish ขึ้น production เท่านั้น** — เครื่อง dev เครื่องนี้ **ไม่ใช่เครื่อง production** (ตรวจแล้ว: ไม่มี `C:\inetpub\checkin`, ไม่มี scheduled task `MardodiCheckinAPI`, ไม่มี service cloudflared, ไม่มีอะไร listen พอร์ต 8001) จึงรัน `publish-apk.ps1` จากที่นี่ไม่ได้ — ตรงกับกับดักข้อ 5 → **ต้องก๊อป APK 2 ไฟล์ไปรันบนเครื่อง production**

### 5.6 ✅ ผลทดสอบบนเครื่องจริง — MTN NX1, Android 16 (11 ก.ย. 2026)

| รายการ | ผล |
|---|---|
| `flutter analyze` ทั้ง 2 แอป | ✅ No issues found |
| `flutter test` แอปพนักงาน | ✅ 81 tests ผ่าน |
| `flutter test` แอปหัวหน้า | ✅ 120 tests ผ่าน |
| `flutter build apk --release` ทั้ง 2 แอป | ✅ exit 0 |
| `adb install -r` ทับของเดิม | ✅ Success ทั้งคู่ (ไม่ต้องถอนติดตั้ง) |
| เปิดแอปพนักงาน | ✅ ไม่มี crash / ไม่มี FATAL ใน logcat |
| เปิดแอปหัวหน้า | ✅ ไม่มี crash — ขึ้นหน้า login (session ถูกล้างจากการติดตั้งทับ) |
| GPS + background tracking | ✅ จับพิกัด `13.88713, 100.50648` ส่ง ping ต่อเนื่อง |
| ดึง `/reports/geofence` จาก production | ✅ ขึ้น `Motta & Montipa (Head office)` รัศมี 0.50 กม. + `ถึงบ้านแล้ว` รัศมี 0.20 กม. |
| ตรรกะ `category=home` ไม่ตัดสินสาย | ✅ ขึ้น "อยู่บ้าน — ไม่ได้ไปทำงาน" และป้าย "ออกงานไม่ได้" ตามที่ตั้งไว้ |
| ป้ายสาย/ตรงเวลาที่ออฟฟิศจริง | ⏳ **ยังทดสอบไม่ได้ — ต้องไปยืนในรัศมี 0.5 กม. ของออฟฟิศ** (ตอนทดสอบอยู่ห่าง 4.00 กม.) |

**บั๊กที่เจอและแก้ในรอบนี้:** หน้าเช็คอินขึ้น `ห่างออฟฟิศ 0.07 กม.` ทั้งที่ออฟฟิศจริงห่าง 4.00 กม. — ตัวเลขนั้นคือระยะถึง**บ้าน** เพราะ `_distanceKm` เก็บค่าจาก `nearestOffice()` แบบไม่ใส่ `workOnly` (= สถานที่ใกล้สุดทุกประเภท) แต่ป้ายเขียนตายตัวว่า "ออฟฟิศ" → พนักงานที่อยู่บ้านจะอ่านผิดเป็นว่ายืนอยู่ข้างออฟฟิศ **แก้แล้วทั้ง 2 แอป** ให้ใช้ `_workDistanceKm` + `_nearestOfficeName` (มีอยู่ในโค้ดแล้ว) จึงขึ้นว่า `ห่าง Motta & Montipa (Head office) 4.00 กม.` และลบฟิลด์ `_distanceKm` ที่ไม่ได้ใช้แล้วออก

</details>

---

<details>
<summary><b>6. Backend — API, ฐานข้อมูล, และกฎธุรกิจ</b></summary>

### 6.1 Router ทั้งหมด (`backend/app/routers/`)

| Router | Endpoint | ใช้ทำอะไร |
|---|---|---|
| `auth.py` | `POST /auth/register`, `POST /auth/login` | สมัคร/ล็อกอิน คืน JWT |
| `checkins.py` | `POST /checkins`, `GET /checkins/me` | ลงเวลาเข้า–ออก (ตรวจ geofence + ใบหน้า + แนบรูป) |
| `faces.py` | `POST /faces/enroll`, `GET /faces/me`, `GET /faces/employee/{id}`, `PUT /faces/order`, `DELETE /faces/{id}`, `GET /faces/{id}/photo` | คลังรูปใบหน้า — ใบแรกหลังจัดลำดับ = รูปประจำตัว |
| `locations.py` | `POST /locations/ping`, `GET /locations/live`, `GET /locations/trail/{id}` | GPS ต่อเนื่อง + ตำแหน่งสด + เส้นทางย้อนหลัง |
| `reports.py` | `GET /reports/geofence`, `/employees`, `/employees/{id}/history`, `/calendar`, `/team-calendar` | ข้อมูลให้ปฏิทินและรายงาน |
| `employee_management.py` | `POST /employee-management`, `PATCH /employee-management/{id}` | ลงทะเบียน/แก้ไขพนักงาน |
| `employment_options.py` | `GET|POST /employment-options` | ตัวเลือกแผนก/ตำแหน่ง |
| `addresses.py` | `GET /addresses/postal-code/{code}` | เติมตำบล/อำเภอ/จังหวัดจากรหัสไปรษณีย์ |
| `camera.py` | `GET /camera/status`, `POST /camera/talkback/token`, `POST /camera/ptz`, `/ptz/stop`, + สตรีม | ภาพสด, หมุนกล้อง, เสียง, ไมค์ |
| `chat.py` 🆕 | `GET /chat/contacts`, `/messages/{peer}`, `POST /messages/{peer}`, `/read/{peer}` | แชทภายใน |
| `line.py` | `POST /line/webhook`, `GET /line/status`, `POST /line/test` | แจ้งเตือนเข้ากลุ่ม LINE |
| `app_release.py` | `GET /app/info`, `/app/download`, `/boss-app/info`, `/boss-app/download` | แจก APK ทั้งสองแอป |

### 6.2 ตารางในฐานข้อมูล

| ตาราง | เก็บอะไร |
|---|---|
| `employees` | พนักงาน/หัวหน้า — `employee_code`, `full_name`, `email`, `hashed_password`, `is_manager`, **`national_id_encrypted` + `national_id_hash`** (เข้ารหัส ไม่เก็บเลขดิบ), เบอร์, ที่อยู่ 5 ฟิลด์, แผนก, ตำแหน่ง, วันเริ่มงาน |
| `checkins` | log เข้า–ออก: เวลา, พิกัด, ระยะจากสถานที่, อยู่ในเขต?, **`office_name`**, พบใบหน้า?, path รูป |
| `location_pings` | พิกัด GPS ต่อเนื่องจาก background service + ชื่อสถานที่ใกล้สุด |
| `face_profiles` | คลังรูปใบหน้าอ้างอิง + ลำดับการแสดง |
| `employee_events` | timeline เหตุการณ์ของพนักงาน (`event_type`, `title`, `detail` JSON, ใครเป็นคนทำ) |
| `employment_options` | ตัวเลือกแผนก/ตำแหน่ง (`kind` + `name`) |
| `chat_messages` 🆕 | ข้อความแชท + `read_at` + กันส่งซ้ำด้วย `(sender_id, client_id)` |

> **Migration:** ไม่ได้ใช้ Alembic — `app/database.py` จะ `ALTER TABLE` เติมคอลัมน์ที่ขาดให้อัตโนมัติตอนสตาร์ต
> **เพิ่มคอลัมน์ใหม่ต้องไปเติมชื่อใน `_ADDED_COLUMNS` ด้วย ไม่งั้นตารางเก่าจะไม่ถูกอัป**

### 6.3 กฎตัดสิน สาย / ตรงเวลา / ออกก่อน

**ตอนเข้างาน (`kind = "in"`)** — เส้นตัดสิน = `WORK_START_TIME + LATE_GRACE_MINUTES`

| กด | ผล | ข้อความ |
|---|---|---|
| 08:15 | ตรงเวลา | `ตรงเวลา (ก่อนเวลา 15 นาที)` |
| 08:30 | ตรงเวลา | `ตรงเวลา` |
| 08:31 | **สาย** | `สาย 1 นาที` |
| 10:05 | **สาย** | `สาย 1 ชม. 35 นาที` |

> ⚠️ **จำนวนนาทีนับจาก 08:30 เสมอ ไม่ใช่นับจากเส้นผ่อนผัน** — ตั้งผ่อนผัน 15 นาที เข้า 08:46 → รายงาน "สาย 16 นาที" (เพราะนั่นคือเลขที่ HR ใช้)

**ตอนออกงาน (`kind = "out"`)**

| กด | ผล | ข้อความ |
|---|---|---|
| 16:30 | **ออกก่อนเวลา** | `ออกก่อนเวลา 1 ชม.` |
| 17:30 | ครบเวลา | `ครบเวลางาน` |
| 18:45 | ครบเวลา | `ครบเวลางาน (เกินเวลา 1 ชม. 15 นาที)` |

**กรณีไม่ตัดสินเลย:** ลงเวลาที่จุด `category=home` · ตั้ง `ATTENDANCE_RULES_ENABLED=false` · `kind` ไม่ใช่ `in`/`out`

**ไฟล์ที่ถือตรรกะนี้ (3 ที่ ต้องตรงกันเสมอ):**
`backend/app/work_schedule.py` · `frontend/src/lib/work-schedule.js` · `lib/services/work_schedule.dart` (ทั้ง 2 แอป)

### 6.4 ข้อจำกัดที่ "ตั้งใจให้เป็น" — คนทำต่อต้องรู้

| ข้อจำกัด | ผลที่ตามมา | ถ้าจะแก้ |
|---|---|---|
| **เทียบเฉพาะเวลาในวัน ไม่ดูวันที่** | ลงเวลาตอนตี 1 จะนับว่า "มาก่อนเวลา" ไม่ใช่สายข้ามวัน | ถ้ามีกะดึกต้องออกแบบใหม่ทั้งก้อน |
| **ไม่เก็บสถานะสายลง DB** — คำนวณสดทุกครั้ง | แก้เกณฑ์ย้อนหลังแล้วรายงานเก่าเปลี่ยนตามทันที (ข้อดี) แต่ล็อกสถานะ ณ วันนั้นไม่ได้ | เพิ่มคอลัมน์ใน `checkins` (งานคนละก้อน) |
| **ไม่รู้จักวันหยุด/วันลา** | เสาร์–อาทิตย์กด 10 โมงก็ขึ้นว่าสาย | ต้องทำตารางวันหยุด — **ยังไม่มีในระบบ** |
| **เวลางานเป็นค่าเดียวทั้งระบบ** | รองรับหลายกะไม่ได้ | ดูผลกระทบกับธุรกิจห้างในหัวข้อ 1.5 |
| **ใบหน้าเป็น detection + liveness ไม่ใช่ 1:1 matching** | ยืนยันว่า "เป็นคนจริง" ได้ แต่ไม่ยืนยันว่า "เป็นคุณ" | ต้องเพิ่ม face embeddings (FaceNet) + เก็บรูปต้นแบบ |

</details>

---

<details>
<summary><b>7. ค่าตั้งค่า (.env) — ปุ่มทั้งหมดที่หมุนได้โดยไม่ต้องแก้โค้ด</b></summary>

ไฟล์ที่ production อ่านจริง: **`checkin-system/backend/.env`** (ตัวอย่างอยู่ที่ `backend/.env.example`)

### 7.1 สถานที่ + เวลางาน (ตัวที่แก้บ่อยสุด)

```env
OFFICES=[{"name":"Motta & Montipa (Head office)","lat":13.9040518,"lng":100.5391995,"radius_km":0.5,"category":"work"}]
WORK_START_TIME=08:30
WORK_END_TIME=17:30
LATE_GRACE_MINUTES=0
EARLY_LEAVE_GRACE_MINUTES=0
ATTENDANCE_RULES_ENABLED=true
```

> ⚠️ **`.env` ต้องเป็น UTF-8 ไม่มี BOM** (ชื่อสถานที่มีอักขระ `&`) และ **`OFFICES` ต้องอยู่บรรทัดเดียว ห้ามตัดบรรทัด**
> ค่าพวกนี้อ่านตอน process เริ่มเท่านั้น — แก้แล้วต้อง restart backend
> ถ้าเว้น `OFFICES` ว่าง ระบบถอยไปใช้ `OFFICE_LAT`/`OFFICE_LNG`/`GEOFENCE_RADIUS_KM` เป็นสถานที่เดียว (เข้ากันได้กับของเดิม)

**`category` ที่รองรับ:** `work` (ที่ทำงาน) · `home` (บ้าน — ไม่ตัดสินสาย, ตั้ง `allow_checkout:false` ได้) · `hospital` (โรงพยาบาล)

### 7.2 กลุ่มอื่น

| กลุ่ม | ตัวแปร |
|---|---|
| ฐานข้อมูล/ระบบ | `DATABASE_URL`, `SECRET_KEY`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `STORAGE_DIR`, `TIMEZONE_OFFSET_HOURS`, `ALLOWED_ORIGINS` |
| LINE | `LINE_NOTIFY_ENABLED`, `LINE_CHANNEL_ACCESS_TOKEN`, `LINE_CHANNEL_SECRET`, `LINE_TARGET_ID` |
| กล้อง PTZ | `CAMERA_PTZ_ENABLED`, `_HOST`, `_PORT`, `_USERNAME`, `_PASSWORD`, `_SPEED`, `_ZOOM_SPEED`, `_DURATION_MS`, `_MAX_DURATION_MS`, `_INVERT_PAN`, `_INVERT_TILT`, `CAMERA_TIMEOUT_SECONDS` |
| เสียงจากกล้อง | `CAMERA_AUDIO_ENABLED`, `CAMERA_RTSP_URL`, `CAMERA_AUDIO_BITRATE`, `FFMPEG_PATH` |
| ไมค์พูดออกกล้อง (TiRTC) | `CAMERA_TIRTC_ENABLED`, `_APP_ID`, `_ACCESS_KEY_ID`, **`_SECRET_KEY_ID`**, `_REMOTE_ID`, `_TOKEN_TTL_SECONDS`, `_STREAM_ID` |

> 🔒 **`CAMERA_TIRTC_SECRET_KEY_ID` ใส่ได้เฉพาะใน `backend/.env` — ห้ามใส่ในแอปและห้าม commit ลง git**

### 7.3 Rollback แบบไม่แตะโค้ด

```env
# กลับไปใช้สถานที่เดิมก่อนย้ายบริษัท
OFFICES=[{"name":"MARDODI","lat":13.9231953,"lng":100.5195808,"radius_km":2.0,"category":"work"},{"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0,"category":"hospital"},{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2,"allow_checkout":false,"category":"home"}]

# ปิดการแจ้งเตือนสายทั้งระบบ
ATTENDANCE_RULES_ENABLED=false
```

</details>

---

<details>
<summary><b>8. Production — เครื่องอยู่ไหน อะไรรันยังไง</b></summary>

### 8.1 โครง deploy

```
มือถือ/เบราว์เซอร์ ──► https://thanakronpart-time.com ──(cloudflared)──► IIS :80 ┬─ React static (C:\inetpub\checkin)
                                                                                  └─ /auth /reports /checkins ... → uvicorn :8001
```

โดเมนที่ใช้ได้ทั้งหมดชี้ที่เดียวกัน: `thanakronpart-time.com`, `www.…`, `api.…`

### 8.2 บริการที่ต้องขึ้นเองตอนบูต

| ส่วน | กลไก |
|---|---|
| IIS (เว็บ :80) | Windows Service แบบ Automatic |
| FastAPI (:8001) | Scheduled Task แบบ AtStartup |
| Cloudflare Tunnel | Windows Service แบบ Automatic |
| แผงควบคุม GUI | Scheduled Task `ThanakonCheckinPanel` แบบ AtLogOn (หน่วง 25 วิ, รันด้วย `-AutoStart`) |

> ⚠️ **ชื่อ Scheduled Task ของ backend ไม่ตรงกันในเอกสาร** — บันทึก production 10 ก.ย. ใช้ **`MardodiCheckinAPI`** (ชื่อเก่าติดมาจากสมัย MARDODI) ส่วน `README.md` เขียนว่า `ThanakonBoxCheckinAPI`
> **ให้เชื่อ `MardodiCheckinAPI`** เพราะนั่นคือตัวที่ restart แล้วได้ผลจริง — และควรแก้ README ให้ตรงกันในรอบหน้า

### 8.3 คำสั่งที่ใช้บ่อย

```powershell
# เริ่มทุกอย่าง (แผงควบคุม GUI)
.\START_PART_TIME.bat

# ติดตั้งครั้งแรก (PowerShell แบบ Administrator)
cd checkin-system\deploy
.\windows-server\install-iis-site.ps1        # IIS + URL Rewrite + ARR + build React
.\windows-server\install-backend-task.ps1    # backend เป็น Scheduled Task ที่ :8001
.\cloudflare\setup-tunnel.ps1 -InstallService

# restart backend
Start-ScheduledTask -TaskName MardodiCheckinAPI

# ตรวจว่าขึ้นจริง
curl https://thanakronpart-time.com/health
curl https://thanakronpart-time.com/reports/geofence
curl https://thanakronpart-time.com/app/info
curl https://thanakronpart-time.com/boss-app/info
```

### 8.4 ⚠️ เรื่องเครื่อง — ระวังสับสน

เอกสารเก่า (`HANDOVER_TALKBACK_2026-09-06.md`) บันทึกว่า **เครื่องพัฒนากับเครื่อง production เป็นคนละเครื่อง** — เคยรัน `publish-apk.ps1` แล้วไฟล์ลงเครื่อง dev ไม่ได้ขึ้น production
**ก่อนสั่ง publish อะไรก็ตาม ให้ยิง `/app/info` และ `/boss-app/info` บนโดเมนจริงเช็คก่อนเสมอ** ว่าเปลี่ยนจริงหรือไม่

### 8.5 สำรองก่อน deploy รอบล่าสุด

```text
C:\Users\Administrator\AppData\Local\CheckinDeployBackups\office-move-20260910-102032
  backend.env    ค่าตั้งค่าก่อนย้าย (มีข้อมูลลับ เก็บเฉพาะผู้ดูแล)
  site\          ไฟล์เว็บไซต์ก่อน deploy
```

ย้อน UI = คืนไฟล์จาก `site\` ไปยัง IIS path เดิม แล้วตรวจ cache ของ PWA อีกรอบ

### 8.6 Dev environment (Docker — แยกจาก production สนิท)

```powershell
cd checkin-system
copy .env.example .env
docker compose up -d --build
docker compose run --rm backend python seed.py
```

| | พอร์ต | เหตุผล |
|---|---|---|
| API ใน container | `8010` | เลี่ยง 8000/8001 ที่ใช้อยู่ |
| PostgreSQL ใน container | `5433` | เลี่ยง 5432 ของ production |

`LINE_NOTIFY_ENABLED` และ `CAMERA_PTZ_ENABLED` ถูกบังคับเป็น `false` ใน compose เพื่อไม่ให้ container ทดสอบยิงแจ้งเตือนเข้ากลุ่ม LINE จริงหรือสั่งกล้องจริง

บัญชีตัวอย่างจาก `seed.py`: พนักงาน `EMP001` / `password123` · หัวหน้า `BOSS001` / `boss12345`

</details>

---

<details>
<summary><b>9. สถานะงาน ณ 10 ก.ย. 2026 — เสร็จอะไร ค้างอะไร</b></summary>

### 9.1 ✅ เสร็จแล้ว

- ย้ายพิกัดออฟฟิศเป็น `Motta & Montipa (Head office)` ใน `backend/.env` และยืนยันบนโดเมนจริงแล้ว
- ตั้งเวลาทำงาน 08:30–17:30 ผ่อนผัน 0 นาที และเปิด `ATTENDANCE_RULES_ENABLED`
- ตรรกะสาย/ตรงเวลา/ออกก่อน — ครบทั้ง backend, เว็บ, และแอปทั้งสอง (ฝั่งโค้ด)
- เว็บ build + deploy ขึ้น IIS แล้ว (ป้ายสถานะ, สรุปรายเดือนมาสาย/ออกก่อน, ปฏิทินหัวหน้า, ประวัติรายบุคคล)
- ทดสอบ parity 11,520 กรณี เว็บ ↔ backend ตรงกันหมด
- ฟีเจอร์ไมค์พูดออกลำโพงกล้อง — เขียนเสร็จ + 107 tests ผ่าน + ทดสอบเส้นทางบนเครื่องจริงครบทุกขั้น
- ระบบ CCTV (โปรเจกต์แยก) — แก้จบแล้ว กล้องพูดได้จริงเมื่อ 7 ก.ย. 2026

### 9.2 ⏳ ค้าง / ยังไม่ได้ทำ

| # | เรื่อง | ตัวบล็อก |
|---|---|---|
| 1 | ~~build APK ใหม่ทั้ง 2 แอป~~ ✅ **เสร็จ 11 ก.ย.** เหลือแค่ **publish ขึ้น production** | เครื่อง dev ไม่ใช่เครื่อง production → ต้องก๊อป APK ไปรัน `publish-apk.ps1` บนเครื่อง production |
| 2 | **ฟีเจอร์ไมค์ใช้จริงไม่ได้** | รอ credential จาก Tange (`business@tange.ai`) — ตัวบล็อกที่นานสุด **เริ่มขอได้เลยไม่ต้องรอข้ออื่น** |
| 3 | **โค้ด backend ตัว TiRTC ยังไม่ขึ้น production** | ยิง `/camera/status` แล้วไม่มี prefix ของ TiRTC = ยังรัน `camera.py` ตัวเก่า |
| 4 | ตารางวันหยุด/วันลา | ยังไม่มีในระบบเลย |
| 5 | ที่อยู่แบบตัวอักษรของออฟฟิศใหม่ | ดึงจาก Google Maps ไม่ได้ (หน้า render ด้วย JS) — ต้องก๊อปมาเติมเอง |
| 6 | รายงาน export | ยังไม่ได้เพิ่ม / ยังไม่ได้เปลี่ยน API รายงาน |
| 7 | ยืนยัน LINE ส่งถึงกลุ่มจริงแบบ end-to-end | ทดสอบด้วย mock `push_text` 6 กรณีผ่าน แต่ยังไม่ได้ส่งเข้ากลุ่มจริง |
| 8 | ~~ทดสอบ APK กับเครื่อง Android จริงหลังย้ายออฟฟิศ~~ | ✅ **เสร็จ 11 ก.ย.** — MTN NX1 ผ่าน ดูหัวข้อ 5.6 · เหลือทดสอบป้ายสาย/ตรงเวลาตอนไปยืนที่ออฟฟิศจริง |

### 9.3 ของค้างใน git

> ✅ **อัปเดต 11 ก.ย. 2026:** ของค้างทั้งหมดที่ลิสต์ไว้ด้านล่าง (ระบบแชท, `work-schedule.js`, tests) **ถูก commit เรียบร้อยแล้ว** ใน `c627aab Major update code balance` และ `1161a2d update SEO Web thanakronpart-time`
>
> branch ปัจจุบัน: **`Film_dev_Part-Time`** (ไม่ใช่ `master` แล้ว) · commit ล่าสุด: `1161a2d`
>
> **ของค้างรอบ 11 ก.ย. (ยังไม่ commit):** `flutter_app/lib/screens/tabs/checkin_tab.dart` และ `flutter_boss_app/lib/screens/tabs/checkin_tab.dart` — แก้ป้ายระยะทางให้บอกชื่อที่ทำงานจริง (ดูหัวข้อ 5.6) · analyze สะอาด + 201 tests ผ่าน

<details>
<summary>บันทึกเดิม ณ 10 ก.ย. (เก็บไว้อ้างอิง — จัดการหมดแล้ว)</summary>

branch ตอนนั้น: **`master`** · commit ล่าสุด: `73e6a2e update code location Company`

**แก้แล้วยังไม่ commit (`M`):**
```
checkin-system/HANDOVER_OFFICE_MOVE_2026-09-10.md
checkin-system/backend/.env.example
checkin-system/backend/app/main.py
checkin-system/deploy/windows-server/web.config
checkin-system/frontend/src/App.jsx
checkin-system/frontend/src/api.js
checkin-system/frontend/src/pages/DashboardPage.jsx
checkin-system/frontend/src/pages/EmployeeHistoryPage.jsx
checkin-system/frontend/vite.config.js
```

**ไฟล์ใหม่ที่ยังไม่ถูก track (`??`) — ถ้าหายคือหายจริง:**
```
checkin-system/backend/app/chat_models.py
checkin-system/backend/app/routers/chat.py
checkin-system/backend/test_chat.py
checkin-system/frontend/src/components/ChatWidget.jsx
checkin-system/frontend/src/components/WorkSchedule.jsx
checkin-system/frontend/src/lib/work-schedule.js
checkin-system/frontend/tests/
```

> ⚠️ **ระบบแชททั้งก้อนยังไม่ได้ commit** และ `work-schedule.js` คือหัวใจของฟีเจอร์ที่เพิ่ง deploy ไป
> เอกสาร talkback ก็บันทึกไว้ว่าไฟล์ฟีเจอร์ไมค์ "ยังไม่ได้ commit" เช่นกัน
> **งานแรกของคนทำต่อควรเป็นการ commit ให้เรียบร้อยก่อนแตะอย่างอื่น**

</details>

</details>

---

<details>
<summary><b>10. งานถัดไป — เรียงตามลำดับที่ควรทำ</b></summary>

### 10.1 publish APK ขึ้น production (เหลือขั้นตอนนี้ขั้นเดียว)

> ✅ **ขั้น 1–3 ทำเสร็จแล้ว 11 ก.ย. 2026** — analyze สะอาด, 201 tests ผ่าน, build ได้ APK ทั้ง 2 ตัว, ลายเซ็นตรงกับของเดิม, ติดตั้งและทดสอบบน MTN NX1 ผ่าน (หัวข้อ 5.6)
> **เหลือแค่ขั้น 4–5** คือเอา APK ไป publish บนเครื่อง production

<details>
<summary>ขั้น 1–3 ที่ทำไปแล้ว (เก็บไว้อ้างอิงตอน build รอบหน้า)</summary>

ทำบน**เครื่องที่มี Flutter + Android SDK**:

1. ใช้ source ปัจจุบันของทั้ง `flutter_app` และ `flutter_boss_app`
2. รัน `flutter analyze` และ `flutter test` ในแต่ละแอปก่อน build
3. Build APK release โดย **รักษา `applicationId` และ signing key เดิมของแต่ละแอป** เพื่อให้อัปเดตทับของเดิมได้

```powershell
cd checkin-system\flutter_app      ; flutter pub get; flutter analyze; flutter test; flutter build apk --release
cd ..\flutter_boss_app             ; flutter pub get; flutter analyze; flutter test; flutter build apk --release
```

ตรวจเวอร์ชัน + ลายเซ็นก่อนส่ง (build-tools 36.1.0):

```powershell
$bt = "$env:LOCALAPPDATA\Android\sdk\build-tools\36.1.0"
& "$bt\aapt2.exe"     dump badging      <apk>   # ต้องได้ versionCode/versionName ตามที่ตั้งใจ
& "$bt\apksigner.bat" verify --print-certs <apk> # ต้องได้ SHA-256 41c0464d…9625e269
```

</details>

**ขั้นที่เหลือ — ทำบนเครื่อง production:**

4. ก๊อป APK 2 ไฟล์นี้จากเครื่อง dev ไปเครื่อง production แล้วรัน:

```powershell
# ไฟล์ต้นทางบนเครื่อง dev (build 11 ก.ย. 2026):
#   checkin-system\flutter_app\build\app\outputs\flutter-apk\app-release.apk       80.2 MB  1.5.0+7
#   checkin-system\flutter_boss_app\build\app\outputs\flutter-apk\app-release.apk  74.0 MB  1.2.0+4

# รันจาก checkin-system บนเครื่อง production; เปลี่ยน path ให้เป็นที่ก๊อปไฟล์ไปวาง
.\deploy\windows-server\publish-apk.ps1 -ApkPath '<employee-release.apk>' -Version '1.5.0+7' -MinSdk 24
.\deploy\windows-server\publish-apk.ps1 -Boss -ApkPath '<boss-release.apk>' -Version '1.2.0+4' -MinSdk 24
```

5. ตรวจว่าขึ้นจริงบน**โดเมนจริง** (ไม่ใช่ localhost) — ต้องเห็นเวอร์ชันเปลี่ยน:

```powershell
curl https://thanakronpart-time.com/app/info        # ต้องได้ "version":"1.5.0+7"  (ก่อน publish = 1.2.0+3)
curl https://thanakronpart-time.com/boss-app/info   # ต้องได้ "version":"1.2.0+4"  (ก่อน publish = 1.0.0+1)
```

6. แจ้งพนักงาน/หัวหน้าให้โหลดตัวใหม่ **และบอกว่าต้องล็อกอินใหม่** (ติดตั้งทับ = session หาย — ยืนยันแล้ว 11 ก.ย.) เพราะแอปไม่มีระบบเตือนอัปเดตในตัว

> APK ที่มีอยู่ใน `flutter_app/thanakon-checkin.apk`, `flutter_boss_app/app-release.apk`, และ `flutter_boss_app/build/app/outputs/flutter-apk/app-release.apk` **เป็น binary เก่าทั้งหมด** — อย่าเอาไป publish แล้วเปลี่ยน metadata ให้ดูเหมือนของใหม่
> APK ไม่ได้อยู่ใน git (ไฟล์ 70+ MB) ต้อง copy เอง — เก็บไว้นอกโฟลเดอร์ IIS จึงไม่ถูกล้างตอน deploy เว็บ และไม่ต้อง restart backend

### 10.2 ปลดบล็อกฟีเจอร์ไมค์ (มี 3 อย่างต้อง deploy ไม่ใช่แค่ APK)

```
1. ขอ credential จาก Tange (business@tange.ai)   ← เริ่มก่อนได้เลย ไม่ต้องรอข้ออื่น
2. commit + push โค้ดจากเครื่องพัฒนา
3. ที่ production: git pull → deploy backend ตัวใหม่ (ต้องมีโค้ด TiRTC)
4. ใส่ CAMERA_TIRTC_* ใน backend\.env → restart
5. publish APK หัวหน้า 1.2.0+4
6. ส่งลิงก์ให้หัวหน้าโหลด (แอปไม่มีระบบเตือนอัปเดตในตัว)
```

**สิ่งที่ต้องขอจาก Tange:** `AppId`, `AccessKeyId`, `SecretKeyId`, `device_id`/`remote_id` ของกล้อง และ **คำยืนยันว่ากล้อง iCam365 ตัวปัจจุบันถูก authorize ให้เชื่อมจาก TiRTC client SDK ของเราได้** (ไม่ใช่ credential ของ test device คนละตัว)

### 10.3 งานที่ค้างอยู่ตามลำดับความสำคัญ

| ลำดับ | งาน | เหตุผล |
|---|---|---|
| ~~1~~ | ~~commit ของค้างทั้งหมด~~ | ✅ เสร็จแล้ว (`c627aab`, `1161a2d`) |
| 1 | **publish APK ขึ้น production (10.1)** | build เสร็จแล้ว แต่ผู้ใช้จริงยังโหลดของเก่าอยู่ — เหลือแค่ก๊อปไฟล์ไปรันบนเครื่อง production |
| 2 | **ทดสอบป้ายสาย/ตรงเวลาที่ออฟฟิศจริง** | ทดสอบบนมือถือผ่านหมดแล้วยกเว้นข้อนี้ ต้องไปยืนในรัศมี 0.5 กม. ของออฟฟิศ (หัวข้อ 5.6) |
| 3 | ขอ credential Tange (10.2) | lead time ยาว เริ่มยิ่งเร็วยิ่งดี |
| 4 | ยืนยันข้อมูลบริษัทกับ HR (หัวข้อ 1.4) | ตัดสินว่าจะขยายเป็นหลายสาขา/หลายกะหรือไม่ |
| 5 | เติมที่อยู่ตัวอักษรของออฟฟิศ | ค้างอยู่ ทำไม่กี่นาที |
| 6 | ตารางวันหยุด/วันลา | ตอนนี้เสาร์อาทิตย์ขึ้นว่าสาย ผิดจริงจังถ้าใช้กับพนักงานหลายคน |
| 7 | export รายงาน (CSV/Excel) ให้ HR | ธุรกิจมีพนักงานหน้าร้านหลายสิบคน HR ต้องใช้ |
| 8 | ยืนยัน LINE end-to-end | เหลือแค่ส่งจริงเข้ากลุ่มหนึ่งครั้ง |
| 9 | แก้ชื่อ Scheduled Task ใน README ให้ตรงกับของจริง | เอกสารขัดกันอยู่ (หัวข้อ 8.2) |
| 10 | แยก bundle เว็บ (เตือน > 500 kB) | คุณภาพ ไม่เร่งด่วน |

</details>

---

<details>
<summary><b>11. อีก 2 ระบบที่ทำไว้ (สรุปย่อ)</b></summary>

### 11.1 บันทึกเส้นทางไรเดอร์ — บางบัวทอง (`F:\GitHub\frontend_film_dev`)

เว็บแอปให้ไรเดอร์บันทึกทุกจุดที่ไปส่ง/แวะในเขตบางบัวทอง นนทบุรี

| | |
|---|---|
| Stack | FastAPI + SQLAlchemy + **SQLite** (`backend/rider_log.db`) + React (Vite) + Leaflet/OpenStreetMap |
| ฟีเจอร์ | บันทึก log ด้วย GPS หรือกรอกเอง · ตาราง + แผนที่หมุดสีตามประเภท · กรอง/ค้นหา · **export CSV** · สมุดที่อยู่ลูกค้า · ปุ่ม 🛵 "ไปส่ง" กรอกข้อมูลลูกค้าให้อัตโนมัติ · log ผูกกับลูกค้า (`customer_id`) |
| ของเด็ด | **OCR ค้นหาลูกค้าจากรูปถ่าย** — ถ่ายรูปหน้าจอแอปส่งของที่วงชื่อลูกค้าด้วยปากกาแดง → OpenCV หาวงสีแดง (HSV threshold) → ครอป → Tesseract (ไทย+อังกฤษ) → fuzzy match กับรายชื่อลูกค้า |
| ⚠️ กับดัก | ต้องใช้ **Python 3.13 เท่านั้น** (3.14 ยังไม่มี wheel ของ `pydantic-core`) · backend **ต้องอยู่พอร์ต 8000** ไม่งั้น Vite proxy พัง · `tessdata` แถมมาแล้วแต่ **ต้องติดตั้งโปรแกรม Tesseract เองบนเครื่อง** · Windows MAX_PATH: `dev.ps1` ใช้ `subst` แก้ปัญหา `spawn esbuild.exe ENOENT` |
| รัน | `./dev.ps1` (Windows) หรือ `./dev.sh` — ยกทั้ง backend + frontend พร้อมกัน |
| Production | backend serve `frontend/dist` เอง พอร์ตเดียว ไม่ต้อง proxy/CORS — GPS ต้องใช้ HTTPS |
| หมายเหตุ | `F:\GitHub\backend_film_dev` เป็นสำเนาเก่าของ backend ตัวนี้ ไม่ใช่โปรเจกต์แยก |

### 11.2 CCTV Smart System (`F:\GitHub\frigate-dev`)

Frigate NVR + ระบบสั่งกล้องเล่นเสียงออกลำโพง — ดูรายละเอียดเต็มที่ `CCTV_SYSTEM_HANDOFF.md` (อัปเดต 7 ก.ย. 2026)

**สถานะ: 🟢 แก้จบแล้ว กล้องพูดได้จริง** ค่าที่ถูกต้องคือ:

```
CAMERA_SPEAKER_FILE=/mnt/mmc01/0/welcome_a2.wav
CAMERA_SPEAKER_TIMEOUT_S=8
```

**บทเรียน 3 ข้อที่ห้ามลืม:**

1. การ์ด mount ที่ `/mnt/mmc01/0/` (มี `0/` ต่อท้าย) **ไม่ใช่** `/mnt/mmc01/` — ค่าเดิมชี้ผิดกล้องเลยไม่เล่นอะไรเลยสักครั้ง
2. **เฟิร์มแวร์ไม่อ่าน WAV header** — อ่านไบต์ดิบที่ 8000 ไบต์/วินาที = **G.711 A-law 8 kHz เท่านั้น** ไฟล์ PCM 16-bit จะออกมาเป็นเสียงซ่ายาวสองเท่า
3. **ยืนยันจากนอกกล้องได้** — เวลาที่ `playaudio` ตอบกลับ = `1.0 วิ + ขนาดไฟล์ ÷ 8000` วัดซ้ำได้ตรงทุกครั้ง (ตอบ ~1.0 วิ = ไฟล์หายจากการ์ดแล้ว) และ `TIMEOUT_S` ต้องมากกว่าคลิปที่ยาวที่สุดบนการ์ดเสมอ ไม่งั้นจะถูกนับเป็น timeout แล้ว retry ยิงซ้ำทับเสียงเดิม

</details>

---

<details>
<summary><b>12. กับดักที่เคยเจอ — อ่านก่อนแตะโค้ด</b></summary>

| # | กับดัก | รายละเอียด |
|---|---|---|
| 1 | **ชื่อ route เว็บชนกับ path API** | API ไม่มี `/api` นำหน้า — หน้าเว็บจึงใช้ `/face-records` ไม่ใช่ `/faces` **เพิ่ม router ใหม่ใน backend ต้องไปเติมชื่อในกฎ `ProxyToBackend` ของ `deploy/windows-server/web.config` ด้วย** |
| 2 | **`.env` มี BOM = พัง** | ชื่อสถานที่มี `&` ต้องเป็น UTF-8 ไม่มี BOM และ `OFFICES` ต้องอยู่บรรทัดเดียว |
| 3 | **แก้ตรรกะเวลาต้องแก้ 3 ที่** | `backend/app/work_schedule.py` + `frontend/src/lib/work-schedule.js` + `lib/services/work_schedule.dart` (×2 แอป) แล้วรัน parity test ซ้ำ |
| 4 | **`Config.offices` ใน Flutter เป็นแค่ fallback** | ตัวตัดสินคือ backend เสมอ แอปดึงสถานที่จาก `/reports/geofence` — แก้ `OFFICES` แล้ว restart พอ ไม่ต้อง build APK |
| 5 | **publish-apk เขียนลงเครื่องที่รันคำสั่งเท่านั้น** | เคยรันบนเครื่อง dev แล้วนึกว่าขึ้น production — ต้องเช็ค `/app/info` บนโดเมนจริงทุกครั้ง |
| 6 | **ติดตั้ง APK ทับ = ผู้ใช้ถูก logout** | ระบบถอนตัวเก่าก่อน ข้อมูลในแอปถูกล้าง ต้องบอกผู้ใช้ให้ล็อกอินใหม่ |
| 7 | **"ฟังเสียง" กับ "พูดออกกล้อง" คนละเส้นทาง** | ฟังเสียงต้องมี `ffmpeg` บนเซิร์ฟเวอร์ · พูดยิงตรงผ่าน TiRTC ไม่ผ่าน ffmpeg — อย่าเอาไปผูกเงื่อนไขเดียวกัน (เคยพลาดมาแล้ว) |
| 8 | **เลขวงแลนชนกัน `192.168.1.x`** | เคยสแกนวงแลนบ้านเพื่อนแล้วสรุปผิดว่า "กล้องหลุดจากวงแลน" ทั้งที่กล้องปกติ — ตรวจว่าเครื่องต่ออยู่วงไหนก่อนสรุป |
| 9 | **เพิ่มคอลัมน์ DB ต้องเติมใน `_ADDED_COLUMNS`** | ไม่ได้ใช้ Alembic — `app/database.py` `ALTER TABLE` เองตอนสตาร์ต ลืมเติมชื่อ = ตารางเก่าไม่ถูกอัป |
| 10 | **สถานะย้อนหลังคำนวณตามเกณฑ์ปัจจุบัน** | ไม่ใช่ snapshot ของเกณฑ์ ณ วันนั้น — แก้ `WORK_START_TIME` แล้วรายงานย้อนหลังเปลี่ยนตามทันที |
| 11 | **กล้องเว็บต้อง HTTPS** | บันทึกใบหน้าผ่านเบราว์เซอร์ใช้ได้เฉพาะ HTTPS หรือ `localhost` |
| 12 | **Docker Desktop อยู่ที่ F: ไม่ใช่ C:** | ติดตั้งที่ `F:\Docker`, data ที่ `F:\DockerData` — ลงใหม่ต้องใส่ flag ครบทั้ง `--installation-dir` และ `--wsl-default-data-root` |

</details>

---

<details>
<summary><b>13. ไฟล์เอกสารที่ควรอ่านต่อ</b></summary>

### ในโปรเจกต์ระบบลงเวลา (`F:\GitHub\project_job_part-time\checkin-system\`)

| ไฟล์ | เนื้อหา |
|---|---|
| `README.md` | ภาพรวมระบบ + วิธีรันทุกส่วน + API + ตาราง DB |
| `คู่มือการใช้งาน.md` | คู่มือผู้ใช้ (หัวหน้า/พนักงาน) + ตาราง path หน้าเว็บและ API + ปัญหาที่พบบ่อย |
| `HANDOVER_OFFICE_MOVE_2026-09-10.md` | ⭐ รายละเอียดเต็มของการย้ายบริษัท + ตรรกะสาย/ตรงเวลา + ผลตรวจ + rollback + งาน APK ที่ค้าง |
| `HANDOVER_TALKBACK_2026-09-06.md` | ⭐ ฟีเจอร์ไมค์พูดออกกล้อง + Tailscale + ลำดับ deploy + สิ่งที่ต้องขอจาก Tange |
| `RUN_LOCAL.md` | วิธีรันบนเครื่องตัวเอง |
| `SERVER_MANAGER.md` · `DEPLOY.md` | จัดการเซิร์ฟเวอร์ / deploy |
| `TRAVEL_ANALYSIS.md` | วิเคราะห์ข้อมูลการเดินทางจาก Google Takeout |
| `deploy/cloudflare/CLOUDFLARE_TUNNEL_SETUP.md` | ตั้ง tunnel + ตารางแก้ปัญหา |
| `deploy/camera/CAMERA_SETUP.md` | ตั้งกล้อง CCTV |
| `deploy/windows-server/DEPLOY_WINDOWS_SERVER.md` | deploy แบบมี public IP |

### โปรเจกต์อื่น

| ไฟล์ | เนื้อหา |
|---|---|
| `F:\GitHub\frigate-dev\CCTV_SYSTEM_HANDOFF.md` | ⭐ ระบบ CCTV ครบทั้งก้อน |
| `F:\GitHub\frontend_film_dev\README.md` · `CLAUDE.md` | ระบบบันทึกเส้นทางไรเดอร์ |
| `F:\GitHub\project_job_part-time\CLAUDE.md` | กติกาการใช้ GitNexus (impact analysis ก่อนแก้โค้ด, detect-changes ก่อน commit) |

### เครื่องมือช่วยอ่านโค้ด

โปรเจกต์นี้ index ด้วย **GitNexus** (4,823 symbols, 11,230 relationships, 411 execution flows) — `CLAUDE.md` กำหนดว่า:

- **ต้องรัน impact analysis ก่อนแก้ function/class ใด ๆ** — `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .`
- **ต้องรัน `detect-changes` ก่อน commit**
- `risk: UNKNOWN` ≠ ปลอดภัย — แปลว่าวิเคราะห์ไม่ได้ ต้องยืนยันด้วยวิธีอื่น
- ห้าม rename ด้วย find-and-replace ให้ใช้คำสั่ง `rename` ที่เข้าใจ call graph

</details>

---

## บันทึกท้ายเอกสาร

### อัปเดต 11 ก.ย. 2026 — build + ทดสอบบนเครื่องจริง

- ทำบนเครื่อง dev `C:\project_job_part-time` (ไม่ใช่ `F:\GitHub` ตามที่เอกสารเดิมเขียนไว้) branch `Film_dev_Part-Time` commit `1161a2d`
- ✅ build APK ทั้ง 2 แอปสำเร็จ ติดตั้งและทดสอบบน **MTN NX1 (Android 16)** ผ่าน — รายละเอียดหัวข้อ 5.6
- ✅ แก้บั๊กป้ายระยะทางในหน้าเช็คอินทั้ง 2 แอป (`ห่างออฟฟิศ` โชว์ระยะถึงบ้าน)
- ⚠️ **ยัง publish ขึ้น production ไม่ได้จากเครื่องนี้** — เครื่อง dev กับ production เป็นคนละเครื่องจริงตามที่เอกสารเดิมเตือนไว้ (กับดักข้อ 5) ตรวจยืนยันแล้วว่าเครื่องนี้ไม่มี IIS/cloudflared/scheduled task ของ backend เลย
- ⏳ ป้ายสาย/ตรงเวลายังไม่ได้ทดสอบที่ออฟฟิศจริง เพราะตอนทดสอบอยู่ห่าง 4.00 กม. (นอกรัศมี 0.5 กม.)

### เดิม

- เอกสารนี้เขียนจากการอ่านโค้ดและเอกสารในเครื่อง ณ 10 ก.ย. 2026 ที่ commit `73e6a2e` **พร้อมของแก้ที่ยังค้างใน working tree**
- **หัวข้อ 1 (บริษัท) เป็นส่วนเดียวที่อ้างอิงแหล่งภายนอกและยังไม่ยืนยัน** — ส่วนที่เหลือทั้งหมดตรวจสอบได้จากไฟล์ในเครื่อง
- ถ้าจะอัปเดตเอกสารนี้ ให้แก้ที่ไฟล์เดิม อย่าสร้างไฟล์ใหม่ซ้อน — และอัปเดตตาราง TL;DR ด้านบนให้ตรงด้วยเสมอ
