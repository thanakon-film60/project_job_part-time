# ===================================================================
# ตั้ง Scheduled Task ส่งสรุปการเข้างานเข้ากลุ่ม LINE ทุกวัน
#
# ต้องรัน PowerShell แบบ "Run as Administrator"
# วิธีใช้:
#     cd F:\GitHub\project_job_part-time\checkin-system\deploy\line
#     .\install-daily-summary-task.ps1              # ส่งทุกวัน 18:00
#     .\install-daily-summary-task.ps1 -Time "17:30"
#
# ทดสอบส่งทันทีโดยไม่ต้องรอ:
#     Start-ScheduledTask -TaskName MardodiDailySummary
# ===================================================================
[CmdletBinding()]
param(
    [string]$Time     = "18:00",
    [string]$TaskName = "MardodiDailySummary",
    [string]$BackendDir = ""
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

$python = Join-Path $BackendDir "venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    throw "ไม่พบ venv ที่ $python — รัน deploy\windows-server\install-backend-task.ps1 ก่อน"
}

Write-Host "`n==> ตั้ง Scheduled Task '$TaskName' (ส่งทุกวันเวลา $Time)" -ForegroundColor Cyan

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Warn "ลบ task เดิมออกก่อน"
}

$action = New-ScheduledTaskAction -Execute $python `
    -Argument "send_daily_summary.py" -WorkingDirectory $BackendDir
$trigger = New-ScheduledTaskTrigger -Daily -At $Time
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description "ส่งสรุปการเข้างานประจำวันเข้ากลุ่ม LINE" | Out-Null
Ok "ตั้ง task แล้ว — จะส่งทุกวันเวลา $Time"

Write-Host "`n==> ทดสอบส่งทันที" -ForegroundColor Cyan
$env:PYTHONIOENCODING = "utf-8"
Push-Location $BackendDir
try { & $python send_daily_summary.py } finally { Pop-Location }

Write-Host "`nคำสั่งที่ใช้บ่อย:" -ForegroundColor Green
Write-Host "  ส่งทันที : Start-ScheduledTask -TaskName $TaskName"
Write-Host "  ดูสถานะ  : Get-ScheduledTaskInfo -TaskName $TaskName"
Write-Host "  ยกเลิก   : Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false"
