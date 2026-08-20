# ===================================================================
# หน้าต่างควบคุมระบบเช็คอิน THANAKON-BOX (GUI)
#
# ทำไมต้องเป็น GUI: หน้าต่าง cmd/PowerShell ของ Windows ใช้ฟอนต์ที่ไม่มี
# ตัวอักษรไทย ภาษาไทยเลยกลายเป็น ??? — หน้าต่างโปรแกรมจริง (WinForms)
# ใช้ฟอนต์ระบบ จึงแสดงภาษาไทยได้ครบ
#
# เปิดใช้: ดับเบิลคลิก START_PART_TIME.bat
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
$PROD_TASK  = "ThanakonBoxCheckinAPI"

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
$fontLog   = New-Object Drawing.Font("Consolas", 9)

# ===================================================================
# หน้าต่างหลัก
# ===================================================================
$form = New-Object Windows.Forms.Form
$form.Text            = "ระบบเช็คอินเข้างาน THANAKON-BOX — แผงควบคุม"
$workArea = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initialWidth  = [Math]::Min(900, [Math]::Max(680, $workArea.Width - 30))
$initialHeight = [Math]::Min(700, [Math]::Max(520, $workArea.Height - 30))
$form.Size            = New-Object Drawing.Size($initialWidth, $initialHeight)
$form.MinimumSize     = New-Object Drawing.Size(680, 520)
$form.StartPosition   = "CenterScreen"
$form.AutoScaleMode   = [Windows.Forms.AutoScaleMode]::Dpi
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
$title.Text      = "ระบบเช็คอินเข้างาน THANAKON-BOX"
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
$statusBar.Height    = 192
$statusBar.BackColor = $cBg
$form.Controls.Add($statusBar)
$statusBar.BringToFront()

function New-StatusLabel([string]$caption, [int]$x, [int]$y = 8) {
    $p = New-Object Windows.Forms.Panel
    $p.Location  = New-Object Drawing.Point($x, $y)
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

$stProd = New-StatusLabel "เว็บจริง: กำลังตรวจ..."      10 8
$stDev  = New-StatusLabel "เครื่องนี้ (dev): กำลังตรวจ..." 320 8
$stTun  = New-StatusLabel "Cloudflare Tunnel: กำลังตรวจ..." 10 54

# ---------- ปุ่มด้านซ้าย ----------
$stApi  = New-StatusLabel "FastAPI :8001: กำลังตรวจสอบ..." 320 54
$stIis  = New-StatusLabel "IIS Web Server :80: กำลังตรวจสอบ..." 10 100
$stAuto = New-StatusLabel "Auto-start: กำลังตรวจสอบ..." 320 100
$stLine = New-StatusLabel "LINE Messaging API: กำลังตรวจสอบ..." 10 146
$stLineTask = New-StatusLabel "LINE Scheduler: กำลังตรวจสอบ..." 320 146

$side = New-Object Windows.Forms.Panel
$side.Dock      = "Left"
$side.Width     = 260
$side.AutoScroll = $true
$side.BackColor = $cBg
$side.Padding   = New-Object Windows.Forms.Padding(16, 10, 8, 10)

$script:buttons = @()

function New-Button([string]$text, [string]$hint, $color, [int]$y, [scriptblock]$action) {
    $b = New-Object Windows.Forms.Button
    $b.Text      = $text
    $b.Font      = $fontBtn
    $b.Size      = New-Object Drawing.Size(226, 52)
    $b.Location  = New-Object Drawing.Point(12, $y)
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
        $h.Size      = New-Object Drawing.Size(226, 18)
        $h.Location  = New-Object Drawing.Point(14, ($y + 53))
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

# Use table layouts so the menu and log always occupy separate columns.
# Docking both controls directly on the form caused the menu to cover the
# left side of the log on small screens / high DPI displays.
$contentLayout = New-Object Windows.Forms.TableLayoutPanel
$contentLayout.Dock = "Fill"
$contentLayout.Margin = New-Object Windows.Forms.Padding(0)
$contentLayout.Padding = New-Object Windows.Forms.Padding(0)
$contentLayout.ColumnCount = 2
$contentLayout.RowCount = 1
$contentLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 260))) | Out-Null
$contentLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$contentLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null

$side.Dock = "Fill"
$side.Margin = New-Object Windows.Forms.Padding(0)
$log.Dock = "Fill"
$log.Margin = New-Object Windows.Forms.Padding(0)
$contentLayout.Controls.Add($side, 0, 0)
$contentLayout.Controls.Add($log, 1, 0)

$rootLayout = New-Object Windows.Forms.TableLayoutPanel
$rootLayout.Dock = "Fill"
$rootLayout.Margin = New-Object Windows.Forms.Padding(0)
$rootLayout.Padding = New-Object Windows.Forms.Padding(0)
$rootLayout.ColumnCount = 1
$rootLayout.RowCount = 3
$rootLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$rootLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 70))) | Out-Null
$rootLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 192))) | Out-Null
$rootLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100))) | Out-Null

$header.Dock = "Fill"
$header.Margin = New-Object Windows.Forms.Padding(0)
$statusBar.Dock = "Fill"
$statusBar.Margin = New-Object Windows.Forms.Padding(0)

$form.Controls.Clear()
$rootLayout.Controls.Add($header, 0, 0)
$rootLayout.Controls.Add($statusBar, 0, 1)
$rootLayout.Controls.Add($contentLayout, 0, 2)
$form.Controls.Add($rootLayout)

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

function Update-BasicStatus {
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

function Get-LineConfiguration {
    $values = @{}
    $envPath = Join-Path $backend ".env"
    if (Test-Path $envPath) {
        Get-Content $envPath -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$') {
                $values[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    return @{
        Enabled = $values["LINE_NOTIFY_ENABLED"] -ne "false"
        Token   = "$($values['LINE_CHANNEL_ACCESS_TOKEN'])"
        Secret  = "$($values['LINE_CHANNEL_SECRET'])"
        Target  = "$($values['LINE_TARGET_ID'])"
    }
}

function Update-LineStatus {
    $lineConfig = Get-LineConfiguration
    $ready = $lineConfig.Enabled -and
        -not [string]::IsNullOrWhiteSpace($lineConfig.Token) -and
        -not [string]::IsNullOrWhiteSpace($lineConfig.Target)

    if (-not $ready) {
        Set-Status $stLine "LINE: ยังไม่ได้ตั้งค่า Token / Group ID" $cRed
    } else {
        try {
            $headers = @{ Authorization = "Bearer $($lineConfig.Token)" }
            Invoke-WebRequest "https://api.line.me/v2/bot/info" -Headers $headers `
                -UseBasicParsing -TimeoutSec 6 | Out-Null
            Set-Status $stLine "LINE: Login แล้ว / พร้อมส่งข้อความ" $cGreen
        } catch {
            $statusCode = 0
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
            if ($statusCode -eq 401) {
                Set-Status $stLine "LINE: Token ไม่ถูกต้องหรือหมดอายุ" $cRed
            } else {
                Set-Status $stLine "LINE: ตั้งค่าแล้ว แต่ตรวจการเชื่อมต่อไม่ได้" $cAmber
            }
        }
    }

    $lineTask = Get-ScheduledTask -TaskName "ThanakonBoxDailySummary" -ErrorAction SilentlyContinue
    if ($lineTask) {
        $lineInfo = Get-ScheduledTaskInfo -TaskName "ThanakonBoxDailySummary" -ErrorAction SilentlyContinue
        $next = if ($lineInfo -and $lineInfo.NextRunTime.Year -gt 2000) {
            $lineInfo.NextRunTime.ToString("dd/MM HH:mm")
        } else { "ไม่ทราบเวลา" }
        Set-Status $stLineTask "LINE Scheduler: ติดตั้งแล้ว / ครั้งถัดไป $next" $cGreen
    } else {
        Set-Status $stLineTask "LINE Scheduler: ยังไม่ได้ติดตั้ง" $cRed
    }
}

function Update-ProductionStatus {
    # production API + Windows startup configuration
    $task = Get-ScheduledTask -TaskName $PROD_TASK -ErrorAction SilentlyContinue
    $svc = Get-Service cloudflared -ErrorAction SilentlyContinue
    if ((Test-PortAlive $PROD_PORT) -and $task) {
        Set-Status $stApi "FastAPI :${PROD_PORT}: ทำงาน ($($task.State))" $cGreen
    } elseif ($task) {
        Set-Status $stApi "FastAPI :${PROD_PORT}: หยุด ($($task.State))" $cAmber
    } else {
        Set-Status $stApi "FastAPI :${PROD_PORT}: ยังไม่ได้ติดตั้ง" $cRed
    }

    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iis -and $iis.Status -eq "Running") {
        Set-Status $stIis "IIS Web Server :80: ทำงาน" $cGreen
    } elseif ($iis) {
        Set-Status $stIis "IIS Web Server :80: หยุด" $cAmber
    } else {
        Set-Status $stIis "IIS Web Server :80: ยังไม่ได้ติดตั้ง" $cRed
    }

    $hasBootTrigger = $false
    if ($task) {
        $hasBootTrigger = @($task.Triggers | Where-Object {
            $_.CimClass.CimClassName -eq "MSFT_TaskBootTrigger"
        }).Count -gt 0
    }
    $iisAuto = $iis -and "$($iis.StartType)" -eq "Automatic"
    $tunAuto = $svc -and "$($svc.StartType)" -eq "Automatic"
    if ($hasBootTrigger -and $iisAuto -and $tunAuto) {
        Set-Status $stAuto "Auto-start: พร้อม (API + IIS + Tunnel)" $cGreen
    } else {
        Set-Status $stAuto "Auto-start: ยังติดตั้งไม่ครบ" $cAmber
    }
}

function Update-Status {
    Update-BasicStatus
    Update-ProductionStatus
    Update-LineStatus
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
            # npm/vite emit ANSI terminal colors; RichTextBox does not interpret them.
            $line = ("$_" -replace '\x1B\[[0-9;?]*[ -/]*[@-~]', '')
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

function Action-StartProduction {
    Set-Busy $true
    Write-Head "เปิด Production servers"
    try {
        $task = Get-ScheduledTask -TaskName $PROD_TASK -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Log "  [!] ยังไม่มี Scheduled Task $PROD_TASK - กดติดตั้ง Auto-start ก่อน" $cAmber
            return
        }

        $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
        if ($iis) {
            Set-Service W3SVC -StartupType Automatic
            if ($iis.Status -ne "Running") { Start-Service W3SVC }
            Write-Log "  [OK] IIS Web Server ทำงานแล้ว (port 80)" $cGreen
        }

        if ($task.State -ne "Running") {
            Start-ScheduledTask -TaskName $PROD_TASK
        }
        Write-Log "  [OK] FastAPI กำลังเริ่ม (port $PROD_PORT)" $cGreen

        $tunnel = Get-Service cloudflared -ErrorAction SilentlyContinue
        if ($tunnel) {
            Set-Service cloudflared -StartupType Automatic
            if ($tunnel.Status -ne "Running") { Start-Service cloudflared }
            Write-Log "  [OK] Cloudflare Tunnel ทำงานแล้ว" $cGreen
        } else {
            Write-Log "  [!] ยังไม่ได้ติดตั้ง Cloudflare Tunnel" $cAmber
        }

        foreach ($i in 1..15) {
            Start-Sleep -Seconds 1
            [Windows.Forms.Application]::DoEvents()
            if (Test-PortAlive $PROD_PORT) { break }
        }
    } catch {
        Write-Log "  ERROR: $($_.Exception.Message)" $cRed
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-RestartProduction {
    Set-Busy $true
    Write-Head "รีสตาร์ต Production servers"
    try {
        $task = Get-ScheduledTask -TaskName $PROD_TASK -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Log "  [!] ยังไม่มี Scheduled Task $PROD_TASK - กดติดตั้ง Auto-start ก่อน" $cAmber
            return
        }
        Stop-ScheduledTask -TaskName $PROD_TASK -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-ScheduledTask -TaskName $PROD_TASK

        $tunnel = Get-Service cloudflared -ErrorAction SilentlyContinue
        if ($tunnel) { Restart-Service cloudflared -Force }
        Write-Log "  [OK] รีสตาร์ต FastAPI และ Cloudflare Tunnel แล้ว" $cGreen
        Start-Sleep -Seconds 3
    } catch {
        Write-Log "  ERROR: $($_.Exception.Message)" $cRed
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-StopProduction {
    $ans = [Windows.Forms.MessageBox]::Show(
        "เว็บไซต์ภายนอกจะใช้งานไม่ได้จนกว่าจะเปิดเซิร์ฟเวอร์อีกครั้ง`n`nต้องการหยุด Production หรือไม่?",
        "หยุด Production servers",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne "Yes") { return }

    Set-Busy $true
    Write-Head "หยุด Production servers"
    try {
        Stop-ScheduledTask -TaskName $PROD_TASK -ErrorAction SilentlyContinue
        Stop-Service cloudflared -Force -ErrorAction SilentlyContinue
        Write-Log "  [OK] หยุด FastAPI และ Cloudflare Tunnel แล้ว" $cGreen
        Write-Log "  IIS ยังทำงานอยู่เพื่อไม่กระทบเว็บไซต์อื่นในเครื่อง" $cMuted
        Start-Sleep -Seconds 2
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-InstallAutoStart {
    $ans = [Windows.Forms.MessageBox]::Show(
        "ระบบจะติดตั้ง IIS, FastAPI Scheduled Task และ Cloudflare Tunnel`n" +
        "ทั้งสามส่วนจะเริ่มเองทุกครั้งเมื่อเปิด Windows`n`nต้องการดำเนินการหรือไม่?",
        "ติดตั้ง Auto-start",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne "Yes") { return }

    Set-Busy $true
    Write-Head "ติดตั้งระบบเริ่มอัตโนมัติ"
    try {
        Invoke-Logged { & (Join-Path $here "windows-server\install-autostart.ps1") }
        Write-Log "  ตรวจสอบสถานะ Auto-start ได้จากแถบด้านบน" $cGreen
    } finally {
        Set-Busy $false
        Update-Status
    }
}

function Action-ConfigureLine {
    Write-Head "ตั้งค่า LINE Messaging API"
    Write-Log "  กำลังเปิดหน้าต่างตั้งค่า LINE (ค่าลับจะไม่แสดงใน GUI)..." $cBlue
    Start-Process (Join-Path $root "ตั้งค่า-LINE.bat")
}

function Action-InstallLineScheduler {
    $lineConfig = Get-LineConfiguration
    $ready = $lineConfig.Enabled -and
        -not [string]::IsNullOrWhiteSpace($lineConfig.Token) -and
        -not [string]::IsNullOrWhiteSpace($lineConfig.Target)
    if (-not $ready) {
        [Windows.Forms.MessageBox]::Show(
            "กรุณากด 'ตั้งค่า LINE' และใส่ Channel access token กับ Group ID ให้ครบก่อน",
            "LINE ยังไม่พร้อม",
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    Set-Busy $true
    Write-Head "ติดตั้ง LINE Scheduler"
    try {
        Invoke-Logged { & (Join-Path $here "line\install-daily-summary-task.ps1") }
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
$y1 = 400; $y2 = 478; $y3 = 556; $y4 = 634; $y5 = 322; $y6 = 712

New-Button "▶   เปิด Production" "IIS + FastAPI + Cloudflare Tunnel" $cGreen 10  { Action-StartProduction } | Out-Null
New-Button "↻   รีสตาร์ต Production" "รีสตาร์ต API และ Tunnel" $cBlue 88 { Action-RestartProduction } | Out-Null
New-Button "■   หยุด Production" "หยุด API และ Tunnel ชั่วคราว" $cGrey 166 { Action-StopProduction } | Out-Null
New-Button "⚙   ติดตั้ง Auto-start" "เปิดเซิร์ฟเวอร์เองทุกครั้งที่เปิดเครื่อง" ([Drawing.Color]::FromArgb(125, 85, 180)) 244 { Action-InstallAutoStart } | Out-Null
New-Button "◆   ตั้งค่า LINE" "ใส่ Token / Secret / Group ID" ([Drawing.Color]::FromArgb(30, 170, 90)) 790 { Action-ConfigureLine } | Out-Null
New-Button "◷   ติดตั้ง LINE Scheduler" "ส่งสรุปทุกวันเวลา 18:00" ([Drawing.Color]::FromArgb(30, 140, 110)) 868 { Action-InstallLineScheduler } | Out-Null

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

    Write-Log "  เซิร์ฟเวอร์ในระบบ" $cBlue
    Write-Log "    IIS Web Server :80 = ให้บริการหน้าเว็บไซต์ React" $cText
    Write-Log "    FastAPI :8001      = API และฐานข้อมูลของระบบเช็กอิน" $cText
    Write-Log "    Cloudflare Tunnel  = เชื่อมเว็บไซต์ในเครื่องออกสู่อินเทอร์เน็ตแบบ HTTPS" $cText
    Write-Log "    Dev :5173/:8002    = เซิร์ฟเวอร์ทดสอบสำหรับนักพัฒนา" $cText
    Write-Log "    Auto-start         = IIS/Service แบบ Automatic + API Task แบบ AtStartup" $cText
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
    Write-Output "api   : $($stApi.Label.Text)"
    Write-Output "iis   : $($stIis.Label.Text)"
    Write-Output "auto  : $($stAuto.Label.Text)"
    Write-Output "line  : $($stLine.Label.Text)"
    Write-Output "lineTask: $($stLineTask.Label.Text)"
    $form.Dispose()
    exit 0
}

[void]$form.ShowDialog()
