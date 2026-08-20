# ===================================================================
# อัปเดตโค้ดที่แก้แล้วขึ้น production ในคำสั่งเดียว
#
#   build React  ->  copy ขึ้น IIS (C:\inetpub\checkin)  ->  restart backend
#   แล้วยิงทดสอบผ่าน https://thanakronpart-time.com
#
# ต้องรัน PowerShell แบบ "Run as Administrator"
# (ใน VS Code ใช้ Task: "Deploy: อัปเดตขึ้น production")
#
# ตรวจสถานะอย่างเดียว ไม่ deploy:
#     .\deploy-update.ps1 -CheckOnly
# ===================================================================
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$SkipFrontend,
    [string]$SitePath = "C:\inetpub\checkin",
    [string]$TaskName = "MardodiCheckinAPI",
    [string]$Hostname = "thanakronpart-time.com",
    [int]$BackendPort = 8001
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here "..\..")).Path

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

function Test-Url($label, $url) {
    try {
        $r = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 25
        $c = $r.Content
        if ($c.Length -gt 100) { $c = $c.Substring(0, 100) + "..." }
        Ok "$label -> HTTP $($r.StatusCode) | $c"
        return $true
    } catch {
        Warn "$label -> $($_.Exception.Message)"
        return $false
    }
}

# ------------------------------------------------------------------
# โหมดตรวจสถานะอย่างเดียว
# ------------------------------------------------------------------
if ($CheckOnly) {
    Step "สถานะบริการ"
    Get-Service W3SVC, cloudflared -ErrorAction SilentlyContinue |
        Select-Object Name, Status, StartType | Format-Table -AutoSize
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
        Select-Object TaskName, State | Format-Table -AutoSize

    Step "ทดสอบภายในเครื่อง"
    Test-Url "backend :$BackendPort"  "http://127.0.0.1:$BackendPort/health" | Out-Null
    Test-Url "IIS หน้าเว็บ"           "http://localhost/"                    | Out-Null
    Test-Url "IIS API /health"       "http://localhost/health"      | Out-Null

    Step "ทดสอบผ่านอินเทอร์เน็ต"
    Test-Url "หน้าเว็บ"          "https://$Hostname/"                  | Out-Null
    Test-Url "API /health"       "https://$Hostname/health"            | Out-Null
    Test-Url "API /reports/geofence" "https://$Hostname/reports/geofence" | Out-Null
    return
}

# ------------------------------------------------------------------
# โหมด deploy
# ------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "ต้องเปิด VS Code / PowerShell แบบ Run as Administrator ถึงจะ restart service ได้"
}

if (-not $SkipFrontend) {
    Step "build React"
    Push-Location (Join-Path $root "frontend")
    try {
        if (-not (Test-Path "node_modules")) { npm install --no-fund --no-audit }
        # ปล่อยว่าง = เรียก API ที่โดเมนเดียวกัน (ไม่มี /api นำหน้าแล้ว)
        $env:VITE_API_BASE = ""
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build ล้มเหลว" }
    } finally { Pop-Location }
    Ok "build เสร็จ"

    Step "copy ไฟล์ขึ้น IIS ($SitePath)"
    $webConfig = Join-Path $SitePath "web.config"
    Get-ChildItem $SitePath -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "web.config" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $root "frontend\dist\*") $SitePath -Recurse -Force
    Copy-Item (Join-Path $here "web.config") $webConfig -Force
    Ok "copy เรียบร้อย"
}

Step "restart backend ($TaskName)"
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Get-Process python -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$root\backend*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $TaskName
Ok "สั่ง restart แล้ว"

Step "รอ backend พร้อม"
$ready = $false
foreach ($i in 1..15) {
    Start-Sleep -Seconds 2
    try {
        Invoke-WebRequest "http://127.0.0.1:$BackendPort/health" -UseBasicParsing -TimeoutSec 5 | Out-Null
        $ready = $true
        break
    } catch { }
}
if ($ready) { Ok "backend :$BackendPort พร้อมแล้ว" } else { Warn "backend ยังไม่ตอบ" }

Step "ตรวจผลผ่านโดเมนจริง"
Test-Url "หน้าเว็บ"              "https://$Hostname/"                  | Out-Null
Test-Url "API /health"           "https://$Hostname/health"            | Out-Null
Test-Url "API /reports/geofence" "https://$Hostname/reports/geofence"  | Out-Null

Write-Host "`nเสร็จแล้ว — เปิด https://$Hostname เพื่อดูผล`n" -ForegroundColor Green
