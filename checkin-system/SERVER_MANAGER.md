# GUI จัดการเซิร์ฟเวอร์และ Auto-start

## เปิด GUI

ดับเบิลคลิก `START_PART_TIME.bat` แล้วกด **Yes** เมื่อ Windows ขอสิทธิ์ Administrator

GUI จะแสดงสถานะของบริการแต่ละส่วน:

| ส่วน | หน้าที่ | การเริ่มพร้อม Windows |
|---|---|---|
| IIS Web Server (`:80`) | ให้บริการหน้าเว็บ React และส่งคำขอ API ต่อไปยัง FastAPI | Windows Service: Automatic |
| FastAPI (`:8001`) | API, ระบบเช็กอิน และฐานข้อมูล | Scheduled Task: `ThanakonBoxCheckinAPI` / AtStartup |
| Cloudflare Tunnel | เชื่อมเว็บในเครื่องกับโดเมนภายนอกผ่าน HTTPS | Windows Service: Automatic |
| Dev (`:5173`, `:8002`) | เซิร์ฟเวอร์ทดสอบสำหรับแก้โค้ด | ไม่เปิดอัตโนมัติและไม่กระทบ Production |

## ติดตั้งให้เซิร์ฟเวอร์เปิดเอง

ใน GUI กด **ติดตั้ง Auto-start** เพียงครั้งแรก ระบบจะติดตั้งทั้ง IIS, FastAPI Scheduled Task และ Cloudflare Tunnel จากนั้นแถบด้านบนต้องแสดง `Auto-start: พร้อม (API + IIS + Tunnel)`

หากต้องการติดตั้งจาก PowerShell โดยตรง ให้เปิด PowerShell แบบ **Run as Administrator** แล้วรัน:

```powershell
cd deploy\windows-server
.\install-autostart.ps1
```

หลังติดตั้ง ควรรีสตาร์ต Windows หนึ่งครั้งเพื่อทดสอบ จากนั้นเปิด `START_PART_TIME.bat` เพื่อตรวจว่าทุกรายการเป็นสีเขียว

## ปุ่ม Production

- **เปิด Production** — เปิด IIS, FastAPI และ Cloudflare Tunnel
- **รีสตาร์ต Production** — รีสตาร์ต FastAPI และ Tunnel โดยไม่หยุด IIS
- **หยุด Production** — หยุด API และ Tunnel ชั่วคราว (ค่า Auto-start ยังอยู่ และจะเริ่มใหม่เมื่อเปิดเครื่องครั้งถัดไป)
