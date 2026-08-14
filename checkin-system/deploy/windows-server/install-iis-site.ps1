# ===================================================================
# ติดตั้ง IIS + URL Rewrite + ARR แล้วสร้างเว็บไซต์ "checkin" ที่พอร์ต 80
#
#   IIS :80  ├─ React ที่ build แล้ว (static)
#            └─ /auth /reports /faces ... → reverse proxy → uvicorn 127.0.0.1:8001
#
# ต้องรัน PowerShell แบบ "Run as Administrator"
# วิธีใช้:
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\windows-server
#     .\install-iis-site.ps1
# ===================================================================
[CmdletBinding()]
param(
    [string]$SiteName = "checkin",
    [string]$SitePath = "C:\inetpub\checkin",
    [int]$Port = 80,
    # โฟลเดอร์ frontend (React) ที่จะ build (เว้นว่าง = หาอัตโนมัติจากที่ตั้งสคริปต์)
    [string]$FrontendDir = "",
    # ปล่อยว่าง = React เรียก API ที่โดเมนเดียวกัน (ไม่มี /api นำหน้า)
    [string]$ApiBase = ""
)

$ErrorActionPreference = "Stop"

# ที่ตั้งของสคริปต์ (ใช้ $PSScriptRoot ไม่ได้ใน param block)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($FrontendDir)) {
    $FrontendDir = (Resolve-Path (Join-Path $here "..\..\frontend")).Path
}

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

# --- ตรวจสิทธิ์ Administrator ---------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "ต้องรัน PowerShell แบบ Run as Administrator" }

# --- 1) ติดตั้ง IIS -------------------------------------------------
Step "ติดตั้ง IIS (ข้ามถ้าติดตั้งแล้ว)"
Install-WindowsFeature -Name Web-Server, Web-Mgmt-Console, Web-Static-Content, `
    Web-Default-Doc, Web-Http-Errors, Web-Http-Logging, Web-Request-Monitor, `
    Web-Filtering, Web-Stat-Compression | Out-Null
Ok "IIS พร้อมใช้งาน"

Import-Module WebAdministration

# --- 2) ติดตั้ง URL Rewrite + ARR ----------------------------------
$tmp = "C:\temp-iis"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$ProgressPreference = "SilentlyContinue"

$rewriteInstalled = Test-Path "$env:SystemRoot\System32\inetsrv\rewrite.dll"
if (-not $rewriteInstalled) {
    Step "ดาวน์โหลด + ติดตั้ง URL Rewrite 2.1"
    $url = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
    Invoke-WebRequest -Uri $url -OutFile "$tmp\rewrite.msi" -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$tmp\rewrite.msi`" /quiet /norestart" -Wait
    Ok "ติดตั้ง URL Rewrite แล้ว"
} else { Ok "URL Rewrite ติดตั้งอยู่แล้ว" }

$arrInstalled = Test-Path "$env:SystemRoot\System32\inetsrv\requestRouter.dll"
if (-not $arrInstalled) {
    Step "ดาวน์โหลด + ติดตั้ง Application Request Routing 3.0"
    $url = "https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi"
    Invoke-WebRequest -Uri $url -OutFile "$tmp\arr.msi" -UseBasicParsing
    Start-Process msiexec.exe -ArgumentList "/i `"$tmp\arr.msi`" /quiet /norestart" -Wait
    Ok "ติดตั้ง ARR แล้ว"
} else { Ok "ARR ติดตั้งอยู่แล้ว" }

# --- 3) เปิด proxy ของ ARR (จำเป็น ไม่งั้น API จะ 404) -------------
Step "เปิด ARR proxy"
& "$env:SystemRoot\System32\inetsrv\appcmd.exe" set config -section:system.webServer/proxy `
    /enabled:"True" /preserveHostHeader:"False" /reverseRewriteHostInResponseHeaders:"False" `
    /commit:apphost | Out-Null
Ok "ARR proxy = enabled"

# --- 4) build React --------------------------------------------------
Step "build React frontend"
if (-not (Test-Path $FrontendDir)) { throw "ไม่พบโฟลเดอร์ frontend: $FrontendDir" }
Push-Location $FrontendDir
try {
    if (-not (Test-Path "node_modules")) {
        Write-Host "    npm install ..." -ForegroundColor DarkGray
        npm install --no-fund --no-audit
    }
    # ให้ React ยิง API แบบ relative -> ผ่าน IIS reverse proxy (same-origin)
    $env:VITE_API_BASE = $ApiBase
    npm run build
} finally { Pop-Location }
Ok "build เสร็จ -> $FrontendDir\dist"

# --- 5) วางไฟล์ลงโฟลเดอร์เว็บไซต์ ----------------------------------
Step "คัดลอกไฟล์ไป $SitePath"
New-Item -ItemType Directory -Force -Path $SitePath | Out-Null
Get-ChildItem $SitePath -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$FrontendDir\dist\*" $SitePath -Recurse -Force
Copy-Item "$here\web.config" $SitePath -Force
Ok "คัดลอกไฟล์เรียบร้อย"

# --- 6) สร้าง/อัปเดตเว็บไซต์ IIS ------------------------------------
Step "ตั้งค่าเว็บไซต์ IIS '$SiteName' ที่พอร์ต $Port"

# ปลด Default Web Site ออกจากพอร์ต 80
# ต้อง "ลบ binding" ไม่ใช่แค่ Stop เพราะ iisreset จะสตาร์ตกลับมาแย่งพอร์ต
$dws = Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
if ($dws -and $dws.Name -ne $SiteName) {
    Get-WebBinding -Name "Default Web Site" -Port $Port -ErrorAction SilentlyContinue |
        Remove-WebBinding -ErrorAction SilentlyContinue
    Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    Warn "ลบ binding พอร์ต $Port ของ 'Default Web Site' และหยุดเว็บไซต์แล้ว"
}

if (-not (Test-Path "IIS:\AppPools\$SiteName")) {
    New-WebAppPool -Name $SiteName | Out-Null
}
# ไม่ได้รันโค้ด .NET (เสิร์ฟ static + proxy เท่านั้น)
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name managedRuntimeVersion -Value ""

$site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if ($site) {
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath   -Value $SitePath
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationPool -Value $SiteName
} else {
    New-Website -Name $SiteName -Port $Port -PhysicalPath $SitePath `
        -ApplicationPool $SiteName -Force | Out-Null
}
# binding: Host name ว่าง = รับทุกโดเมน (จำเป็นสำหรับ Cloudflare Tunnel)
Get-WebBinding -Name $SiteName | Remove-WebBinding
New-WebBinding -Name $SiteName -Protocol http -Port $Port -IPAddress "*" -HostHeader ""
Start-Website -Name $SiteName
Ok "เว็บไซต์ '$SiteName' ทำงานที่พอร์ต $Port"

# --- 7) ตรวจผล -------------------------------------------------------
Step "ทดสอบ"
Start-Sleep -Seconds 2
try {
    $r = Invoke-WebRequest "http://localhost:$Port/" -UseBasicParsing -TimeoutSec 10
    Ok "หน้าเว็บ: HTTP $($r.StatusCode)"
} catch { Warn "หน้าเว็บยังเรียกไม่ได้: $($_.Exception.Message)" }
try {
    $r = Invoke-WebRequest "http://localhost:$Port/health" -UseBasicParsing -TimeoutSec 10
    Ok "API proxy: $($r.Content)"
} catch { Warn "API proxy ยังเรียกไม่ได้ (backend รันที่ :8000 อยู่หรือเปล่า?) — $($_.Exception.Message)" }

Write-Host "`nเสร็จแล้ว — ต่อไปรัน deploy\cloudflare\setup-tunnel.ps1 เพื่อเปิดออกอินเทอร์เน็ต`n" -ForegroundColor Green
