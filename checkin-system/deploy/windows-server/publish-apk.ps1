# ===================================================================
# วางไฟล์ APK ที่ build เสร็จแล้ว ลง storage ของ backend เพื่อให้เว็บแจกดาวน์โหลด
#
# ใช้ตอนไหน:
#   เครื่อง production ไม่มี Flutter/Android SDK (และไม่จำเป็นต้องมี) จึง build
#   ที่เครื่อง dev ด้วย build-flutter-apk.ps1 แล้ว copy ไฟล์ .apk มาที่เซิร์ฟเวอร์
#   จากนั้นรันสคริปต์นี้ครั้งเดียว ปุ่มดาวน์โหลดบนหน้าแรกจะขึ้นทันที
#
#   .\publish-apk.ps1 -ApkPath D:\thanakon-checkin.apk
#   .\publish-apk.ps1                       # ไม่ใส่ = ใช้ไฟล์ที่ flutter build ไว้ในเครื่องนี้
#   .\publish-apk.ps1 -ApkPath ... -Version 1.0.1
#   .\publish-apk.ps1 -Boss                 # แอปหัวหน้า (flutter_boss_app)
#
# หมายเหตุ:
#   * ไม่ต้อง restart backend — /app/info อ่านไฟล์จากดิสก์ใหม่ทุกครั้งที่มีคนเปิดหน้าเว็บ
#   * ไฟล์อยู่นอกโฟลเดอร์ IIS จึงไม่ถูกล้างทิ้งตอน deploy หน้าเว็บใหม่
#   * APK ไม่ได้ commit ลง git (อยู่ใน .gitignore) — ต้องส่งไฟล์มาทางนี้เท่านั้น
# ===================================================================
[CmdletBinding()]
param(
    # ไฟล์ .apk ที่จะเอาขึ้นเซิร์ฟเวอร์
    [string]$ApkPath,
    # เวอร์ชันที่จะโชว์บนเว็บ (ไม่ใส่ = อ่านจาก flutter_app\pubspec.yaml)
    [string]$Version,
    # API level ต่ำสุดที่ APK ตัวนี้รองรับ — build-flutter-apk.ps1 อ่านค่าจริงจาก
    # build.gradle มาส่งให้ ถ้ารันเองบนเซิร์ฟเวอร์ให้ใส่ตามที่ build มา
    [int]$MinSdk = 24,
    # ใส่สวิตช์นี้เมื่อเป็น APK ของ "แอปหัวหน้า" (flutter_boss_app)
    #
    # สองแอปคนละไฟล์ คนละ endpoint และห้ามทับกัน — หัวหน้าที่เผลอโหลด APK
    # ของพนักงานมาติดตั้งจะใช้งานไม่ได้ เพราะเป็นคนละ applicationId
    [switch]$Boss
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here "..\..")).Path
if ($Boss) {
    $appName  = "แอปหัวหน้า"
    $appDir   = Join-Path $root "flutter_boss_app"
    $outDir   = Join-Path $root "backend\storage\boss-app"
    $apkName  = "thanakon-boss.apk"
    $infoPath = "/boss-app/info"
    $dlPath   = "/boss-app/download"
    $audience = "หัวหน้า"
} else {
    $appName  = "แอปพนักงาน"
    $appDir   = Join-Path $root "flutter_app"
    $outDir   = Join-Path $root "backend\storage\app"
    $apkName  = "thanakon-checkin.apk"
    $infoPath = "/app/info"
    $dlPath   = "/app/download"
    $audience = "พนักงาน"
}

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }

# --- 1. หาไฟล์ต้นทาง ---------------------------------------------------------
if (-not $ApkPath) {
    $ApkPath = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
}
if (-not (Test-Path $ApkPath)) {
    throw @"
ไม่พบไฟล์ APK ที่ $ApkPath
  * เครื่องที่มี Flutter SDK: รัน .\build-flutter-apk.ps1 ก่อน
  * เครื่อง production: copy ไฟล์ .apk จากเครื่อง dev มาวางไว้ก่อน
    แล้วสั่ง .\publish-apk.ps1 -ApkPath <ที่วางไฟล์ไว้>
"@
}
$src = Get-Item $ApkPath

# กันเคสไฟล์เสีย/copy มาไม่ครบ (เช่นได้หน้า error ของเว็บมาแทนไฟล์จริง)
# APK คือไฟล์ zip จึงต้องขึ้นต้นด้วย "PK" — ถ้าไม่ใช่ พนักงานจะกดติดตั้งแล้วเด้ง
# "แอปยังไม่ได้ติดตั้ง" โดยไม่รู้สาเหตุ ตรวจตรงนี้ทีเดียวจบ
$head = New-Object byte[] 2
$stream = [System.IO.File]::OpenRead($src.FullName)
try { $read = $stream.Read($head, 0, 2) } finally { $stream.Dispose() }
if ($read -lt 2 -or $head[0] -ne 0x50 -or $head[1] -ne 0x4B) {
    throw "ไฟล์ $($src.FullName) ไม่ใช่ APK (ไม่ขึ้นต้นด้วย PK) — copy มาไม่ครบหรือได้ไฟล์ผิดตัว"
}

# --- 2. เวอร์ชัน -------------------------------------------------------------
if (-not $Version) {
    $pubspec = Join-Path $appDir "pubspec.yaml"
    if (Test-Path $pubspec) {
        $verLine = Select-String -Path $pubspec -Pattern '^version:\s*(\S+)' | Select-Object -First 1
        if ($verLine) { $Version = $verLine.Matches[0].Groups[1].Value }
    }
}

# --- 3. วางไฟล์ + เขียนข้อมูลเวอร์ชัน ----------------------------------------
Step "วาง APK ของ$appName ลง storage ของ backend"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory $outDir -Force | Out-Null }
$dest = Join-Path $outDir $apkName
Copy-Item $src.FullName $dest -Force

# เวลาที่ build จริง (เวลาแก้ไขไฟล์ต้นทาง) ไม่ใช่เวลาที่ copy ขึ้นเซิร์ฟเวอร์
#
# ต้องบังคับ InvariantCulture — เครื่องที่ตั้งภาษาไทยจะแปลง yyyy เป็นปี พ.ศ. (2569)
# แล้วฝั่งเว็บจะโชว์วันที่เพี้ยนไปห้าร้อยปี
$builtAt = $src.LastWriteTimeUtc.ToString(
    "yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)

# แปลง API level เป็นชื่อเวอร์ชัน Android ที่พนักงานอ่านรู้เรื่อง
$androidNames = @{
    21 = "5.0"; 22 = "5.1"; 23 = "6.0"; 24 = "7.0"; 25 = "7.1"; 26 = "8.0"
    27 = "8.1"; 28 = "9";   29 = "10";  30 = "11";  31 = "12";  32 = "12L"
    33 = "13";  34 = "14";  35 = "15";  36 = "16"
}
$minAndroid = if ($androidNames.ContainsKey($MinSdk)) {
    "$($androidNames[$MinSdk]) (API $MinSdk)"
} else {
    "API $MinSdk"
}

$json = @{
    version     = $Version
    built_at    = $builtAt
    min_android = $minAndroid
} | ConvertTo-Json

# เขียนเป็น UTF-8 ไม่มี BOM — Set-Content -Encoding UTF8 ของ PowerShell 5.1 ใส่ BOM
# ให้ ซึ่ง json.load() ฝั่ง Python อ่านไม่ผ่าน (เวอร์ชัน/วันที่จะหายไปจากหน้าเว็บ)
[System.IO.File]::WriteAllText(
    (Join-Path $outDir "release.json"), $json, (New-Object System.Text.UTF8Encoding($false)))

$sizeMb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
Ok "$($src.Name) -> $dest ($sizeMb MB, เวอร์ชัน $Version, ต้องใช้ Android $minAndroid)"

Write-Host ""
Write-Host "  เสร็จแล้ว — ส่งลิงก์นี้ให้$audience ได้เลย" -ForegroundColor Green
Write-Host "  ลิงก์ตรง : https://thanakronpart-time.com$dlPath" -ForegroundColor Green
Write-Host "  เช็กสถานะ: https://thanakronpart-time.com$infoPath" -ForegroundColor Green
if ($Boss) {
    Write-Host ""
    Write-Host "  หมายเหตุ: แอปหัวหน้าไม่มีระบบเตือนอัปเดตในตัว" -ForegroundColor Yellow
    Write-Host "  ต้องส่งลิงก์ให้หัวหน้าเอง ไม่งั้นจะใช้ตัวเก่าต่อไปโดยไม่รู้ตัว" -ForegroundColor Yellow
}
Write-Host ""
