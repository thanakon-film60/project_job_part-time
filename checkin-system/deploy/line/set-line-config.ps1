# ===================================================================
# ใส่ค่า LINE ลง backend\.env แล้ว restart backend ให้อัตโนมัติ
#
# สคริปต์นี้จะ "ถาม" ให้คุณวางค่าเอง — ค่าที่วางจะไม่ถูกแสดงบนจอ
# และไม่ถูกส่งไปที่ไหนนอกจากไฟล์ .env บนเครื่องนี้
#
# หมายเหตุ: ข้อความบนจอเป็นภาษาอังกฤษทั้งหมด เพราะหน้าต่าง console
# ของ Windows ใช้ฟอนต์ที่ไม่มีตัวอักษรไทย (ภาษาไทยจะกลายเป็น ???)
#
# ต้องรัน PowerShell แบบ "Run as Administrator" (เพราะต้อง restart service)
# วิธีใช้: ดับเบิลคลิก ตั้งค่า-LINE.bat  หรือ
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

function Ok($m)   { Write-Host "  [OK] $m"   -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m"   -ForegroundColor Yellow }
function Head($m) { Write-Host "`n==> $m"    -ForegroundColor Cyan }

if (-not (Test-Path $envPath)) { throw "File not found: $envPath" }

# ---------- อ่านค่าเดิม ----------
$lines = [IO.File]::ReadAllLines($envPath, (New-Object Text.UTF8Encoding($false)))
$current = @{}
foreach ($l in $lines) {
    if ($l -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $current[$Matches[1]] = $Matches[2] }
}

function Mask([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return "(not set)" }
    if ($v.Length -le 10) { return "***" }
    return $v.Substring(0, 6) + "..." + $v.Substring($v.Length - 4)
}

Write-Host ""
Write-Host "  LINE notification setup" -ForegroundColor Cyan
Write-Host "  ------------------------------------------------"
Write-Host "  Current values:"
Write-Host ("    Channel access token : " + (Mask $current["LINE_CHANNEL_ACCESS_TOKEN"]))
Write-Host ("    Channel secret       : " + (Mask $current["LINE_CHANNEL_SECRET"]))
Write-Host ("    Group ID             : " + $(if ($current["LINE_TARGET_ID"]) { $current["LINE_TARGET_ID"] } else { "(not set)" }))
Write-Host ""
Write-Host "  Leave blank and press Enter = keep current value" -ForegroundColor DarkGray
Write-Host "  (Your input is hidden while typing/pasting)" -ForegroundColor DarkGray
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

$token  = AskSecret "Channel access token (paste, then Enter)" "LINE_CHANNEL_ACCESS_TOKEN"
$secret = AskSecret "Channel secret (paste, then Enter)      " "LINE_CHANNEL_SECRET"

Write-Host ""
Write-Host "  Group ID starts with C. Leave blank if you don't have it yet -" -ForegroundColor DarkGray
Write-Host "  invite the bot to your group and it will tell you the ID there." -ForegroundColor DarkGray
$groupIn = Read-Host "  Group ID"
$group = if ([string]::IsNullOrWhiteSpace($groupIn)) { $current["LINE_TARGET_ID"] } else { $groupIn.Trim() }

# ---------- เขียนกลับ ----------
Head "Saving to .env"
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
Ok "Saved (backup at .env.bak)"

# ---------- restart ----------
Head "Restarting backend"
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
if ($ready) { Ok "Backend is up" } else { Warn "Backend not responding yet" }

# ---------- สรุป ----------
Head "Status"
if (-not $token)  { Warn "No access token set" }
if (-not $secret) { Warn "No channel secret set - webhook verify will fail" }

if (-not $group) {
    Warn "No Group ID yet"
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "    1. Add the bot as a LINE friend  (ID: @436oifum)"
    Write-Host "    2. Invite the bot into your group"
    Write-Host "    3. The bot will post the Group ID in the group"
    Write-Host "       (or type  id  in the group to ask again)"
    Write-Host "    4. Run this script again and paste the Group ID"
} else {
    Head "Sending a test message to the group"
    Push-Location $BackendDir
    try {
        $env:PYTHONIOENCODING = "utf-8"
        & (Join-Path $BackendDir "venv\Scripts\python.exe") -c @"
from app.notify_line import push_text, is_configured
if not is_configured():
    print('  [!] Config incomplete')
else:
    ok = push_text('Test notification from THANAKON-ROOM check-in system.\nIf you can see this in the group, setup is complete.')
    print('  [OK] Sent' if ok else '  [!] Failed - check token / Group ID')
"@
    } finally { Pop-Location }
}

Write-Host ""
Write-Host "  Done. Press Enter to close." -ForegroundColor Green
