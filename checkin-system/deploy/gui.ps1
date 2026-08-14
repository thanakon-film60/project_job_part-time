# ===================================================================
# หน้าต่างควบคุมระบบเช็คอิน MARDODI (GUI)
#
# ทำไมต้องเป็น GUI: หน้าต่าง cmd/PowerShell ของ Windows ใช้ฟอนต์ที่ไม่มี
# ตัวอักษรไทย ภาษาไทยเลยกลายเป็น ??? — หน้าต่างโปรแกรมจริง (WinForms)
# ใช้ฟอนต์ระบบ จึงแสดงภาษาไทยได้ครบ
#
# เปิดใช้: ดับเบิลคลิก START.bat
# ===================================================================
[CmdletBinding()]
param(
    # ใช้ตอนทดสอบว่าหน้าต่างสร้างได้ไหม โดยไม่ต้องเปิดจริง
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# ---------- ขอสิทธิ์ Administrator (จำเป็นตอน deploy) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$selfPath = $MyInvocation.MyCommand.Path
if (-not $isAdmin -and -not $SelfTest) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$selfPath`""
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# ---------- ค่าคงที่ ----------
$here     = Split-Path -Parent $selfPath
$root     = Split-Path -Parent $here
$backend  = Join-Path $root "backend"
$frontend = Join-Path $root "frontend"

$DEV_PORT   = 8002
$WEB_PORT   = 5173
$PROD_PORT  = 8001
$SITE       = "https://thanakronpart-time.com"
$DEV_MARKER = "CHECKIN_DEV_A7F3"

# ---------- ธีมสี ----------
$cBg     = [Drawing.Color]::FromArgb(24, 26, 32)
$cPanel  = [Drawing.Color]::FromArgb(33, 36, 44)
$cText   = [Drawing.Color]::FromArgb(232, 234, 240)
$cMuted  = [Drawing.Color]::FromArgb(150, 156, 170)
$cGreen  = [Drawing.Color]::FromArgb(80, 200, 120)
$cRed    = [Drawing.Color]::FromArgb(235, 100, 100)
$cAmber  = [Drawing.Color]::FromArgb(235, 180, 80)
$cBlue   = [Drawing.Color]::FromArgb(70, 130, 220)

$fontUI    = New-Object Drawing.Font("Segoe UI", 11)
$fontBtn   = New-Object Drawing.Font("Segoe UI", 12, [Drawing.FontStyle]::Bold)
$fontSmall = New-Object Drawing.Font("Segoe UI", 9)
$fontHead  = New-Object Drawing.Font("Segoe UI", 16, [Drawing.FontStyle]::Bold)
$fontLog   = New-Object Drawing.Font("Consolas", 10)

# ===================================================================
# หน้าต่างหลัก
# ===================================================================
$form = New-Object Windows.Forms.Form
$form.Text            = "ระบบเช็คอินเข้างาน MARDODI — แผงควบคุม"
$form.Size            = New-Object Drawing.Size(980, 700)
$form.MinimumSize     = New-Object Drawing.Size(860, 600)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = $cBg
$form.ForeColor       = $cText
$form.Font            = $fontUI

# ---------- แถบหัว ----------
$header = New-Object Windows.Forms.Panel
$header.Dock      = "Top"
$header.Height    = 70
$header.BackColor = $cPanel
$form.Controls.Add($header)

$title = New-Object Windows.Forms.Label
$title.Text      = "ระบบเช็คอินเข้างาน MARDODI"
$title.Font      = $fontHead
$title.ForeColor = $cText
$title.AutoSize  = $true
$title.Location  = New-Object Drawing.Point(20, 12)
$header.Controls.Add($title)

$subtitle = New-Object Windows.Forms.Label
$subtitle.Text      = "เว็บจริง: $SITE"
$subtitle.Font      = $fontSmall
$subtitle.ForeColor = $cMuted
$subtitle.AutoSize  = $true
$subtitle.Location  = New-Object Drawing.Point(22, 44)
$header.Controls.Add($subtitle)

# ---------- แถบสถานะ ----------
$statusBar = New-Object Windows.Forms.Panel
$statusBar.Dock      = "Top"
$statusBar.Height    = 54
$statusBar.BackColor = $cBg
$form.Controls.Add($statusBar)
$statusBar.BringToFront()

function New-StatusLabel([string]$caption, [int]$x) {
    $p = New-Object Windows.Forms.Panel
    $p.Location  = New-Object Drawing.Point($x, 8)
    $p.Size      = New-Object Drawing.Size(300, 38)
    $p.BackColor = $cPanel

    $dot = New-Object Windows.Forms.Label
    $dot.Text      = "●"
    $dot.ForeColor = $cMuted
    $dot.AutoSize  = $true
    $dot.Location  = New-Object Drawing.Point(10, 8)
    $p.Controls.Add($dot)

    $lb = New-Object Windows.Forms.Label
    $lb.Text      = $caption
    $lb.ForeColor = $cText
    $lb.Font      = $fontSmall
    $lb.AutoSize  = $true
    $lb.Location  = New-Object Drawing.Point(32, 11)
    $p.Controls.Add($lb)

    $statusBar.Controls.Add($p)
    return @{ Panel = $p; Dot = $dot; Label = $lb }
}

$stProd = New-StatusLabel "เว็บจริง: กำลังตรวจ..."      20
$stDev  = New-StatusLabel "เครื่องนี้ (dev): กำลังตรวจ..." 330
$stTun  = New-StatusLabel "Cloudflare Tunnel: กำลังตรวจ..." 640

# ---------- ปุ่มด้านซ้าย ----------
$side = New-Object Windows.Forms.Panel
$side.Dock      = "Left"
$side.Width     = 300
$side.BackColor = $cBg
$side.Padding   = New-Object Windows.Forms.Padding(16, 10, 8, 10)
$form.Controls.Add($side)
$side.BringToFront()

$script:buttons = @()

function New-Button([string]$text, [string]$hint, $color, [int]$y, [scriptblock]$action) {
    $b = New-Object Windows.Forms.Button
    $b.Text      = $text
    $b.Font      = $fontBtn
    $b.Size      = New-Object Drawing.Size(268, 52)
    $b.Location  = New-Object Drawing.Point(16, $y)
    $b.FlatStyle = "Flat"
    $b.BackColor = $color
    $b.ForeColor = [Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor    = "Hand"
    $b.TextAlign = "MiddleLeft"
    $b.Padding   = New-Object Windows.Forms.Padding(14, 0, 0, 0)
    $b.Add_Click($action)
    $side.Controls.Add($b)
    $script:buttons += $b

    if ($hint) {
        $h = New-Object Windows.Forms.Label
        $h.Text      = $hint
        $h.Font      = $fontSmall
        $h.ForeColor = $cMuted
        $h.AutoSize  = $false
        $h.Size      = New-Object Drawing.Size(268, 18)
        $h.Location  = New-Object Drawing.Point(18, ($y + 53))
        $side.Controls.Add($h)
    }
    return $b
}

# ---------- กล่อง log ----------
$log = New-Object Windows.Forms.RichTextBox
$log.Dock        = "Fill"
$log.BackColor   = [Drawing.Color]::FromArgb(16, 18, 22)
$log.ForeColor   = $cText
$log.Font        = $fontLog
$log.ReadOnly    = $true
$log.BorderStyle = "None"
# ต้องตัดคำ ไม่งั้น ScrollToCaret จะเลื่อนไปขวาสุดจนอ่านข้อความไม่เห็น
$log.WordWrap    = $true
$log.ScrollBars  = "Vertical"
$form.Controls.Add($log)

function Write-Log([string]$text, $color = $null) {
    if ($null -eq $color) { $color = $cText }
    $log.SelectionStart  = $log.TextLength
    $log.SelectionLength = 0
    $log.SelectionColor  = $color
    $log.AppendText("$text`r`n")
    $log.SelectionColor  = $log.ForeColor
    $log.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}

function Write-Head([string]$text) {
    Write-Log ""
    Write-Log ("─" * 70) $cMuted
    Write-Log "  $text" $cBlue
    Write-Log ("─" * 70) $cMuted
}

# ===================================================================
# ฟังก์ชันทำงาน
# ===================================================================
function Test-PortAlive([int]$port) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect("127.0.0.1", $port, $null, $null)
        Start-Sleep -Milliseconds 200
        $alive = $c.Connected
        $c.Close()
        return $alive
    } catch { return $false }
}

function Test-Http([string]$url, [int]$timeoutSec = 10) {
    try {
        $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec $timeoutSec
        return @{ Ok = $true; Code = $r.StatusCode; Body = $r.Content }
    } catch {
        return @{ Ok = $false; Code = 0; Body = $_.Exception.Message }
    }
}

function Set-Status($st, [string]$text, $color) {
    $st.Label.Text     = $text
    $st.Dot.ForeColor  = $color
}

function Update-Status {
    # เว็บจริง
    $p = Test-Http "$SITE/health" 12
    if ($p.Ok) { Set-Status $stProd "เว็บจริง: ทำงานปกติ" $cGreen }
    else        { Set-Status $stProd "เว็บจริง: มีปัญหา"   $cRed }

    # dev
    if (Test-PortAlive $WEB_PORT) { Set-Status $stDev "เครื่องนี้ (dev): กำลังรันอยู่" $cGreen }
    else                          { Set-Status $stDev "เครื่องนี้ (dev): ปิดอยู่"      $cMuted }

    # tunnel
    $svc = Get-Service cloudflared -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { Set-Status $stTun "Cloudflare Tunnel: ทำงานอยู่" $cGreen }
    elseif ($svc)                            { Set-Status $stTun "Cloudflare Tunnel: หยุดอยู่"  $cAmber }
    else                                     { Set-Status $stTun "Cloudflare Tunnel: ยังไม่ติดตั้ง" $cRed }
}

function Set-Busy([bool]$busy) {
    foreach ($b in $script:buttons) { $b.Enabled = -not $busy }
    if ($busy) { $form.Cursor = "WaitCursor" } else { $form.Cursor = "Default" }
    [Windows.Forms.Application]::DoEvents()
}

# รันคำสั่งภายนอกแล้วส่งผลเข้ากล่อง log ทีละบรรทัด
function Invoke-Logged([scriptblock]$block) {
    try {
        & $block 2>&1 | ForEach-Object {
            $line = "$_"
            $c = $cText
            if ($line -match '\[OK\]|สำเร็จ|พร้อม|เรียบร้อย|เสร็จ') { $c = $cGreen }
            elseif ($line -match '\[!\]|ERROR|error|ล้มเหลว|ไม่ได้|ไม่พบ')  { $c = $cAmber }
            Write-Log "  $line" $c
        }
    } catch {
        Write-Log "  ผิดพลาด: $($_.Exception.Message)" $cRed
    }
}

function Ensure-Dependencies {
    $needPy = -not (Test-Path (Join-Path $backend "venv\Scripts\uvicorn.exe"))
    $needJs = -not (Test-Path (Join-Path $frontend "node_modules"))
    if (-not ($needPy -or $needJs)) { return }

    Write-Log "  ครั้งแรก — กำลังติดตั้งไลบรารี (ใช้เวลา 1-2 นาที)" $cAmber
    if ($needPy) {
        Push-Location $backend
        try {
            if (-not (Test-Path "venv")) { Invoke-Logged { python -m venv venv } }
            Invoke-Logged { .\venv\Scripts\python -m pip install --quiet --upgrade pip }
            Invoke-Logged { .\venv\Scripts\pip install --quiet -r requirements-base.txt }
        } finally { Pop-Location }
        Write-Log "  [OK] ไลบรารี Python พร้อม" $cGreen
    }
    if ($needJs) {
        Push-Location $frontend
        try { Invoke-Logged { npm install --no-fund --no-audit } } finally { Pop-Location }
        Write-Log "  [OK] ไลบรารี Node พร้อม" $cGreen
    }
}

function Ensure-DevDatabase {
    if (Test-Path (Join-Path $backend "checkin-dev.db")) { return }
    Write-Log "  กำลังสร้างข้อมูลตัวอย่าง..." $cMuted
    Push-Location $backend
    try {
        $env:DATABASE_URL     = "sqlite:///./checkin-dev.db"
        $env:SECRET_KEY       = "local-dev-secret"
        $env:PYTHONIOENCODING = "utf-8"
        Invoke-Logged { .\venv\Scripts\python seed.py }
    } finally { Pop-Location }
    Write-Log "  [OK] สร้างบัญชีตัวอย่างแล้ว" $cGreen
}

function Stop-Dev {
    function KillTree([int]$procId) {
        if ($procId -le 0) { return }
        cmd.exe /c "taskkill /PID $procId /F /T >nul 2>&1" | Out-Null
    }
    foreach ($round in 1..4) {
        # ⚠️ ห้ามกรองด้วย path ของ backend เพราะ backend production รันจากโฟลเดอร์เดียวกัน
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$DEV_MARKER*" } |
            ForEach-Object { KillTree $_.ProcessId }

        foreach ($port in @($DEV_PORT, $WEB_PORT)) {
            Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
                ForEach-Object { KillTree $_.OwningProcess }
        }

        # worker กำพร้าของ uvicorn --reload (multiprocessing spawn)
        $aliveIds = (Get-Process -ErrorAction SilentlyContinue).Id
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like "python*" -and
                $_.CommandLine -like "*multiprocessing*" -and
                ($aliveIds -notcontains $_.ParentProcessId)
            } |
            ForEach-Object { KillTree $_.ProcessId }

        Start-Sleep -Milliseconds 1000
        if (-not (Test-PortAlive $DEV_PORT) -and -not (Test-PortAlive $WEB_PORT)) { return $true }
    }
    return $false
}

function Action-StartDev {
    Set-Busy $true
    Write-Head "เปิดระบบบนเครื่องนี้"
    try {
        Ensure-Dependencies
        Ensure-DevDatabase
        Stop-Dev | Out-Null

        # หน้าต่างที่เปิดใหม่ใช้ข้อความอังกฤษ เพราะ console แสดงภาษาไทยไม่ได้
        $bk = "`$env:CHECKIN_TAG='$DEV_MARKER'; " +
              "`$env:DATABASE_URL='sqlite:///./checkin-dev.db'; " +
              "`$env:SECRET_KEY='local-dev-secret'; " +
              "`$env:ALLOWED_ORIGINS='*'; " +
              "`$env:PYTHONIOENCODING='utf-8'; " +
              "cd '$backend'; " +
              "`$host.UI.RawUI.WindowTitle='BACKEND  port $DEV_PORT  - closing this window stops the API'; " +
              ".\venv\Scripts\python -m uvicorn app.main:app --reload --port $DEV_PORT"
        Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-NoExit","-Command",$bk)
        Write-Log "  เปิด backend ที่พอร์ต $DEV_PORT แล้ว" $cGreen

        $fe = "`$env:CHECKIN_TAG='$DEV_MARKER'; " +
              "`$env:VITE_API_BASE='http://localhost:$DEV_PORT'; " +
              "cd '$frontend'; " +
              "`$host.UI.RawUI.WindowTitle='FRONTEND  port $WEB_PORT  - closing this window stops the website'; " +
              "npm run dev"
        Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-NoExit","-Command",$fe)
        Write-Log "  เปิดหน้าเว็บที่พอร์ต $WEB_PORT แล้ว" $cGreen

        Write-Log "  รอหน้าเว็บพร้อม..." $cMuted
        $ready = $false
        foreach ($i in 1..30) {
            Start-Sleep -Seconds 2
            [Windows.Forms.Application]::DoEvents()
            if (Test-PortAlive $WEB_PORT) { $ready = $true; break }
        }

        if ($ready) {
            Start-Process "http://localhost:$WEB_PORT"
            Write-Log ""
            Write-Log "  [OK] พร้อมใช้งาน — เปิดเบราว์เซอร์ให้แล้ว" $cGreen
            Write-Log "       หน้าเว็บ  : http://localhost:$WEB_PORT" $cText
            Write-Log "       API docs : http://localhost:$DEV_PORT/docs" $cText
            Write-Log ""
            Write-Log "       บัญชีทดสอบ" $cMuted
            Write-Log "         ผู้จัดการ : BOSS001 / boss12345" $cText
            Write-Log "         พนักงาน  : EMP001  / password123" $cText
        } else {
            Write-Log "  [!] หน้าเว็บยังไม่ขึ้น — ดูข้อความในหน้าต่างสีดำที่เพิ่งเปิด" $cAmber
        }
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-StopDev {
    Set-Busy $true
    Write-Head "หยุดระบบบนเครื่องนี้"
    try {
        if (Stop-Dev) { Write-Log "  [OK] หยุดเรียบร้อย (เว็บจริงไม่กระทบ)" $cGreen }
        else { Write-Log "  [!] ยังมีบางตัวค้างอยู่ — ลองปิดหน้าต่างสีดำที่เปิดค้างไว้" $cAmber }
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-Deploy {
    $ans = [Windows.Forms.MessageBox]::Show(
        "จะ build โค้ดล่าสุดแล้วอัปขึ้นเว็บจริงที่`n$SITE`n`nระหว่างนี้เว็บจริงจะสะดุดสักครู่ ยืนยันไหม?",
        "ยืนยันการอัปขึ้นเว็บจริง",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne "Yes") { return }

    Set-Busy $true
    Write-Head "อัปโค้ดขึ้นเว็บจริง"
    try {
        Invoke-Logged { & (Join-Path $here "windows-server\deploy-update.ps1") }
        Write-Log "  เสร็จแล้ว" $cGreen
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-Check {
    Set-Busy $true
    Write-Head "ตรวจสถานะเว็บจริง"
    try {
        Invoke-Logged { & (Join-Path $here "windows-server\deploy-update.ps1") -CheckOnly }
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-Reinstall {
    $ans = [Windows.Forms.MessageBox]::Show(
        "ติดตั้งระบบใหม่ทั้งหมด (IIS + backend + Cloudflare Tunnel)`n" +
        "ใช้ตอนย้ายเครื่องหรือระบบพังเท่านั้น`n`nใช้เวลาหลายนาที ยืนยันไหม?",
        "ยืนยันการติดตั้งใหม่",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne "Yes") { return }

    Set-Busy $true
    Write-Head "ติดตั้งระบบใหม่ทั้งหมด"
    try {
        Write-Log "  [1/3] IIS + หน้าเว็บ" $cBlue
        Invoke-Logged { & (Join-Path $here "windows-server\install-iis-site.ps1") }
        Write-Log "  [2/3] backend" $cBlue
        Invoke-Logged { & (Join-Path $here "windows-server\install-backend-task.ps1") }
        Write-Log "  [3/3] Cloudflare Tunnel" $cBlue
        Invoke-Logged { & (Join-Path $here "cloudflare\setup-tunnel.ps1") -InstallService }
        Write-Log "  เสร็จแล้ว" $cGreen
    } finally {
        Set-Busy $false
        Update-Status
    }
}

# ===================================================================
# สร้างปุ่ม (เว้นระยะปุ่มละ 78px: ปุ่มสูง 52 + คำอธิบาย 18 + ช่องไฟ 8)
# ===================================================================
$cGrey = [Drawing.Color]::FromArgb(90, 96, 110)
$y1 = 10; $y2 = 88; $y3 = 166; $y4 = 244; $y5 = 322; $y6 = 400

New-Button "▶   รันบนเครื่องนี้"     "แก้โค้ดแล้วเห็นผลทันที"        $cGreen $y1 { Action-StartDev } | Out-Null
New-Button "■   หยุดที่รันบนเครื่อง" "ไม่กระทบเว็บจริง"              $cGrey  $y2 { Action-StopDev }  | Out-Null
New-Button "▲   อัปขึ้นเว็บจริง"     "build + deploy + ทดสอบให้"     $cBlue  $y3 { Action-Deploy }   | Out-Null
New-Button "✓   เช็คสถานะเว็บจริง"   "ดูว่าทุกอย่างยังปกติไหม"       $cGrey  $y4 { Action-Check }    | Out-Null
New-Button "◈   เปิดเว็บจริง"        $SITE                           $cGrey  $y5 { Start-Process $SITE } | Out-Null
New-Button "⚙   ติดตั้งใหม่ทั้งหมด"  "ใช้ตอนย้ายเครื่อง / ระบบพัง"   ([Drawing.Color]::FromArgb(150, 90, 60)) $y6 { Action-Reinstall } | Out-Null

# ===================================================================
# เริ่มทำงาน
# ===================================================================

# ตรวจสถานะทุก 30 วินาที
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({ try { Update-Status } catch { } })

$form.Add_Shown({
    # ดันหน้าต่างขึ้นมาหน้าสุดตอนเปิด (ไม่งั้นอาจไปซ่อนหลังหน้าต่างอื่น)
    $form.TopMost = $true
    $form.Activate()
    $form.TopMost = $false

    # ต้องเขียน log หลังหน้าต่างแสดงแล้ว ไม่งั้น RichTextBox ยังไม่พร้อมรับข้อความ
    Write-Log ""
    Write-Log "  ยินดีต้อนรับ" $cBlue
    Write-Log "  เลือกคำสั่งจากปุ่มด้านซ้าย — ผลลัพธ์จะแสดงตรงนี้" $cMuted
    Write-Log ""
    Write-Log "  ปุ่มที่ใช้บ่อย" $cMuted
    Write-Log "    รันบนเครื่องนี้    = เปิดเว็บ + API บนเครื่อง ไว้แก้โค้ดแล้วดูผลทันที" $cText
    Write-Log "    อัปขึ้นเว็บจริง     = เอาโค้ดล่าสุดไปใช้จริงที่ $SITE" $cText
    Write-Log "    เช็คสถานะเว็บจริง = ดูว่า IIS / backend / tunnel ยังปกติไหม" $cText
    Write-Log ""

    try { Update-Status } catch { }
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
    if (Test-PortAlive $WEB_PORT) {
        $r = [Windows.Forms.MessageBox]::Show(
            "ระบบบนเครื่อง (dev) ยังรันอยู่`n`nต้องการหยุดก่อนปิดหน้าต่างนี้ไหม?",
            "ปิดโปรแกรม",
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Question)
        if ($r -eq "Yes") { Stop-Dev | Out-Null }
    }
})

if ($SelfTest) {
    Write-Output "form created OK: $($form.Text)"
    Write-Output "buttons: $($script:buttons.Count)"
    Update-Status
    Write-Output "prod  : $($stProd.Label.Text)"
    Write-Output "dev   : $($stDev.Label.Text)"
    Write-Output "tunnel: $($stTun.Label.Text)"
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
