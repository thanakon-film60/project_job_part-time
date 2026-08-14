# ===================================================================
# รัน backend แบบทดสอบเครื่องตัวเอง (ใช้ SQLite ไม่ต้องลง PostgreSQL)
# วิธีใช้: เปิด Terminal ใน VS Code แล้วพิมพ์
#     cd backend
#     .\run-local.ps1
# ===================================================================
$ErrorActionPreference = "Stop"

# ใช้ SQLite ไฟล์เดียว (ทดสอบง่าย ไม่ต้องใช้ psycopg2/PostgreSQL)
$env:DATABASE_URL = "sqlite:///./checkin.db"
$env:SECRET_KEY   = "local-dev-secret"

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
Write-Host "เปิด API ที่ http://localhost:8000/docs" -ForegroundColor Green
Write-Host "ปล่อยหน้าต่างนี้ไว้ อย่าปิด แล้วเปิด Terminal ใหม่ไปรัน frontend"
Write-Host ""

.\venv\Scripts\python -m uvicorn app.main:app --reload --port 8000
