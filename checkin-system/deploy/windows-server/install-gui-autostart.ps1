# ===================================================================
# เปิด "แผงควบคุม" (GUI) เองทุกครั้งที่ล็อกอินเข้า Windows
# แล้วให้ GUI ตรวจและเปิด Production ให้อัตโนมัติ
#
# ทำไมต้องใช้ Scheduled Task แบบ AtLogOn (ไม่ใช้โฟลเดอร์ Startup):
#   GUI ต้องรันด้วยสิทธิ์ Administrator ถ้าวาง shortcut ไว้ในโฟลเดอร์
#   Startup ธรรมดา Windows จะเด้ง UAC ถามทุกครั้งที่เปิดเครื่อง
#   ส่วน Task ที่ตั้ง RunLevel = Highest จะรันเป็น admin มาตั้งแต่แรก
#   จึงไม่มีหน้าต่างถามให้กด
#
# ต้องรัน PowerShell แบบ "Run as Administrator"
# วิธีใช้:
#     .\install-gui-autostart.ps1
#     .\install-gui-autostart.ps1 -Uninstall
# ===================================================================
[CmdletBinding()]
param(
    [string]$TaskName = "ThanakonCheckinPanel",
    # ผู้ใช้ที่จะให้หน้าต่างเด้งขึ้นตอนล็อกอิน (ว่างไว้ = คนที่รันสคริปต์นี้)
    [string]$UserId = "",
    # หน่วงเวลาก่อนเปิด GUI เพื่อรอ IIS / Task ของ backend / cloudflared ตั้งตัวก่อน
    [int]$DelaySeconds = 25,
    # เปิด GUI เฉยๆ ไม่ต้องสั่งเปิด Production ให้
    [switch]$NoAutoStartProduction,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "ต้องรัน PowerShell แบบ Run as Administrator" }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- ถอนการติดตั้ง ----------
if ($Uninstall) {
    Step "ลบ Scheduled Task $TaskName"
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Ok "ลบแล้ว - หน้าต่างควบคุมจะไม่เปิดเองอีก"
    } else {
        Warn "ไม่พบ Task ชื่อนี้อยู่แล้ว"
    }
    exit 0
}

# ---------- ติดตั้ง ----------
$guiPath = Join-Path (Split-Path -Parent $here) "gui.ps1"
if (-not (Test-Path $guiPath)) { throw "ไม่พบไฟล์ GUI ที่ $guiPath" }
$guiPath = (Resolve-Path $guiPath).Path

if ([string]::IsNullOrWhiteSpace($UserId)) { $UserId = "$env:USERDOMAIN\$env:USERNAME" }
if ($DelaySeconds -lt 0) { $DelaySeconds = 0 }

Step "สร้าง Scheduled Task $TaskName (เปิดตอนล็อกอินของ $UserId)"

$psArgs = @(
    "-NoProfile"
    "-ExecutionPolicy", "Bypass"
    "-WindowStyle", "Hidden"
    "-File", "`"$guiPath`""
)
if (-not $NoAutoStartProduction) { $psArgs += "-AutoStart" }

$action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument ($psArgs -join " ") `
    -WorkingDirectory (Split-Path -Parent (Split-Path -Parent $here))

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
if ($DelaySeconds -gt 0) { $trigger.Delay = "PT${DelaySeconds}S" }

# LogonType = Interactive จำเป็นสำหรับงานที่มีหน้าต่าง ถ้าใช้ Password/S4U
# งานจะรันใน session ที่ไม่มีหน้าจอ แล้วผู้ใช้จะไม่เห็นหน้าต่างเลย
$principal = New-ScheduledTaskPrincipal `
    -UserId $UserId `
    -LogonType Interactive `
    -RunLevel Highest

# ExecutionTimeLimit = 0 เพราะแผงควบคุมเปิดค้างไว้ทั้งวัน
# ถ้าปล่อยค่าเริ่มต้น (3 วัน) Windows จะปิดหน้าต่างทิ้งเอง
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "เปิดแผงควบคุมระบบเช็คอิน THANAKON-ROOM และเปิด Production ให้อัตโนมัติเมื่อเข้าใช้งาน Windows" `
    -Force | Out-Null

Ok "ติดตั้งแล้ว"

# ---------- ตรวจผล ----------
Step "ตรวจสอบ"
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { throw "สร้าง Task ไม่สำเร็จ" }

$hasLogon = @($task.Triggers | Where-Object {
    $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger"
}).Count -gt 0

[PSCustomObject]@{
    Task          = $task.TaskName
    Trigger       = if ($hasLogon) { "AtLogOn (+${DelaySeconds}s)" } else { "ไม่พบ trigger ตอนล็อกอิน" }
    RunAs         = $task.Principal.UserId
    RunLevel      = $task.Principal.RunLevel
    State         = $task.State
    AutoStartProd = if ($NoAutoStartProduction) { "ไม่" } else { "ใช่" }
} | Format-List

Write-Host ""
Write-Host "ครั้งต่อไปที่เปิดเครื่องและล็อกอิน หน้าต่างแผงควบคุมจะเปิดขึ้นเอง" -ForegroundColor Green
if (-not $NoAutoStartProduction) {
    Write-Host "และจะสั่งเปิด IIS + FastAPI + Cloudflare Tunnel ให้อัตโนมัติ" -ForegroundColor Green
}
Write-Host "ทดลองเดี๋ยวนี้ได้ด้วย:  Start-ScheduledTask -TaskName $TaskName" -ForegroundColor DarkGray
