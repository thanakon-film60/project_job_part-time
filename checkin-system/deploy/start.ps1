# ===================================================================
# เมนูเดียวจบ — ดับเบิลคลิก START.bat แล้วเลือกตัวเลข
# ไม่ต้องจำคำสั่ง ไม่ต้องเปิด VS Code
# ===================================================================
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root     = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$backend  = Join-Path $root "backend"
$frontend = Join-Path $root "frontend"
$deploy   = Join-Path $root "deploy"

$DEV_PORT = 8002
$SITE     = "https://api.thanakronpart-time.com"

# ใส่ไว้ในบรรทัดคำสั่งของหน้าต่าง dev เพื่อให้หาเจอตอนสั่งหยุด
# (ห้ามซ้ำกับอย่างอื่นบนเครื่อง)
$DEV_MARKER = "CHECKIN_DEV_A7F3"

function Ok($m)   { Write-Host "  [OK] $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m"   -ForegroundColor Yellow }
function Info($m) { Write-Host "  $m"        -ForegroundColor Gray }
function Head($m) { Write-Host "`n$m`n" -ForegroundColor Cyan }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# เปิดหน้าต่างใหม่แบบขอสิทธิ์ Administrator แล้วรันสคริปต์ที่ระบุ
function Invoke-AsAdmin([string]$script, [string[]]$scriptArgs = @()) {
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", $script) + $scriptArgs
    Start-Process powershell.exe -ArgumentList $a -Verb RunAs
    Info "เปิดหน้าต่างใหม่ให้แล้ว (ถ้ามีป๊อปอัปถามสิทธิ์ ให้กด Yes)"
}

function Ensure-Dependencies {
    $needPy = -not (Test-Path (Join-Path $backend "venv\Scripts\uvicorn.exe"))
    $needJs = -not (Test-Path (Join-Path $frontend "node_modules"))
    if (-not ($needPy -or $needJs)) { return }

    Head "ติดตั้งไลบรารีครั้งแรก (ใช้เวลาสัก 1-2 นาที รอสักครู่)"
    if ($needPy) {
        Push-Location $backend
        try {
            if (-not (Test-Path "venv")) { python -m venv venv }
            .\venv\Scripts\python -m pip install --quiet --upgrade pip
            .\venv\Scripts\pip install --quiet -r requirements-base.txt
        } finally { Pop-Location }
        Ok "ไลบรารี Python พร้อม"
    }
    if ($needJs) {
        Push-Location $frontend
        try { npm install --no-fund --no-audit } finally { Pop-Location }
        Ok "ไลบรารี Node พร้อม"
    }
}

function Ensure-DevDatabase {
    if (Test-Path (Join-Path $backend "checkin-dev.db")) { return }
    Head "สร้างข้อมูลตัวอย่าง"
    Push-Location $backend
    try {
        $env:DATABASE_URL     = "sqlite:///./checkin-dev.db"
        $env:SECRET_KEY       = "local-dev-secret"
        $env:PYTHONIOENCODING = "utf-8"
        .\venv\Scripts\python seed.py
    } finally { Pop-Location }
    Ok "สร้างบัญชีตัวอย่างแล้ว"
}

function Test-PortAlive([int]$port) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect("127.0.0.1", $port, $null, $null)
        Start-Sleep -Milliseconds 250
        $alive = $c.Connected
        $c.Close()
        return $alive
    } catch { return $false }
}

function Stop-Dev {
    # uvicorn --reload และ npm run dev แตก process ลูกหลายชั้น
    # (uvicorn ใช้ multiprocessing spawn, npm เรียก node อีกที)
    # จึงต้องฆ่าทั้งต้นไม้ด้วย taskkill /T และวนซ้ำจนพอร์ตว่างจริง
    #
    # ⚠️ ห้ามกรองด้วย path ของ backend เฉย ๆ เพราะ backend production
    #    รันจากโฟลเดอร์เดียวกัน จะโดนฆ่าไปด้วย (เว็บจริงล่ม 502)
    #    จึงใช้ marker เฉพาะของ dev + เลขพอร์ตเป็นตัวชี้
    function KillTree([int]$procId) {
        if ($procId -le 0) { return }
        cmd.exe /c "taskkill /PID $procId /F /T >nul 2>&1" | Out-Null
    }

    foreach ($round in 1..4) {

        # 1) ฆ่าหน้าต่างที่เมนูนี้เปิดเอง (มี marker ในบรรทัดคำสั่ง) ทั้งต้นไม้
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$DEV_MARKER*" } |
            ForEach-Object { KillTree $_.ProcessId }

        # 2) ฆ่าตัวที่ยังถือพอร์ต dev อยู่ ทั้งต้นไม้
        foreach ($port in @($DEV_PORT, 5173)) {
            Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
                ForEach-Object { KillTree $_.OwningProcess }
        }

        # 3) กวาด worker ที่กำพร้า — uvicorn --reload ใช้ multiprocessing spawn
        #    ถ้า process แม่ตายไปแล้ว ลูกจะยังถือพอร์ตอยู่และ taskkill ตามไม่เจอ
        $alive = (Get-Process -ErrorAction SilentlyContinue).Id
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like "python*" -and
                $_.CommandLine -like "*multiprocessing*" -and
                ($alive -notcontains $_.ParentProcessId)
            } |
            ForEach-Object { KillTree $_.ProcessId }

        Start-Sleep -Milliseconds 1200
        if (-not (Test-PortAlive $DEV_PORT) -and -not (Test-PortAlive 5173)) { return $true }
    }
    return $false
}

# ------------------------------------------------------------------
# 1) รันบนเครื่องตัวเอง
# ------------------------------------------------------------------
function Start-Dev {
    Ensure-Dependencies
    Ensure-DevDatabase

    Head "กำลังเปิดระบบบนเครื่อง..."
    Stop-Dev | Out-Null

    $bk = "`$env:CHECKIN_TAG='$DEV_MARKER'; " +
          "`$env:DATABASE_URL='sqlite:///./checkin-dev.db'; " +
          "`$env:SECRET_KEY='local-dev-secret'; " +
          "`$env:ALLOWED_ORIGINS='*'; " +
          "`$env:PYTHONIOENCODING='utf-8'; " +
          "cd '$backend'; " +
          "Write-Host 'BACKEND :$DEV_PORT  (ปิดหน้าต่างนี้ = หยุด backend)' -ForegroundColor Cyan; " +
          ".\venv\Scripts\python -m uvicorn app.main:app --reload --port $DEV_PORT"
    Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-NoExit","-Command",$bk)

    $fe = "`$env:CHECKIN_TAG='$DEV_MARKER'; " +
          "`$env:VITE_API_BASE='http://localhost:$DEV_PORT'; " +
          "cd '$frontend'; " +
          "Write-Host 'FRONTEND :5173  (ปิดหน้าต่างนี้ = หยุดหน้าเว็บ)' -ForegroundColor Cyan; " +
          "npm run dev"
    Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-NoExit","-Command",$fe)

    Info "รอหน้าเว็บพร้อม..."
    $ready = $false
    foreach ($i in 1..30) {
        Start-Sleep -Seconds 2
        try {
            Invoke-WebRequest "http://localhost:5173" -UseBasicParsing -TimeoutSec 3 | Out-Null
            $ready = $true; break
        } catch { }
    }

    if ($ready) {
        Start-Process "http://localhost:5173"
        Ok "เปิดเบราว์เซอร์ให้แล้ว: http://localhost:5173"
    } else {
        Warn "หน้าเว็บยังไม่ขึ้น — ดู error ในหน้าต่างสีดำที่เพิ่งเปิด"
    }

    Write-Host ""
    Info "บัญชีทดสอบ"
    Info "  ผู้จัดการ : BOSS001 / boss12345"
    Info "  พนักงาน  : EMP001  / password123"
    Write-Host ""
    Info "API docs : http://localhost:$DEV_PORT/docs"
    Info "จะหยุด: ปิดหน้าต่างสีดำ 2 อัน หรือกลับมาที่เมนูนี้แล้วเลือก 9"
}

# ------------------------------------------------------------------
# เมนู
# ------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║       ระบบเช็คอินเข้างาน MARDODI                  ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   ทำงานบนเครื่องตัวเอง" -ForegroundColor DarkGray
    Write-Host "     1" -NoNewline -ForegroundColor Yellow
    Write-Host "  รันเว็บบนเครื่อง (แก้โค้ดแล้วเห็นผลทันที)"
    Write-Host ""
    Write-Host "   เว็บจริง  $SITE" -ForegroundColor DarkGray
    Write-Host "     2" -NoNewline -ForegroundColor Yellow
    Write-Host "  อัปโค้ดที่แก้แล้วขึ้นเว็บจริง"
    Write-Host "     3" -NoNewline -ForegroundColor Yellow
    Write-Host "  เช็คว่าเว็บจริงยังทำงานปกติไหม"
    Write-Host "     4" -NoNewline -ForegroundColor Yellow
    Write-Host "  เปิดเว็บจริงในเบราว์เซอร์"
    Write-Host ""
    Write-Host "   อื่น ๆ" -ForegroundColor DarkGray
    Write-Host "     5" -NoNewline -ForegroundColor Yellow
    Write-Host "  ติดตั้งใหม่ทั้งหมด (ใช้ตอนย้ายเครื่อง / ระบบพัง)"
    Write-Host "     9" -NoNewline -ForegroundColor Yellow
    Write-Host "  หยุดระบบที่รันบนเครื่อง"
    Write-Host "     0" -NoNewline -ForegroundColor Yellow
    Write-Host "  ออก"
    Write-Host ""
}

$emptyCount = 0
while ($true) {
    Show-Menu
    $choice = Read-Host "  เลือกตัวเลข"

    # กันลูปไม่รู้จบเวลาถูกเรียกแบบไม่มีคีย์บอร์ด (เช่นรันจากสคริปต์อื่น)
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $emptyCount++
        if ($emptyCount -ge 3) { exit }
        continue
    }
    $emptyCount = 0

    switch ($choice.Trim()) {
        "1" {
            try { Start-Dev } catch { Warn $_.Exception.Message }
            Read-Host "`n  กด Enter เพื่อกลับเมนู" | Out-Null
        }
        "2" {
            Head "อัปโค้ดขึ้นเว็บจริง"
            $s = Join-Path $deploy "windows-server\deploy-update.ps1"
            if (Test-Admin) {
                & $s
                Read-Host "`n  กด Enter เพื่อกลับเมนู" | Out-Null
            } else {
                Invoke-AsAdmin $s
                Read-Host "`n  ทำงานอยู่ในหน้าต่างใหม่ — กด Enter เพื่อกลับเมนู" | Out-Null
            }
        }
        "3" {
            Head "ตรวจสถานะเว็บจริง"
            & (Join-Path $deploy "windows-server\deploy-update.ps1") -CheckOnly
            Read-Host "`n  กด Enter เพื่อกลับเมนู" | Out-Null
        }
        "4" { Start-Process $SITE }
        "5" {
            Head "ติดตั้งใหม่ทั้งหมด"
            Warn "จะเปิดหน้าต่าง Administrator 3 อันต่อกัน: IIS -> backend -> tunnel"
            $go = Read-Host "  พิมพ์ YES เพื่อยืนยัน"
            if ($go -eq "YES") {
                Invoke-AsAdmin (Join-Path $deploy "windows-server\install-iis-site.ps1")
                Info "รอหน้าต่างแรกทำงานจนจบก่อน แล้วค่อยกด Enter"
                Read-Host | Out-Null
                Invoke-AsAdmin (Join-Path $deploy "windows-server\install-backend-task.ps1")
                Info "รอหน้าต่างที่สองทำงานจนจบก่อน แล้วค่อยกด Enter"
                Read-Host | Out-Null
                Invoke-AsAdmin (Join-Path $deploy "cloudflare\setup-tunnel.ps1") @("-InstallService")
            } else { Info "ยกเลิก" }
            Read-Host "`n  กด Enter เพื่อกลับเมนู" | Out-Null
        }
        "9" {
            if (Stop-Dev) { Ok "หยุดระบบบนเครื่องแล้ว (เว็บจริงไม่กระทบ)" }
            else { Warn "ยังมีบางตัวค้างอยู่ — ลองปิดหน้าต่างสีดำที่เปิดค้างไว้" }
            Start-Sleep -Seconds 2
        }
        "0" { exit }
        default { }
    }
}
