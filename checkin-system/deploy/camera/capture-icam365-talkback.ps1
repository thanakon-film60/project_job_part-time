# จับแพ็กเก็ตช่วงกดพูดในแอป iCam365 เพื่อถอดโปรโตคอล talkback
#
# ต้องรัน PowerShell แบบ Run as Administrator เพราะ pktmon ต้องใช้สิทธิ์ driver
# สำคัญ: เครื่องที่รันสคริปต์ต้องอยู่บนทางผ่านของ traffic ระหว่างมือถือกับกล้อง
# เช่น ให้มือถือเกาะ Windows Mobile Hotspot ของเครื่องนี้ หรือใช้ router/switch port mirror

[CmdletBinding()]
param(
    [string]$CameraIp = "192.168.1.101",
    [int]$Seconds = 45,
    [string]$OutDir = (Join-Path $PSScriptRoot "captures"),
    [int]$MaxFileMb = 128
)

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "ต้องเปิด PowerShell แบบ Run as Administrator"
}

if ($Seconds -lt 10) {
    throw "Seconds ต้องไม่น้อยกว่า 10 เพื่อให้มีเวลาจับช่วงเริ่ม/พูด/หยุด"
}

$pktmon = Get-Command pktmon.exe -ErrorAction Stop
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$etl = Join-Path $OutDir "icam365-talkback-$stamp.etl"
$pcap = Join-Path $OutDir "icam365-talkback-$stamp.pcapng"

Step "เตรียมตัวจับแพ็กเก็ต"
Warn "สคริปต์จะล้าง pktmon filter เดิมชั่วคราว และตั้ง filter เฉพาะ IP กล้อง $CameraIp"
& $pktmon.Source stop 2>$null | Out-Null
& $pktmon.Source filter remove | Out-Null
& $pktmon.Source filter add "icam365-camera" -i $CameraIp | Out-Null
Ok "ตั้ง filter เฉพาะ traffic ที่มี $CameraIp เป็นต้นทางหรือปลายทาง"

Write-Host ""
Write-Host "ก่อนเริ่ม:" -ForegroundColor Yellow
Write-Host "  1. เปิดแอป iCam365 ไปที่หน้า live view ของกล้อง"
Write-Host "  2. อย่าเพิ่งกดปุ่มพูดจนกว่าสคริปต์ขึ้นว่า START TALKING"
Write-Host "  3. กดพูดค้างประมาณ 10 วินาที แล้วปล่อย จากนั้นรอจนจับครบเวลา"
Write-Host ""
Read-Host "พร้อมแล้วกด Enter เพื่อเริ่มจับ"

try {
    Step "เริ่มจับ $Seconds วินาที"
    & $pktmon.Source start --capture --comp nics --pkt-size 0 --file-name $etl --file-size $MaxFileMb | Out-Null
    Ok "START TALKING: กดปุ่มพูดใน iCam365 ได้เลย"

    for ($left = $Seconds; $left -gt 0; $left--) {
        Write-Progress `
            -Activity "กำลังจับ iCam365 talkback" `
            -Status "เหลือ $left วินาที" `
            -PercentComplete ((($Seconds - $left) / $Seconds) * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity "กำลังจับ iCam365 talkback" -Completed
} finally {
    Step "หยุดจับ"
    & $pktmon.Source stop | Out-Null
    & $pktmon.Source filter remove | Out-Null
}

Step "แปลงเป็น pcapng"
& $pktmon.Source etl2pcap $etl --out $pcap | Out-Null

Ok "ไฟล์ ETL:   $etl"
Ok "ไฟล์ PCAP:  $pcap"
Write-Host ""
Write-Host "ส่งไฟล์ .pcapng นี้ให้ทีมแอปวิเคราะห์ต่อ ห้ามแนบไฟล์ที่จับตอนใช้งานแอปอื่นปนมา" -ForegroundColor Yellow
