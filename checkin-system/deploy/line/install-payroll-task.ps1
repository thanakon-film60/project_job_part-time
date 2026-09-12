# ===================================================================
# ตั้ง Scheduled Task ส่งสรุปรอบเงินเดือนเข้า LINE
#
# ตั้ง task เดียวแต่มี 2 trigger ต่อวัน (เช้า + เย็น) แล้วให้สคริปต์เป็นคน
# ตัดสินเองว่าวันนี้ควรส่งอะไร — ไม่ต้องตั้ง task แยกตามวันที่ 26/27/28
#   เช้า  -> ข้อความ "เริ่มรอบใหม่" (27) และ "เงินเดือนออก" (28)
#   เย็น  -> ข้อความ "ตัดรอบ" (26) ซึ่งต้องรอให้ลงเวลาออกงานของวันนั้นครบก่อน
# ส่งซ้ำไม่ได้เพราะทุกใบถูกบันทึกไว้ในตาราง payroll_notices
#
# ต้องรัน PowerShell แบบ "Run as Administrator"
# วิธีใช้:
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\line
#     .\install-payroll-task.ps1
#     .\install-payroll-task.ps1 -MorningTime "08:30" -EveningTime "19:00"
#     .\install-payroll-task.ps1 -Uninstall
#
# ทดสอบส่งทันทีโดยไม่ต้องรอ:
#     Start-ScheduledTask -TaskName ThanakonPayrollNotice
# ===================================================================
[CmdletBinding()]
param(
    [string]$MorningTime = "09:00",
    [string]$EveningTime = "18:00",
    [string]$TaskName    = "ThanakonPayrollNotice",
    [string]$BackendDir  = "",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($BackendDir)) {
    $BackendDir = (Resolve-Path (Join-Path $here "..\..\backend")).Path
}

function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "ต้องรัน PowerShell แบบ Run as Administrator" }

if ($Uninstall) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Ok "ลบ task '$TaskName' แล้ว"
    } else {
        Warn "ไม่พบ task '$TaskName' อยู่แล้ว"
    }
    exit 0
}

$python = Join-Path $BackendDir "venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    throw "ไม่พบ venv ที่ $python — รัน deploy\windows-server\install-backend-task.ps1 ก่อน"
}

$script = Join-Path $BackendDir "send_payroll_notice.py"
if (-not (Test-Path $script)) {
    throw "ไม่พบ $script — ดึงโค้ดใหม่ให้ครบก่อน (git pull)"
}

# --- เตือนเรื่องความเป็นส่วนตัวก่อนตั้ง task ---
# เงินเดือนไม่ควรเข้ากลุ่มที่มีคนอื่นอยู่ ถ้าไม่ได้ตั้งห้องแยกไว้ต้องรู้ตัวก่อน
$envFile = Join-Path $BackendDir ".env"
if (Test-Path $envFile) {
    $envText = Get-Content $envFile -Raw -Encoding UTF8
    if ($envText -notmatch '(?m)^\s*PAYROLL_LINE_TARGET_ID\s*=\s*\S') {
        Warn "ยังไม่ได้ตั้ง PAYROLL_LINE_TARGET_ID ใน .env"
        Warn "ข้อความเงินเดือนจะถูกส่งเข้าห้องเดียวกับแจ้งเตือนเข้างาน (LINE_TARGET_ID)"
        Warn "ถ้าห้องนั้นมีคนอื่นอยู่ ให้ตั้งเป็นแชทส่วนตัวก่อน แล้วรันสคริปต์นี้ใหม่"
    }
    if ($envText -notmatch '(?m)^\s*PAYROLL_DEFAULT_SALARY\s*=\s*[1-9]') {
        Warn "ยังไม่ได้ตั้ง PAYROLL_DEFAULT_SALARY — ต้องตั้งเงินเดือนรายคนที่ employees.base_salary"
    }
}

Write-Host "`n==> ตั้ง Scheduled Task '$TaskName' (ทุกวัน $MorningTime และ $EveningTime)" -ForegroundColor Cyan

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Warn "ลบ task เดิมออกก่อน"
}

$action = New-ScheduledTaskAction -Execute $python `
    -Argument "send_payroll_notice.py" -WorkingDirectory $BackendDir

# trigger สองเวลาในหนึ่ง task — StartWhenAvailable ทำให้เครื่องที่ปิดอยู่ตอนถึงเวลา
# ได้รันตอนเปิดกลับมา และสคริปต์ยังมีหน้าต่างตามหลัง (PAYROLL_NOTICE_CATCHUP_HOURS)
# กันข้อความตกรอบอีกชั้น
$triggers = @(
    (New-ScheduledTaskTrigger -Daily -At $MorningTime),
    (New-ScheduledTaskTrigger -Daily -At $EveningTime)
)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
    -Principal $principal -Settings $settings `
    -Description "ส่งสรุปรอบเงินเดือน (ตัดรอบ/เริ่มรอบใหม่/เงินเดือนออก) เข้า LINE" | Out-Null
Ok "ตั้ง task แล้ว — จะตรวจทุกวันเวลา $MorningTime และ $EveningTime"

Write-Host "`n==> ตรวจสถานะรอบปัจจุบัน (ไม่ส่งอะไร)" -ForegroundColor Cyan
$env:PYTHONIOENCODING = "utf-8"
Push-Location $BackendDir
try { & $python send_payroll_notice.py --status } finally { Pop-Location }

Write-Host "`nคำสั่งที่ใช้บ่อย:" -ForegroundColor Green
Write-Host "  ดูสถานะรอบ   : .\venv\Scripts\python.exe send_payroll_notice.py --status"
Write-Host "  ดูข้อความก่อนส่ง: .\venv\Scripts\python.exe send_payroll_notice.py --kind cutoff --force --dry-run"
Write-Host "  สั่งตรวจ/ส่งเลย : Start-ScheduledTask -TaskName $TaskName"
Write-Host "  ดูผลรันล่าสุด  : Get-ScheduledTaskInfo -TaskName $TaskName"
Write-Host "  ยกเลิก        : .\install-payroll-task.ps1 -Uninstall"
