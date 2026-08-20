# ===================================================================
# เตรียม + รัน backend (FastAPI) ของ checkin-system เป็นบริการถาวร
# ใช้ Scheduled Task (ไม่ต้องพึ่ง NSSM) รันอัตโนมัติทุกครั้งที่บูตเครื่อง
#
#   uvicorn 127.0.0.1:8001  <--  IIS reverse proxy (ไม่มี /api นำหน้า)
#
# ใช้พอร์ต 8001 เพราะพอร์ต 8000 บนเครื่องนี้ถูกโปรเจ็กต์อื่นใช้อยู่
#
# ต้องรัน PowerShell แบบ "Run as Administrator"
# วิธีใช้:
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\windows-server
#     .\install-backend-task.ps1
# ===================================================================
[CmdletBinding()]
param(
    [string]$BackendDir = "",
    [int]$Port          = 8001,
    [string]$TaskName   = "ThanakonBoxCheckinAPI",
    # ใช้ SQLite (ไม่ต้องติดตั้ง PostgreSQL) — เปลี่ยนเป็น postgresql://... ได้ถ้ามี DB จริง
    [string]$DatabaseUrl = "sqlite:///./checkin.db",
    [string]$SecretKey   = "",
    # โดเมนที่อนุญาตให้เรียก API จากเบราว์เซอร์
    [string]$AllowedOrigins = "https://thanakronpart-time.com,https://www.thanakronpart-time.com,https://api.thanakronpart-time.com",
    # สถานที่ที่เช็คอินได้ (JSON บรรทัดเดียว) — เพิ่ม/แก้สาขาได้ที่นี่
    [string]$Offices = '[{"name":"THANAKON-BOX","lat":13.9231953,"lng":100.5195808,"radius_km":2.0},{"name":"BJH Bangkok","lat":13.8918358,"lng":100.563443,"radius_km":1.0},{"name":"ถึงบ้านแล้ว","lat":13.8865664,"lng":100.5066278,"radius_km":0.2}]'
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($BackendDir)) {
    $BackendDir = (Resolve-Path (Join-Path $here "..\..\backend")).Path
}

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "ต้องรัน PowerShell แบบ Run as Administrator" }

# --- 1) venv + ไลบรารี ----------------------------------------------
Step "เตรียม virtual environment ที่ $BackendDir"
Push-Location $BackendDir
try {
    $venvPython = Join-Path $BackendDir "venv\Scripts\python.exe"
    if (-not (Test-Path $venvPython)) {
        python -m venv venv
        Ok "สร้าง venv แล้ว"
    } else { Ok "มี venv อยู่แล้ว" }

    & $venvPython -m pip install --quiet --upgrade pip
    & $venvPython -m pip install --quiet -r requirements-base.txt
    if (-not (Test-Path (Join-Path $BackendDir "venv\Scripts\uvicorn.exe"))) {
        throw "ติดตั้งไลบรารีไม่สำเร็จ"
    }
    Ok "ติดตั้งไลบรารีครบ"

    # --- 2) ไฟล์ .env ------------------------------------------------
    Step "เขียนไฟล์ .env"
    $envPath = Join-Path $BackendDir ".env"

    # Keep the current signing key when reinstalling/updating. Rotating this
    # key invalidates every JWT that is still stored in users' browsers.
    if ([string]::IsNullOrWhiteSpace($SecretKey) -and (Test-Path $envPath)) {
        $secretLine = Get-Content $envPath |
            Where-Object { $_ -match '^SECRET_KEY=' } |
            Select-Object -First 1
        if ($secretLine) {
            $SecretKey = $secretLine.Substring('SECRET_KEY='.Length)
            Ok "ใช้ SECRET_KEY เดิม เพื่อไม่ให้ผู้ใช้หลุดจากระบบ"
        }
    }
    if ([string]::IsNullOrWhiteSpace($SecretKey)) {
        $bytes = New-Object byte[] 48
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $SecretKey = [Convert]::ToBase64String($bytes)
    }
    if (Test-Path $envPath) {
        Copy-Item $envPath "$envPath.bak" -Force
        Warn "สำรอง .env เดิมไว้ที่ .env.bak"
    }
    # สำคัญ: ต้องเขียนแบบ UTF-8 ไม่มี BOM ไม่งั้น python-dotenv จะอ่านคีย์บรรทัดแรกเพี้ยน
    $envLines = @(
        "DATABASE_URL=$DatabaseUrl",
        "OFFICES=$Offices",
        "OFFICE_LAT=13.9231953",
        "OFFICE_LNG=100.5195808",
        "OFFICE_NAME=THANAKON-BOX",
        "GEOFENCE_RADIUS_KM=2.0",
        "SECRET_KEY=$SecretKey",
        "ACCESS_TOKEN_EXPIRE_MINUTES=720",
        "STORAGE_DIR=$(Join-Path $BackendDir 'storage')",
        "ALLOWED_ORIGINS=$AllowedOrigins"
    )

    # Preserve optional integrations when reinstalling the backend. These
    # values are configured separately and must not disappear on an update.
    if (Test-Path $envPath) {
        $existingValues = @{}
        Get-Content $envPath | ForEach-Object {
            if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$') {
                $existingValues[$Matches[1]] = $Matches[2]
            }
        }
        foreach ($key in @(
            "LINE_NOTIFY_ENABLED",
            "LINE_CHANNEL_ACCESS_TOKEN",
            "LINE_CHANNEL_SECRET",
            "LINE_TARGET_ID",
            "TIMEZONE_OFFSET_HOURS"
        )) {
            if ($existingValues.ContainsKey($key)) {
                $envLines += "$key=$($existingValues[$key])"
            }
        }
    }
    [IO.File]::WriteAllLines($envPath, $envLines, (New-Object Text.UTF8Encoding($false)))
    Ok "เขียน .env แล้ว (SECRET_KEY พร้อมใช้งาน)"

    # --- 3) seed ข้อมูลตัวอย่าง --------------------------------------
    Step "สร้างตาราง + ข้อมูลตัวอย่าง"
    # console ของ Windows เป็น cp1252 — บังคับ UTF-8 ไม่งั้น print ภาษาไทยจะพัง
    $env:PYTHONIOENCODING = "utf-8"
    & $venvPython seed.py
    if ($LASTEXITCODE -ne 0) { throw "seed.py ล้มเหลว — ตรวจ .env / DATABASE_URL" }
    Ok "seed เรียบร้อย"
}
finally { Pop-Location }

# --- 4) Scheduled Task ----------------------------------------------
Step "ตั้ง Scheduled Task '$TaskName' (รันตอนบูต)"

Get-Process -Name python -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$BackendDir*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Warn "ลบ task เดิมออกก่อน"
}

$venvPython = Join-Path $BackendDir "venv\Scripts\python.exe"
$args = "-m uvicorn app.main:app --host 127.0.0.1 --port $Port " +
        "--proxy-headers --forwarded-allow-ips 127.0.0.1"

$action    = New-ScheduledTaskAction -Execute $venvPython -Argument $args -WorkingDirectory $BackendDir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries -StartWhenAvailable `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description "checkin-system FastAPI backend (uvicorn :$Port)" | Out-Null
Start-ScheduledTask -TaskName $TaskName
Ok "task ทำงานแล้ว"

# --- 5) ตรวจผล -------------------------------------------------------
Step "ทดสอบ"
$ok = $false
foreach ($i in 1..15) {
    Start-Sleep -Seconds 2
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 5
        Ok "backend :$Port -> $($r.Content)"
        $ok = $true
        break
    } catch { }
}
if (-not $ok) { Warn "backend ยังไม่ตอบที่พอร์ต $Port — ตรวจ log ด้วย Get-ScheduledTaskInfo -TaskName $TaskName" }

try {
    $r = Invoke-WebRequest "http://localhost/health" -UseBasicParsing -TimeoutSec 10
    Ok "ผ่าน IIS: /health -> $($r.Content)"
} catch { Warn "IIS proxy ยังไม่ผ่าน: $($_.Exception.Message)" }

Write-Host "`nคำสั่งที่ใช้บ่อย:" -ForegroundColor Green
Write-Host "  Start-ScheduledTask  -TaskName $TaskName"
Write-Host "  Stop-ScheduledTask   -TaskName $TaskName"
Write-Host "  Get-ScheduledTaskInfo -TaskName $TaskName"
