# ===================================================================
# ติดตั้ง backend (FastAPI) เป็น Windows Service ด้วย NSSM
# รันใน PowerShell แบบ Administrator
# ต้องมี NSSM ก่อน:  choco install nssm   หรือดาวน์โหลดจาก https://nssm.cc
# ===================================================================

param(
  [string]$AppDir   = "C:\apps\checkin-system\backend",
  [string]$ServiceName = "MardodiCheckinAPI",
  [string]$Port     = "8000"
)

$ErrorActionPreference = "Stop"

$venvPython = Join-Path $AppDir "venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
  Write-Host "ไม่พบ venv ที่ $venvPython" -ForegroundColor Red
  Write-Host "สร้างก่อนด้วย:  cd $AppDir ; python -m venv venv ; venv\Scripts\pip install -r requirements.txt"
  exit 1
}

# อาร์กิวเมนต์ uvicorn (bind แค่ localhost เพราะ IIS เป็นตัวรับจากภายนอก)
# --proxy-headers ให้ backend อ่าน IP จริงจาก IIS
$uvicornArgs = "-m uvicorn app.main:app --host 127.0.0.1 --port $Port --workers 2 --proxy-headers --forwarded-allow-ips 127.0.0.1"

# ลบ service เดิมถ้ามี
$existing = Get-Service $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "ลบ service เดิม $ServiceName ..."
  nssm stop $ServiceName
  nssm remove $ServiceName confirm
}

Write-Host "ติดตั้ง service $ServiceName ..."
nssm install $ServiceName $venvPython $uvicornArgs
nssm set $ServiceName AppDirectory $AppDir
nssm set $ServiceName AppStdout (Join-Path $AppDir "logs\api-out.log")
nssm set $ServiceName AppStderr (Join-Path $AppDir "logs\api-err.log")
nssm set $ServiceName Start SERVICE_AUTO_START

# ตัวแปรแวดล้อม production (แก้ค่าตามจริง)
$envBlock = @(
  "DATABASE_URL=postgresql://checkin:CHANGE_ME@127.0.0.1:5432/checkin",
  'OFFICES=[{"name":"MARDODI","lat":13.9231953,"lng":100.5195808,"radius_km":2.0},{"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0},{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2}]',
  "OFFICE_LAT=13.9231953",
  "OFFICE_LNG=100.5195808",
  "OFFICE_NAME=MARDODI",
  "GEOFENCE_RADIUS_KM=2.0",
  "SECRET_KEY=CHANGE_ME_TO_A_LONG_RANDOM_STRING",
  "STORAGE_DIR=C:\apps\checkin-system\backend\storage"
) -join "`r`n"
nssm set $ServiceName AppEnvironmentExtra $envBlock

New-Item -ItemType Directory -Force -Path (Join-Path $AppDir "logs") | Out-Null

Write-Host "เริ่ม service ..."
nssm start $ServiceName

Write-Host "เสร็จ! ตรวจสถานะด้วย:  Get-Service $ServiceName" -ForegroundColor Green
Write-Host "ทดสอบภายในเครื่อง:  curl http://127.0.0.1:$Port/health"
