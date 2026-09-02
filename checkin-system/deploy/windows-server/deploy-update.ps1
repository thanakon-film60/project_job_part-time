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

# เรียกโปรแกรมภายนอก (npm ฯลฯ) แล้วตัดสินผลจาก exit code เท่านั้น
#
# npm เขียนคำเตือน (npm warn ...) ลง stderr เป็นเรื่องปกติ แต่ PowerShell 5.1
# กับ $ErrorActionPreference = "Stop" จะแปลง stderr ของโปรแกรมภายนอกเป็น error
# แล้วหยุดสคริปต์กลางคัน — deploy จะตายตั้งแต่ npm install ทั้งที่ยังไม่มีอะไรพัง
# ตรงนี้จึงลด ErrorActionPreference ชั่วคราวเฉพาะตอนเรียกโปรแกรมภายนอก
function Invoke-Native($exe, $arguments, $failMessage) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $exe @arguments
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($LASTEXITCODE -ne 0) { throw $failMessage }
}

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

# ตรวจว่า IIS ส่งต่อ "ทุก router ที่ backend มี" ไปให้ backend จริงหรือยัง
#
# ทำไมต้องมีตัวนี้: กฎ ProxyToBackend ใน web.config เป็นรายชื่อที่พิมพ์มือ
# ถ้าเพิ่ม router ใหม่ใน backend แล้วลืมเติมชื่อลงในกฎ คำขอจะไม่ตกไป backend
# แต่ไปเข้ากฎ StaticFiles แล้ว IIS ตอบหน้า index.html กลับมาด้วยรหัส 200
# — เช็คแค่รหัสสถานะจะเห็นเป็น "ผ่าน" ทั้งที่ API เส้นนั้นใช้ไม่ได้เลย
#
# เกิดขึ้นจริงกับ /camera/* มาแล้ว: backend มีเส้นทางครบ แต่ IIS ยังใช้กฎเก่า
# แอปหัวหน้าจึงขึ้นว่า "เซิร์ฟเวอร์ตอบข้อมูลผิดรูปแบบ (text/html)"
#
# ตัวนี้ไม่ได้ใช้รายชื่อที่พิมพ์ไว้เอง แต่ไปอ่าน /openapi.json ของ backend
# แล้วดึงชื่อ router ออกมาทั้งหมด router ใหม่จึงถูกตรวจให้เองโดยไม่ต้องมาแก้ที่นี่

# ยิง 1 คำขอแล้วคืน (รหัสสถานะ, ชนิดข้อมูล) — 401/404/405 ไม่ถือเป็นความผิดพลาด
# (PowerShell 5.1 โยน WebException ส่วน PowerShell 7 โยน HttpResponseException)
function Get-UrlInfo($url, [switch]$NoRedirect) {
    $args = @{ Uri = $url; UseBasicParsing = $true; TimeoutSec = 25 }
    # ห้ามตามรีไดเรกต์ตอนตรวจเส้นทาง — FastAPI ตอบ 307 เพื่อตัด / ท้าย path
    # แล้ว IIS ส่ง Location เป็นที่อยู่ภายใน (https://127.0.0.1:8001/...) ออกมา
    # ถ้าตามต่อ เราจะไปยิงเครื่องตัวเองแล้วได้ error ที่ไม่เกี่ยวกับเรื่องที่ตรวจ
    if ($NoRedirect) { $args.MaximumRedirection = 0 }
    try {
        $r = Invoke-WebRequest @args
        return @{ Status = [int]$r.StatusCode; Type = ($r.Headers['Content-Type'] -join ','); Error = $null }
    } catch {
        $res = $_.Exception.Response
        if ($null -eq $res) { return @{ Status = 0; Type = ""; Error = $_.Exception.Message } }
        if ($res -is [System.Net.HttpWebResponse]) {
            return @{ Status = [int]$res.StatusCode; Type = $res.ContentType; Error = $null }
        }
        # PowerShell 7: HttpResponseMessage
        $type = ""
        if ($res.Content -and $res.Content.Headers.ContentType) { $type = $res.Content.Headers.ContentType.ToString() }
        return @{ Status = [int]$res.StatusCode; Type = $type; Error = $null }
    }
}

function Test-BackendRouting($baseUrl) {
    $spec = Get-UrlInfo "$baseUrl/openapi.json"
    if ($spec.Type -notlike "*json*") {
        Warn "อ่าน /openapi.json ไม่ได้ (ได้ '$($spec.Type)') ข้ามการตรวจเส้นทาง"
        return $true
    }

    try {
        $paths = (Invoke-WebRequest "$baseUrl/openapi.json" -UseBasicParsing -TimeoutSec 25).Content |
            ConvertFrom-Json | ForEach-Object { $_.paths.PSObject.Properties.Name }
    } catch {
        Warn "แปลง /openapi.json ไม่สำเร็จ: $($_.Exception.Message)"
        return $true
    }

    # ชื่อ router = ส่วนแรกของ path เช่น /camera/status -> camera
    $prefixes = $paths |
        ForEach-Object { ($_ -split '/')[1] } |
        Where-Object { $_ } |
        Sort-Object -Unique

    $missing = @()
    foreach ($prefix in $prefixes) {
        # ขอที่ราก router ตรงๆ (เช่น /camera/) — backend ตอบ 404 เป็น JSON เสมอ
        # จึงไม่ไปกระทบข้อมูลอะไร และไม่โหลดไฟล์ใหญ่อย่าง /app/download
        $info = Get-UrlInfo "$baseUrl/$prefix/" -NoRedirect
        if ($info.Error) {
            Warn "  /$prefix/ -> $($info.Error)"
            continue
        }
        # 3xx = backend เป็นคนตอบแน่นอน (กฎ StaticFiles ไม่มีทางตอบรีไดเรกต์)
        # ส่วนกรณีอื่นดูที่ชนิดข้อมูล: backend ตอบ JSON เสมอ หน้าเว็บตอบ HTML
        if ($info.Status -ge 300 -and $info.Status -lt 400) {
            Ok "  /$prefix/ -> ส่งต่อไป backend แล้ว (HTTP $($info.Status))"
        } elseif ($info.Type -like "*json*") {
            Ok "  /$prefix/ -> ส่งต่อไป backend แล้ว (HTTP $($info.Status))"
        } else {
            $missing += $prefix
            Warn "  /$prefix/ -> HTTP $($info.Status) ได้ '$($info.Type)' = ตกไปเป็นหน้าเว็บ React"
        }
    }

    if ($missing.Count -gt 0) {
        Warn ""
        Warn "router ที่ IIS ยังไม่ส่งต่อ: $($missing -join ', ')"
        Warn "แก้ที่ deploy\windows-server\web.config กฎ ProxyToBackend"
        Warn "เติมชื่อพวกนี้ลงในวงเล็บ ^(app|auth|...)  แล้ว deploy ใหม่อีกครั้ง"
        return $false
    }
    return $true
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

    Step "ตรวจว่า IIS ส่งต่อทุก router ของ backend"
    Test-BackendRouting "https://$Hostname" | Out-Null
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
        # รัน npm install ทุกครั้ง ไม่ใช่เฉพาะตอนไม่มี node_modules --
        # ถ้ามีการเพิ่มไลบรารีใหม่ใน package.json (เช่น leaflet) แล้วข้ามขั้นนี้
        # build จะพังเพราะ resolve import ไม่เจอ npm ไม่ทำอะไรถ้าครบอยู่แล้ว
        Invoke-Native "npm" @("install", "--no-fund", "--no-audit") "npm install ล้มเหลว"
        # ปล่อยว่าง = เรียก API ที่โดเมนเดียวกัน (ไม่มี /api นำหน้าแล้ว)
        $env:VITE_API_BASE = ""
        Invoke-Native "npm" @("run", "build") "npm run build ล้มเหลว"
    } finally { Pop-Location }
    Ok "build เสร็จ"

    Step "copy หน้าเว็บขึ้น IIS ($SitePath)"
    Get-ChildItem $SitePath -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "web.config" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $root "frontend\dist\*") $SitePath -Recurse -Force
    Ok "copy หน้าเว็บเรียบร้อย"
}

# web.config ต้อง copy ทุกครั้ง แม้ใช้ -SkipFrontend
#
# มันไม่ใช่ไฟล์ของหน้าเว็บ แต่เป็น "ตารางเส้นทาง" ที่บอก IIS ว่า path ไหน
# ต้องส่งต่อไป backend เพราะฉะนั้นเวลาเพิ่ม router ใหม่ใน backend อย่างเดียว
# (ซึ่งเป็นเหตุผลที่คนใช้ -SkipFrontend) คือเวลาที่ "ต้อง" อัปเดตไฟล์นี้ที่สุด
#
# เคยพลาดมาแล้วกับ /camera/*: deploy ด้วย -SkipFrontend ทำให้ backend มีเส้นทาง
# ครบแต่ IIS ยังใช้กฎเก่าที่ไม่มี camera คำขอเลยตกไปเป็นหน้าเว็บ React
# แล้วแอปหัวหน้าขึ้นว่า "เซิร์ฟเวอร์ตอบข้อมูลผิดรูปแบบ (text/html)"
Step "copy web.config ขึ้น IIS ($SitePath)"
Copy-Item (Join-Path $here "web.config") (Join-Path $SitePath "web.config") -Force
Ok "copy web.config เรียบร้อย"

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

Step "ตรวจว่า IIS ส่งต่อทุก router ของ backend"
$routesOk = Test-BackendRouting "https://$Hostname"

if ($routesOk) {
    Write-Host "`nเสร็จแล้ว — เปิด https://$Hostname เพื่อดูผล`n" -ForegroundColor Green
} else {
    Write-Host "`ndeploy เสร็จ แต่มีเส้นทาง API ที่ IIS ยังไม่ส่งต่อไป backend" -ForegroundColor Yellow
    Write-Host "ดูข้อความ [!] ด้านบนว่าเส้นทางไหน แล้วแก้กฎ ProxyToBackend ใน web.config`n" -ForegroundColor Yellow
}
