# แก้ปัญหา: แอปหัวหน้าขึ้น "เซิร์ฟเวอร์ตอบข้อมูลผิดรูปแบบ (text/html)" ที่แท็บกล้อง

เอกสารนี้ใช้บน **เครื่อง production** (เครื่องที่รัน IIS + backend)
ทำตามหัวข้อ [วิธีแก้](#วิธีแก้) อย่างเดียวก็จบ ประมาณ 2 นาที

---

## อาการ

แท็บ "กล้องวงจรปิด" ในแอปหัวหน้าขึ้นข้อความ:

> เช็คสถานะกล้องไม่สำเร็จ: เซิร์ฟเวอร์ตอบข้อมูลผิดรูปแบบ (text/html)
> กรุณาตรวจ IIS reverse proxy ของเส้นทาง /camera/status

ส่วนแท็บอื่น (ลงเวลา, ทีม, แผนที่) ใช้งานได้ปกติ

---

## สาเหตุ

**backend อัปขึ้นไปเรียบร้อยแล้ว แต่ IIS ยังใช้ตารางเส้นทางชุดเก่า**

IIS ตัดสินใจจาก `web.config` ว่า path ไหนต้องส่งต่อไปให้ backend — เป็น
**รายชื่อที่พิมพ์มือ** ในกฎ `ProxyToBackend` ถ้าชื่อ router ไม่อยู่ในรายชื่อนั้น
คำขอจะไม่ไป backend แต่ตกไปเข้ากฎ `StaticFiles` แล้ว IIS ส่ง `index.html`
ของหน้าเว็บ React กลับมาแทน

`web.config` บนเครื่อง production ยังเป็นชุดที่**ไม่มีคำว่า `camera`** อยู่ในรายชื่อ
คำขอ `/camera/status` จึงได้หน้าเว็บ (HTML) กลับไป ไม่ใช่ข้อมูล (JSON)
แอปอ่าน HTML เป็น JSON ไม่ได้ เลยขึ้นข้อความข้างบน

ที่ทำให้มองข้ามง่ายคือ **IIS ตอบกลับด้วยรหัส 200 (สำเร็จ)** ทั้งที่ผลลัพธ์ผิด
การเช็คด้วยรหัสสถานะอย่างเดียวจึงเห็นเป็น "ผ่าน" ตลอด

### ทำไม deploy ไปแล้วยังไม่หาย

ในสคริปต์ `deploy-update.ps1` เดิม คำสั่ง copy `web.config` ถูกวางไว้**ข้างใน**
เงื่อนไข `if (-not $SkipFrontend)` แปลว่า:

```
deploy-update.ps1                  ->  copy web.config ด้วย   (หาย)
deploy-update.ps1 -SkipFrontend    ->  ไม่ copy web.config     (ไม่หาย)
```

`-SkipFrontend` คือตัวเลือกที่คนใช้ตอน "แก้แต่ backend ไม่ได้แตะหน้าเว็บ"
ซึ่งดันเป็น**จังหวะเดียวกับที่มี router ใหม่และต้องอัปเดต `web.config` มากที่สุด**
backend จึงมีเส้นทางครบ แต่ IIS ยังไม่รู้จัก

> แก้ที่ต้นเหตุแล้ว: ย้ายคำสั่ง copy `web.config` ออกมานอกเงื่อนไข ตอนนี้
> `web.config` ถูก copy ทุกครั้งที่ deploy ไม่ว่าจะใส่ `-SkipFrontend` หรือไม่

---

## วิธีแก้

เปิด **PowerShell แบบ Run as Administrator** บนเครื่อง production แล้ว:

```powershell
cd C:\project_job_part-time\checkin-system\deploy\windows-server
git pull
.\deploy-update.ps1
```

จบแล้ว — ท้ายสคริปต์จะตรวจให้เองว่าทุก router ส่งต่อครบไหม

### ถ้าอยากแก้เฉพาะไฟล์เดียว ไม่อยาก deploy ใหม่ทั้งชุด

```powershell
cd C:\project_job_part-time\checkin-system\deploy\windows-server
git pull
Copy-Item .\web.config C:\inetpub\checkin\web.config -Force
```

IIS อ่าน `web.config` ใหม่เองทันที ไม่ต้อง restart อะไรเลย
(ถ้าพาธเว็บไม่ใช่ `C:\inetpub\checkin` ให้เปลี่ยนตามจริง)

---

## วิธีตรวจว่าหายแล้ว

```powershell
cd C:\project_job_part-time\checkin-system\deploy\windows-server
.\deploy-update.ps1 -CheckOnly
```

ดูหัวข้อ **"ตรวจว่า IIS ส่งต่อทุก router ของ backend"** ต้องเป็น `[OK]` ทุกบรรทัด

**ก่อนแก้** จะเห็นแบบนี้:

```
[!]    /camera/ -> HTTP 200 ได้ 'text/html' = ตกไปเป็นหน้าเว็บ React
[!]  router ที่ IIS ยังไม่ส่งต่อ: camera
```

**หลังแก้** ต้องเป็น:

```
[OK]   /camera/ -> ส่งต่อไป backend แล้ว (HTTP 404)
```

> ได้ 404 ถือว่าถูกต้อง — เพราะ `/camera/` เฉยๆ ไม่ใช่เส้นทางที่มีจริง
> (ของจริงคือ `/camera/status`, `/camera/snapshot`) สิ่งที่ตรวจคือ
> **ใครเป็นคนตอบ** ต้องเป็น backend (ตอบ JSON) ไม่ใช่หน้าเว็บ (ตอบ HTML)

ตรวจด้วยมือก็ได้ — บรรทัดเดียว (ใช้ได้ทั้ง PowerShell 5.1 และ 7):

```powershell
curl.exe -s -o NUL -w "%{content_type}" https://thanakronpart-time.com/camera/status
```

| ได้ผลเป็น | แปลว่า |
|---|---|
| `application/json` | ถูกต้องแล้ว |
| `text/html` | ยังไม่หาย — `web.config` ยังไม่ถูก copy ขึ้นไป |

สุดท้ายเปิดแอปหัวหน้า ไปแท็บ "กล้องวงจรปิด" ต้องเห็นภาพสดกับป้าย **LIVE** สีแดง

---

## ถ้าเพิ่ม router ใหม่ใน backend วันหลัง

ต้องเติมชื่อลงในกฎ `ProxyToBackend` ของ [`web.config`](web.config) ด้วยทุกครั้ง:

```xml
<rule name="ProxyToBackend" stopProcessing="true">
  <match url="^(app|boss-app|addresses|auth|camera|checkins|...|openapi\.json)(/.*)?$" />
  <action type="Rewrite" url="http://127.0.0.1:8001/{R:0}" />
</rule>
```

และ **ห้ามตั้งชื่อหน้าเว็บ React ให้ซ้ำกับชื่อในรายการนี้** ไม่งั้นหน้าเว็บจะเปิดไม่ได้
(ด้วยเหตุนี้หน้าประวัติใบหน้าจึงใช้ `/face-records` ไม่ใช่ `/faces`)

ตอนนี้ `deploy-update.ps1` ตรวจให้อัตโนมัติแล้ว โดยไปอ่านรายชื่อ router จริง
จาก `/openapi.json` ของ backend มาเทียบ — router ใหม่จึงถูกตรวจให้เองโดยไม่ต้องแก้สคริปต์
ถ้าลืมเติมชื่อใน `web.config` ตอนท้าย deploy จะเตือนขึ้นมาพร้อมบอกชื่อที่ขาด

---

## หมายเหตุ: อีกเรื่องที่เจอระหว่างตรวจ (ยังไม่ได้แก้ ไม่ด่วน)

เวลา backend ตอบรีไดเรกต์ 307 (เช่นตอนตัด `/` ท้าย path) IIS ส่ง header
`Location` เป็น**ที่อยู่ภายในเครื่อง**ออกไปให้ client:

```
GET https://thanakronpart-time.com/checkins/
-> 307  location: https://127.0.0.1:8001/checkins     <-- ควรเป็นโดเมนจริง
```

ตอนนี้ยังไม่กระทบแอปหรือเว็บ เพราะทั้งคู่เรียก path แบบไม่มี `/` ท้ายอยู่แล้ว
แต่ถ้าวันหลังมีใครเรียกโดยมี `/` ท้าย จะเจอ error แปลกๆ ที่หาต้นตอยาก

แก้ได้โดยเปิด reverse-rewrite ของ Location header ใน ARR
(IIS Manager -> Application Request Routing Cache -> Server Proxy Settings ->
ติ๊ก **Reverse rewrite host in response headers**) หรือเพิ่ม `outboundRules` ใน `web.config`
