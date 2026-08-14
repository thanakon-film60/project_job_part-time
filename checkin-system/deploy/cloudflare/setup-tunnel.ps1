# ===================================================================
# ตั้งค่า Cloudflare Tunnel ให้เปิด IIS :80 ออกสู่อินเทอร์เน็ต
#   https://api.thanakronpart-time.com  ->  IIS :80  ->  React + API -> :8001
#
# ต้องทำมาก่อน (ทำแล้ว): ดาวน์โหลด cloudflared, tunnel login, tunnel create
# ต้องรัน PowerShell แบบ "Run as Administrator" (เฉพาะตอนติดตั้ง service)
#
# วิธีใช้:
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\cloudflare
#     .\setup-tunnel.ps1              # ตั้งค่า + ทดสอบรันหน้าจอ
#     .\setup-tunnel.ps1 -InstallService   # ตั้งค่า + ติดตั้งเป็น Windows Service
# ===================================================================
[CmdletBinding()]
param(
    [string]$Cloudflared = "F:\Game\cloudflared-windows-amd64.exe",
    [string]$ConfigPath  = "F:\Game\config.yml",
    [string]$TunnelName  = "Film_Part-Time",
    # ทุกโดเมนที่จะชี้มาที่ tunnel นี้ (ต้องตรงกับ ingress ใน config.yml)
    [string[]]$Hostnames = @(
        "thanakronpart-time.com",
        "www.thanakronpart-time.com",
        "api.thanakronpart-time.com"
    ),
    [int]$OriginPort     = 80,
    [switch]$InstallService
)

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

# --- 0) ตรวจของที่ต้องมี ---------------------------------------------
Step "ตรวจสอบ cloudflared"
if (-not (Test-Path $Cloudflared)) { throw "ไม่พบ cloudflared ที่ $Cloudflared" }
& $Cloudflared --version
Ok "พร้อมใช้งาน"

Step "ตรวจว่า origin ($OriginPort) เปิดอยู่จริง"
$listening = (Test-NetConnection -ComputerName 127.0.0.1 -Port $OriginPort `
    -WarningAction SilentlyContinue).TcpTestSucceeded
if ($listening) { Ok "พอร์ต $OriginPort listening อยู่" }
else { Warn "ไม่มีอะไร listening ที่พอร์ต $OriginPort — tunnel จะขึ้น 502 (รัน install-iis-site.ps1 ก่อน)" }

# --- 1) ผูก DNS route ------------------------------------------------
Step "ผูก DNS route -> tunnel $TunnelName"
# cloudflared เขียน log ลง stderr เป็นปกติ — ปิด Stop ชั่วคราวไม่ให้ PowerShell มองว่าเป็น error
foreach ($h in $Hostnames) {
    $ErrorActionPreference = "Continue"
    $out = & $Cloudflared tunnel route dns $TunnelName $h 2>&1
    $ErrorActionPreference = "Stop"
    if ($LASTEXITCODE -eq 0) { Ok "$h -> ผูก DNS สำเร็จ" }
    elseif ("$out" -match "already exists|already configured|record with that host") { Ok "$h -> มี DNS record อยู่แล้ว" }
    else { Warn "$h -> route dns: $out" }
}
# ใช้โดเมนแรกเป็นตัวแทนตอนทดสอบ
$Hostname = $Hostnames[0]

# --- 2) เขียน config.yml --------------------------------------------
Step "เขียน config -> $ConfigPath"
$src = Join-Path $PSScriptRoot "config.yml"
if (-not (Test-Path $src)) { throw "ไม่พบไฟล์ต้นฉบับ $src" }
$dir = Split-Path $ConfigPath -Parent
New-Item -ItemType Directory -Force -Path $dir | Out-Null
if (Test-Path $ConfigPath) {
    Copy-Item $ConfigPath "$ConfigPath.bak" -Force
    Warn "สำรองของเดิมไว้ที่ $ConfigPath.bak"
}
Copy-Item $src $ConfigPath -Force
Ok "เขียน config แล้ว"

# --- 3) ตรวจ config ---------------------------------------------------
Step "ตรวจ ingress rules"
$ErrorActionPreference = "Continue"
& $Cloudflared tunnel --config $ConfigPath ingress validate 2>&1 | Write-Host
$ErrorActionPreference = "Stop"

# --- 4) รัน ---------------------------------------------------------
if ($InstallService) {
    Step "ติดตั้งเป็น Windows Service"
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "ติดตั้ง service ต้องรันแบบ Run as Administrator" }

    $ErrorActionPreference = "Continue"
    if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
        sc.exe stop Cloudflared | Out-Null
        Start-Sleep -Seconds 3
    }
    Get-Process cloudflared* -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
        Stop-Service cloudflared -Force -ErrorAction SilentlyContinue
        & $Cloudflared service uninstall 2>&1 | Write-Host
        Warn "ถอน service เดิมออกก่อน"
    }
    # ถ้าเคยลบ service ด้วย sc.exe จะเหลือ registry ของ event logger ค้าง
    # ทำให้ติดตั้งใหม่ไม่ผ่าน ("registry key already exists")
    $evtKey = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\Cloudflared"
    if (Test-Path $evtKey) {
        Remove-Item $evtKey -Recurse -Force -ErrorAction SilentlyContinue
        Warn "ลบ registry ของ event logger ที่ค้างอยู่"
    }
    if ([string]::IsNullOrWhiteSpace($env:PROGRAMDATA)) { $env:PROGRAMDATA = "C:\ProgramData" }

    & $Cloudflared --config $ConfigPath service install 2>&1 | Write-Host
    $ErrorActionPreference = "Stop"

    # ------------------------------------------------------------------
    # cloudflared บน Windows ติดตั้ง service แบบไม่ส่ง --config ให้ (ImagePath = แค่ .exe)
    # และ service รันด้วยบัญชี SYSTEM ซึ่งอ่านไฟล์ใน C:\Users\<user>\.cloudflared ไม่ได้
    # -> ผลคือ tunnel ไม่มี connection เลย (เว็บขึ้น error 530 / 1033)
    #
    # แก้โดยวาง config + credentials ไว้ที่ ProgramData (SYSTEM อ่านได้)
    # แล้วเขียน ImagePath ให้ชี้ config นั้นตรง ๆ
    # ------------------------------------------------------------------
    Step "เตรียม config สำหรับ service ที่ ProgramData"
    $svcDir = Join-Path $env:PROGRAMDATA "Cloudflare\cloudflared"
    New-Item -ItemType Directory -Force -Path $svcDir | Out-Null

    # ต้องอ่านแบบ UTF-8 ชัดเจน — Get-Content ของ PowerShell 5.1 อ่านเป็น ANSI
    # ทำให้ตัวอักษรไทยเพี้ยนจนกลายเป็น control character แล้ว cloudflared parse YAML ไม่ผ่าน
    $cfgLines = [IO.File]::ReadAllLines($ConfigPath, (New-Object Text.UTF8Encoding($false)))
    $credLine = $cfgLines | Where-Object { $_ -match '^\s*credentials-file\s*:' } | Select-Object -First 1
    $credSrc  = ($credLine -replace '^\s*credentials-file\s*:\s*', '').Trim()
    if (-not (Test-Path $credSrc)) { throw "ไม่พบไฟล์ credentials: $credSrc" }

    $credDst = Join-Path $svcDir (Split-Path $credSrc -Leaf)
    Copy-Item $credSrc $credDst -Force
    Ok "คัดลอก credentials -> $credDst"

    $svcCfg = Join-Path $svcDir "config.yml"
    # ต้องเขียนแบบ UTF-8 ไม่มี BOM ไม่งั้น YAML parser ของ cloudflared จะพัง
    $newLines = $cfgLines -replace '^\s*credentials-file\s*:.*$', "credentials-file: $credDst"
    [IO.File]::WriteAllLines($svcCfg, $newLines, (New-Object Text.UTF8Encoding($false)))
    Ok "เขียน config ของ service -> $svcCfg"

    $svcKey    = "HKLM:\SYSTEM\CurrentControlSet\Services\Cloudflared"
    $imagePath = "`"$Cloudflared`" --config `"$svcCfg`" tunnel run $TunnelName"
    Set-ItemProperty -Path $svcKey -Name ImagePath -Value $imagePath
    Ok "ImagePath = $imagePath"

    # ต้อง stop ก่อน เพราะ service install สตาร์ต service ไปแล้วด้วย ImagePath เดิม (ไม่มี --config)
    # ถ้าไม่ stop process เดิมจะยังรันด้วยค่าเก่า -> tunnel ไม่มี connection (error 530/1033)
    $ErrorActionPreference = "Continue"
    sc.exe stop Cloudflared | Out-Null
    Start-Sleep -Seconds 4
    Get-Process cloudflared* -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    $ErrorActionPreference = "Stop"

    Start-Service cloudflared
    Start-Sleep -Seconds 8
    Get-Service cloudflared | Select-Object Name, Status, StartType | Format-Table
    Ok "service ทำงานแล้ว (จะเริ่มเองทุกครั้งที่รีบูต)"

    Step "ทดสอบผ่านอินเทอร์เน็ต"
    $passed = $false
    foreach ($i in 1..8) {
        Start-Sleep -Seconds 6
        try {
            $r = Invoke-WebRequest "https://$Hostname/health" -UseBasicParsing -TimeoutSec 20
            Ok "https://$Hostname/health -> $($r.Content)"
            $passed = $true
            break
        } catch { Write-Host "    ...ลองครั้งที่ $i : $($_.Exception.Message)" -ForegroundColor DarkGray }
    }
    if (-not $passed) {
        Warn "ยังเรียกไม่ได้ — ดู log ที่ F:\Game\cloudflared.log"
    } else {
        try {
            $r = Invoke-WebRequest "https://$Hostname/" -UseBasicParsing -TimeoutSec 20
            Ok "หน้าเว็บ https://$Hostname/ -> HTTP $($r.StatusCode)"
        } catch { Warn "หน้าเว็บ: $($_.Exception.Message)" }
    }
}
else {
    Step "ทดสอบรันแบบหน้าจอ (Ctrl+C เพื่อหยุด)"
    Write-Host "    เปิด https://$Hostname ในเบราว์เซอร์เพื่อตรวจผล" -ForegroundColor DarkGray
    & $Cloudflared tunnel --config $ConfigPath run $TunnelName
}
