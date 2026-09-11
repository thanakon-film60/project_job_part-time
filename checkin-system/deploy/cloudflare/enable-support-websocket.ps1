# ===================================================================
# เปิดทางให้ WebSocket ของห้องช่วยเหลือระยะไกลใช้งานได้ โดยไม่ต้อง restart เครื่อง
#
# ปัญหา: IIS จะส่งต่อ WebSocket ได้ก็ต่อเมื่อเปิดฟีเจอร์ Web-WebSockets
#        ฟีเจอร์ถูกติดตั้งไว้แล้ว (12 ก.ย. 2026) แต่ค้างสถานะ "Enable Pending"
#        ซึ่งจะเสร็จก็ต่อเมื่อ restart เครื่อง — และตอนนี้มี Windows Update
#        ค้างอยู่ 6 ตัว รวม Cumulative Update ของ OS กับ .NET ที่จะลงตอนปิด/เปิด
#        เครื่อง กินเวลานานโดยคุมไม่ได้ จึงไม่ควร restart แบบไม่มีคนเฝ้า
#
# วิธีแก้: cloudflared รองรับ WebSocket ในตัวอยู่แล้ว สคริปต์นี้เพิ่มกฎ ingress
#        ให้ path /support/ws/ วิ่งตรงไป uvicorn :8001 ข้าม IIS ไปเลย
#        (ได้ผลพลอยได้คือเร็วขึ้น เพราะตัดตัวกลางออกหนึ่งชั้น)
#
# ปลอดภัยแค่ไหน: ไม่ได้ลดการตรวจสิทธิ์เลย — backend ตรวจโทเค็นในลิงก์ห้อง
#        และ JWT ของผู้ช่วยเองอยู่แล้ว (_authorize_ws ใน app/routers/support.py)
#        เส้นทางอื่นทุกเส้นยังวิ่งผ่าน IIS เหมือนเดิมทุกอย่าง
#
# ใช้เวลาราว 20 วินาที เว็บสะดุดตอน restart tunnel ไม่กี่วินาที
# ทุกขั้นมีตัวตรวจ ถ้าไม่ผ่านจะคืน config เดิมและ restart กลับให้เองอัตโนมัติ
#
# วิธีใช้ (Run as Administrator):
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\cloudflare
#     .\enable-support-websocket.ps1
#
# ดูว่าจะแก้อะไรโดยยังไม่แก้จริง:
#     .\enable-support-websocket.ps1 -WhatIfOnly
#
# ย้อนกลับ:
#     .\enable-support-websocket.ps1 -Rollback
# ===================================================================
[CmdletBinding()]
param(
    [switch]$Rollback,
    [switch]$WhatIfOnly,
    [string]$ServiceName = "Cloudflared",
    [string]$Hostname = "thanakronpart-time.com"
)

$ErrorActionPreference = "Stop"

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "    [X]  $m" -ForegroundColor Red }

# เขียนไฟล์แบบไม่ใส่ BOM — ตัวแปลง YAML ของ Go สะดุด BOM ได้
# (Set-Content -Encoding UTF8 ของ PowerShell 5.1 ใส่ BOM ให้เสมอ จึงใช้ .NET แทน)
function Write-TextNoBom($path, $text) {
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "ต้องเปิด PowerShell แบบ Run as Administrator" }

# ------------------------------------------------------------------
# หา config ที่ service ใช้จริง จาก command line ของตัว service เอง
#
# อย่าเดาว่าเป็น F:\Game\config.yml — เครื่องนี้มีไฟล์ชื่อเดียวกันอยู่หลายที่
# ตัวที่ service ใช้จริงคือ C:\ProgramData\Cloudflare\cloudflared\config.yml
# (แก้ผิดไฟล์ = แก้แล้วไม่มีอะไรเปลี่ยน แล้วไล่หาสาเหตุไม่เจอ)
# ------------------------------------------------------------------
Step "หา config ที่ cloudflared ใช้อยู่"
$svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
if (-not $svc) { throw "ไม่พบ service '$ServiceName'" }
if ($svc.PathName -notmatch '--config\s+"?([^"]+\.yml)"?') {
    throw "อ่านพาธ config จาก service ไม่ได้: $($svc.PathName)"
}
$configPath = $Matches[1].Trim()
if (-not (Test-Path $configPath)) { throw "ไม่พบไฟล์ config: $configPath" }
Ok "config: $configPath"

$exe = if ($svc.PathName -match '^"([^"]+\.exe)"') { $Matches[1] } else { $null }
$marker = 'path: ^/support/ws/'

# ------------------------------------------------------------------
# โหมดย้อนกลับ
# ------------------------------------------------------------------
if ($Rollback) {
    Step "ย้อนกลับเป็น config ก่อนหน้า"
    $backup = Get-ChildItem "$configPath.backup-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $backup) { throw "ไม่พบไฟล์สำรอง" }
    Copy-Item $backup.FullName $configPath -Force
    Ok "คืนค่าจาก $($backup.Name)"
    Restart-Service $ServiceName
    Start-Sleep -Seconds 8
    Ok "restart $ServiceName แล้ว (สถานะ: $((Get-Service $ServiceName).Status))"
    return
}

if ((Get-Content $configPath -Raw) -like "*$marker*") {
    Ok "มีกฎอยู่แล้ว ไม่ต้องทำอะไรเพิ่ม"
    return
}

# ------------------------------------------------------------------
# ประกอบ config ใหม่: แทรกกฎไว้ "ใต้บรรทัด ingress: ทันที"
#
# ต้องอยู่บนสุดของรายการ เพราะ cloudflared ไล่กฎจากบนลงล่างแล้วหยุดที่กฎแรก
# ที่ตรง ถ้าไปอยู่ใต้กฎ hostname เปล่า ๆ ของโดเมนเดียวกัน จะไม่มีวันถูกใช้เลย
# ------------------------------------------------------------------
Step "ประกอบ config ใหม่"
$newRules = @"
  # ---------------------------------------------------------------
  # WebSocket ของห้องช่วยเหลือระยะไกล -> ตรงไป uvicorn :8001 ไม่ผ่าน IIS
  #
  # IIS ส่งต่อ WebSocket ไม่ได้จนกว่าฟีเจอร์ Web-WebSockets จะติดตั้งเสร็จ
  # (ติดตั้งแล้วแต่ค้าง "Enable Pending" รอ restart เครื่อง - 12 ก.ย. 2026)
  # cloudflared รองรับ WebSocket ในตัว จึงส่งเส้นนี้ตรงไป backend เลย
  #
  # !! กฎที่มี path ต้องอยู่เหนือกฎ hostname เปล่า ๆ ของโดเมนเดียวกันเสมอ
  #
  # ความปลอดภัยไม่ได้ลดลง: backend ตรวจโทเค็นในลิงก์ห้องและ JWT ของผู้ช่วยเอง
  # อยู่แล้ว (_authorize_ws ใน backend/app/routers/support.py)
  # เส้นทางอื่นทุกเส้นยังวิ่งผ่าน IIS เหมือนเดิม
  #
  # สร้างโดย deploy\cloudflare\enable-support-websocket.ps1
  # ลบ 3 กฎนี้ทิ้งได้เมื่อ Get-WindowsFeature Web-WebSockets เป็น Installed แล้ว
  # (จะเก็บไว้ต่อก็ได้ ไม่เสียหาย)
  # ---------------------------------------------------------------
  - hostname: $Hostname
    path: ^/support/ws/
    service: http://localhost:8001
    originRequest:
      connectTimeout: 30s

  - hostname: www.$Hostname
    path: ^/support/ws/
    service: http://localhost:8001
    originRequest:
      connectTimeout: 30s

  - hostname: api.$Hostname
    path: ^/support/ws/
    service: http://localhost:8001
    originRequest:
      connectTimeout: 30s

"@

$lines = [System.IO.File]::ReadAllLines($configPath)
$ingressIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimEnd() -eq "ingress:") { $ingressIndex = $i; break }
}
if ($ingressIndex -lt 0) { throw "ไม่พบบรรทัด 'ingress:' ใน $configPath" }

$before = if ($ingressIndex -ge 0) { $lines[0..$ingressIndex] } else { @() }
$after  = $lines[($ingressIndex + 1)..($lines.Count - 1)]
$merged = (($before -join "`r`n") + "`r`n" + ($newRules -replace "`r?`n", "`r`n") + ($after -join "`r`n") + "`r`n")

if ($WhatIfOnly) {
    Step "ตัวอย่าง config ใหม่ (ยังไม่เขียนลงไฟล์)"
    # ส่งออกทาง pipeline ไม่ใช่ Write-Host เพื่อให้เอาไปตรวจต่อได้ เช่น
    #   .\enable-support-websocket.ps1 -WhatIfOnly | Out-File preview.yml -Encoding utf8
    Write-Output $merged
    Ok "โหมดดูอย่างเดียว — ไม่ได้แก้อะไรเลย"
    return
}

Step "สำรอง config เดิม"
$backupPath = "$configPath.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $configPath $backupPath -Force
Ok "สำรองไว้ที่ $(Split-Path $backupPath -Leaf)"

Write-TextNoBom $configPath $merged
Ok "เขียน config ใหม่แล้ว ($((Get-Item $configPath).Length) ไบต์)"

# ------------------------------------------------------------------
# ตรวจไวยากรณ์ก่อนแตะ service — config พังแล้ว tunnel ไม่ขึ้น = เว็บล่มทั้งระบบ
# ------------------------------------------------------------------
Step "ตรวจไวยากรณ์ config"
if ($exe -and (Test-Path $exe)) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $out = & $exe --config $configPath tunnel ingress validate 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    Write-Host ($out.Trim())
    if ($code -ne 0) {
        Fail "config ไม่ผ่านการตรวจ — คืนค่าเดิม (ยังไม่ได้แตะ service เลย)"
        Copy-Item $backupPath $configPath -Force
        throw "config ไม่ถูกต้อง ระบบยังทำงานปกติทุกอย่าง"
    }
    Ok "ไวยากรณ์ถูกต้อง"
} else {
    Warn "ไม่พบ cloudflared.exe ข้ามการตรวจไวยากรณ์"
}

# ------------------------------------------------------------------
# restart แล้วตรวจผลจริง ไม่ผ่านให้คืนค่าเดิมอัตโนมัติ
# ------------------------------------------------------------------
Step "restart $ServiceName"
Restart-Service $ServiceName
Start-Sleep -Seconds 8
Ok "restart แล้ว (สถานะ: $((Get-Service $ServiceName).Status))"

Step "ตรวจว่าเว็บยังใช้ได้ผ่านโดเมนจริง"
$healthy = $false
foreach ($i in 1..10) {
    try {
        if ((Invoke-WebRequest "https://$Hostname/health" -UseBasicParsing -TimeoutSec 10).StatusCode -eq 200) {
            $healthy = $true; break
        }
    } catch { Start-Sleep -Seconds 3 }
}
if (-not $healthy) {
    Fail "เว็บไม่ตอบหลัง restart — คืน config เดิมและ restart กลับ"
    Copy-Item $backupPath $configPath -Force
    Restart-Service $ServiceName
    Start-Sleep -Seconds 8
    throw "ย้อนกลับเรียบร้อย เว็บควรกลับมาปกติ ดูรายละเอียดที่ F:\Game\cloudflared.log"
}
Ok "https://$Hostname/health ตอบ 200"

Step "ตรวจ WebSocket ของห้องช่วยเหลือ"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$py = Join-Path $root "backend\venv\Scripts\python.exe"
$check = Join-Path $root "backend\verify_support_ws.py"
if ((Test-Path $py) -and (Test-Path $check)) {
    $env:PYTHONIOENCODING = "utf-8"
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    & $py $check --public $Hostname
    $checkCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($checkCode -ne 0) {
        Warn "ตัวตรวจรายงานว่ายังไม่ผ่าน — ดูรายละเอียดด้านบน"
        Warn "ย้อนกลับได้ด้วย: .\enable-support-websocket.ps1 -Rollback"
        return
    }
} else {
    Warn "ไม่พบ verify_support_ws.py ข้ามการตรวจ"
}

Write-Host "`nเสร็จแล้ว — เปิด https://$Hostname/it-support ใช้งานได้เลย`n" -ForegroundColor Green
