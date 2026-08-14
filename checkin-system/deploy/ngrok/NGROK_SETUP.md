# เปิดให้เข้าจากอินเทอร์เน็ตด้วย ngrok.exe

ใช้ ngrok แทนการจดโดเมน / port forward / ทำ HTTPS เอง — ngrok ให้ URL แบบ `https://xxxx.ngrok-free.app` ที่วิ่งเข้ามาที่เครื่องของคุณโดยตรง

```
มือถือ/เบราว์เซอร์  ──►  https://xxxx.ngrok-free.app  ──(ngrok tunnel)──►  IIS :80
                                                                          ├─ React (static)
                                                                          └─ /api/* → uvicorn :8000 → PostgreSQL
```

> ยิง ngrok เข้า **IIS พอร์ต 80** ตัวเดียว จะได้ทั้งหน้าเว็บและ API อยู่ URL เดียวกัน (same-origin ไม่ต้องกังวลเรื่อง CORS)

---

## ขั้นตอน (ทำต่อจากการติดตั้ง IIS + backend + PostgreSQL ในคู่มือ Windows Server)

### 1. ตั้งค่า IIS ให้รับทุก Host
เพราะ URL ของ ngrok ไม่ตรงกับ hostname ที่ผูกไว้ ให้ตั้ง binding ของเว็บไซต์ `checkin`:
- IIS Manager > เว็บไซต์ checkin > Bindings > แก้ binding พอร์ต 80 ให้ **Host name = ว่าง** (รับทุกโดเมน)

ในไฟล์ `ngrok.yml` ตั้ง `host_header: localhost` ไว้แล้ว เพื่อให้ IIS รับ request ได้

### 2. ใส่ authtoken (ครั้งเดียว)
สมัคร ngrok ฟรี แล้วเอา authtoken มาใส่:
```powershell
ngrok config add-authtoken <YOUR_AUTHTOKEN>
```
หรือแก้ในไฟล์ `ngrok.yml` ที่ให้มา

### 3. รัน ngrok
```powershell
ngrok start --all --config C:\apps\checkin-system\deploy\ngrok\ngrok.yml
```
จะได้บรรทัดประมาณ:
```
Forwarding  https://a1b2-xxx.ngrok-free.app -> http://localhost:80
```
คัดลอก URL `https://a1b2-xxx.ngrok-free.app` ไปใช้

### 4. ตั้งค่าแอป Flutter ให้ชี้ URL ngrok
แก้ `flutter_app\lib\config.dart`:
```dart
static const String apiBase = "https://a1b2-xxx.ngrok-free.app/api";
```
แล้ว `flutter build apk --release`

### 5. (ทางเลือก) จำกัด CORS
เนื่องจาก same-origin แล้ว ไม่ตั้งก็ได้ แต่ถ้าจะตั้งให้แก้ `backend\.env`:
```
ALLOWED_ORIGINS=https://a1b2-xxx.ngrok-free.app
```
แล้ว `nssm restart MardodiCheckinAPI`

---

## ให้ ngrok รันตลอด (เป็น Windows Service)
ngrok รันเป็น service ได้ เพื่อให้เปิดทันทีหลังรีบูต:
```powershell
ngrok service install --config C:\apps\checkin-system\deploy\ngrok\ngrok.yml
ngrok service start
```

---

## ข้อจำกัดของ ngrok ที่ต้องรู้ (สำคัญ)

1. **URL ฟรีเปลี่ยนทุกครั้งที่รีสตาร์ต** → ต้อง build APK ใหม่ทุกครั้งที่ URL เปลี่ยน
   วิธีแก้: อัปเกรดแพ็กเกจ ngrok เพื่อได้ **static domain** (URL คงที่) แล้วใส่ `domain:` ใน `ngrok.yml`
   จะได้ไม่ต้อง build แอปใหม่

2. **หน้าเตือน interstitial ของ ngrok ฟรี** — ครั้งแรกที่เปิดหน้าเว็บในเบราว์เซอร์จะเจอหน้าเตือนให้กดผ่าน 1 ครั้ง
   ส่วนการเรียก API เราใส่ header `ngrok-skip-browser-warning` ให้แล้วทั้งใน React และ Flutter จึงไม่ติดปัญหานี้
   (แพ็กเกจแบบเสียเงินจะไม่มีหน้าเตือน)

3. **ต้องเปิดเครื่อง + ngrok ค้างไว้ตลอด** ถึงจะเข้าถึงได้ — ถ้าปิดเครื่อง tunnel จะหลุด

4. **ฟรีจำกัดจำนวน request/ต่อเนื่อง** ถ้าใช้จริงจังหลายคน แนะนำแพ็กเกจเสียเงิน

## สรุปทางเลือกที่เสถียรกว่า
ถ้าต้องใช้ระยะยาวกับหลายคน แนะนำ **static domain ของ ngrok (แบบเสียเงิน)** หรือกลับไปใช้โดเมนจริง + port forward ตามคู่มือ `DEPLOY_WINDOWS_SERVER.md` เพราะ URL ไม่เปลี่ยนและไม่มีหน้าเตือน
