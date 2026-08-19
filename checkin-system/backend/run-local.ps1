# ===================================================================
# รัน backend แบบทดสอบเครื่องตัวเอง (ใช้ SQLite ไม่ต้องลง PostgreSQL)
# วิธีใช้: เปิด Terminal ใน VS Code แล้วพิมพ์
#     cd backend
#     .\run-local.ps1
# ===================================================================
$ErrorActionPreference = "Stop"

# ใช้ SQLite ไฟล์เดียว (ทดสอบง่าย ไม่ต้องใช้ psycopg2/PostgreSQL)
$env:DATABASE_URL     = "sqlite:///./checkin-dev.db"
$env:OFFICES          = '[{"name":"MARDODI","lat":13.9231953,"lng":100.5195808,"radius_km":2.0},{"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0},{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2}]'
$env:SECRET_KEY       = "local-dev-secret"
$env:ALLOWED_ORIGINS  = "*"
# console ของ Windows เป็น cp1252 — บังคับ UTF-8 ไม่งั้น print ภาษาไทยจะพัง
$env:PYTHONIOENCODING = "utf-8"

# พอร์ต 8000 มีโปรเจ็กต์อื่นบนเครื่องนี้ใช้อยู่ และ 8001 คือ backend production
# ตอน dev จึงใช้ 8002 เพื่อไม่ให้ชนกัน
$devPort = 8002

# ถ้า venv เดิมพัง (จากการติดตั้งที่ล้มเหลว) ให้ลบทิ้งแล้วสร้างใหม่
if (Test-Path "venv") {
  $hasUvicorn = Test-Path "venv\Scripts\uvicorn.exe"
  if (-not $hasUvicorn) {
    Write-Host "venv เดิมไม่สมบูรณ์ กำลังลบและสร้างใหม่..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "venv"
  }
}
if (-not (Test-Path "venv")) {
  Write-Host "สร้าง virtual environment..." -ForegroundColor Cyan
  python -m venv venv
}

Write-Host "ติดตั้งไลบรารี (เฉพาะที่จำเป็นสำหรับโลคอล ไม่รวม PostgreSQL)..." -ForegroundColor Cyan
.\venv\Scripts\python -m pip install --quiet --upgrade pip
.\venv\Scripts\pip install -r requirements-base.txt

# ตรวจว่าติดตั้งสำเร็จจริงก่อนไปต่อ
if (-not (Test-Path "venv\Scripts\uvicorn.exe")) {
  Write-Host "ติดตั้งไลบรารีไม่สำเร็จ กรุณาส่ง error ด้านบนมาให้ช่วยดู" -ForegroundColor Red
  exit 1
}

Write-Host "สร้างข้อมูลตัวอย่าง (บัญชี + เช็คอินย้อนหลัง)..." -ForegroundColor Cyan
.\venv\Scripts\python seed.py

Write-Host ""
Write-Host "== บัญชีสำหรับล็อกอิน ==" -ForegroundColor Green
Write-Host "  ผู้จัดการ (ดูปฏิทิน): BOSS001 / boss12345"
Write-Host "  พนักงาน:            EMP001  / password123"
Write-Host ""
Write-Host "เปิด API ที่ http://localhost:$devPort/docs" -ForegroundColor Green
Write-Host "ปล่อยหน้าต่างนี้ไว้ อย่าปิด แล้วเปิด Terminal ใหม่ไปรัน frontend"
Write-Host ""

.\venv\Scripts\python -m uvicorn app.main:app --reload --port $devPort
