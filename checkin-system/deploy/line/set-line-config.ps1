# ===================================================================
# ใส่ค่า LINE ลง backend\.env แล้ว restart backend ให้อัตโนมัติ
#
# สคริปต์นี้จะ "ถาม" ให้คุณวางค่าเอง — ค่าที่วางจะไม่ถูกแสดงบนจอ
# และไม่ถูกส่งไปที่ไหนนอกจากไฟล์ .env บนเครื่องนี้
#
# ต้องรัน PowerShell แบบ "Run as Administrator" (เพราะต้อง restart service)
# วิธีใช้:
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\line
#     .\set-line-config.ps1
#
# ใส่ทีละค่าก็ได้ (เว้นว่างแล้วกด Enter = ไม่แก้ค่าเดิม)
# ===================================================================
[CmdletBinding()]
param(
    [string]$BackendDir = ""
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($BackendDir)) {
    $BackendDir = (Resolve-Path (Join-Path $here "..\..\backend")).Path
}
$envPath = Join-Path $BackendDir ".env"

function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Head($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

if (-not (Test-Path $envPath)) { throw "ไม่พบไฟล์ $envPath" }

# ---------- อ่านค่าเดิม ----------
$lines = [IO.File]::ReadAllLines($envPath, (New-Object Text.UTF8Encoding($false)))
$current = @{}
foreach ($l in $lines) {
    if ($l -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $current[$Matches[1]] = $Matches[2] }
}

function Mask([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return "(ยังไม่ได้ตั้ง)" }
    if ($v.Length -le 10) { return "***" }
    return $v.Substring(0, 6) + "..." + $v.Substring($v.Length - 4)
}

Write-Host ""
Write-Host "  ตั้งค่าแจ้งเตือน LINE" -ForegroundColor Cyan
Write-Host "  ---------------------------------------------"
Write-Host "  ค่าปัจจุบัน:"
Write-Host ("    Channel access token : " + (Mask $current["LINE_CHANNEL_ACCESS_TOKEN"]))
Write-Host ("    Channel secret       : " + (Mask $current["LINE_CHANNEL_SECRET"]))
Write-Host ("    Group ID             : " + $(if ($current["LINE_TARGET_ID"]) { $current["LINE_TARGET_ID"] } else { "(ยังไม่ได้ตั้ง)" }))
Write-Host ""
Write-Host "  เว้นว่างแล้วกด Enter = ไม่แก้ค่าเดิม" -ForegroundColor DarkGray
Write-Host ""

function AskSecret([string]$label, [string]$key) {
    $sec = Read-Host "  $label" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    if ([string]::IsNullOrWhiteSpace($plain)) { return $current[$key] }
    return $plain.Trim()
}

$token  = AskSecret "Channel access token (วางแล้วกด Enter)" "LINE_CHANNEL_ACCESS_TOKEN"
$secret = AskSecret "Channel secret" "LINE_CHANNEL_SECRET"

$groupIn = Read-Host "  Group ID (ขึ้นต้นด้วย C — ยังไม่มีก็เว้นว่างไว้ก่อน)"
$group = if ([string]::IsNullOrWhiteSpace($groupIn)) { $current["LINE_TARGET_ID"] } else { $groupIn.Trim() }

# ---------- เขียนกลับ ----------
Head "บันทึกลง .env"
Copy-Item $envPath "$envPath.bak" -Force

$wanted = [ordered]@{
    "LINE_NOTIFY_ENABLED"       = "true"
    "LINE_CHANNEL_ACCESS_TOKEN" = $token
    "LINE_CHANNEL_SECRET"       = $secret
    "LINE_TARGET_ID"            = $group
    "TIMEZONE_OFFSET_HOURS"     = $(if ($current["TIMEZONE_OFFSET_HOURS"]) { $current["TIMEZONE_OFFSET_HOURS"] } else { "7" })
}

$seen = @{}
$out = foreach ($l in $lines) {
    if ($l -match '^\s*([A-Z_]+)\s*=' -and $wanted.Contains($Matches[1])) {
        $k = $Matches[1]
        $seen[$k] = $true
        "$k=$($wanted[$k])"
    } else { $l }
}
foreach ($k in $wanted.Keys) {
    if (-not $seen.ContainsKey($k)) { $out = @($out) + "$k=$($wanted[$k])" }
}

# ต้องเป็น UTF-8 ไม่มี BOM ไม่งั้น pydantic อ่านคีย์บรรทัดแรกไม่เจอ
[IO.File]::WriteAllLines($envPath, $out, (New-Object Text.UTF8Encoding($false)))
Ok "เขียน .env แล้ว (สำรองของเดิมไว้ที่ .env.bak)"

# ---------- restart ----------
Head "restart backend"
Stop-ScheduledTask -TaskName MardodiCheckinAPI -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*--port 8001*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName MardodiCheckinAPI

$ready = $false
foreach ($i in 1..20) {
    Start-Sleep -Seconds 2
    try {
        Invoke-WebRequest "http://127.0.0.1:8001/health" -UseBasicParsing -TimeoutSec 5 | Out-Null
        $ready = $true; break
    } catch { }
}
if ($ready) { Ok "backend พร้อมแล้ว" } else { Warn "backend ยังไม่ตอบ" }

# ---------- สรุป ----------
Head "สถานะ"
if (-not $token)  { Warn "ยังไม่มี access token" }
if (-not $secret) { Warn "ยังไม่มี channel secret — webhook จะ verify ไม่ผ่าน" }
if (-not $group) {
    Warn "ยังไม่มี Group ID"
    Write-Host "       ขั้นต่อไป: เชิญบอทเข้ากลุ่ม แล้วบอทจะบอก Group ID ในกลุ่มเอง" -ForegroundColor DarkGray
    Write-Host "       (หรือพิมพ์คำว่า id ในกลุ่ม) จากนั้นรันสคริปต์นี้อีกครั้งแล้วใส่เฉพาะ Group ID" -ForegroundColor DarkGray
} else {
    Head "ยิงข้อความทดสอบเข้ากลุ่ม"
    Push-Location $BackendDir
    try {
        $env:PYTHONIOENCODING = "utf-8"
        & (Join-Path $BackendDir "venv\Scripts\python.exe") -c @"
from app.notify_line import push_text, is_configured
print('พร้อมส่ง' if is_configured() else 'ตั้งค่าไม่ครบ')
if is_configured():
    ok = push_text('🔔 ทดสอบการแจ้งเตือนจากระบบเช็คอิน MARDODI\nถ้าเห็นข้อความนี้ = ตั้งค่าเรียบร้อยแล้วครับ')
    print('ส่งสำเร็จ' if ok else 'ส่งไม่สำเร็จ - ตรวจ token / Group ID')
"@
    } finally { Pop-Location }
}

Write-Host ""
