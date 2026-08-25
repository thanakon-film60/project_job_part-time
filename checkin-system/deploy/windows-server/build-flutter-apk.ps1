# ===================================================================
# build แอป Flutter เป็นไฟล์ APK แล้ววางให้เว็บแจกดาวน์โหลด
#
#   flutter create (ถ้ายังไม่มี android/)  ->  ใส่สิทธิ์ใน AndroidManifest
#   ->  สร้างไอคอนจากโลโก้เดียวกับเว็บ  ->  flutter build apk --release
#   ->  copy ไปที่ backend\storage\app\thanakon-checkin.apk
#
# พนักงานจะเห็นปุ่มดาวน์โหลดที่หน้าแรกของเว็บทันที (ไม่ต้อง deploy เว็บใหม่)
#
# ต้องมี Flutter SDK + Android SDK บนเครื่อง (flutter doctor ต้องผ่าน)
#
#   .\build-flutter-apk.ps1              # build ปกติ
#   .\build-flutter-apk.ps1 -Clean       # ลบ build เก่าก่อน (ใช้เมื่อไอคอนไม่เปลี่ยน)
# ===================================================================
[CmdletBinding()]
param(
    [switch]$Clean,
    # ชื่อที่ขึ้นใต้ไอคอนบนหน้าจอมือถือ
    [string]$AppLabel = "THANAKON-ROOM"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $here "..\..")).Path
$appDir = Join-Path $root "flutter_app"

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }

# flutter/dart เขียนคำเตือนลง stderr เป็นปกติ ซึ่ง $ErrorActionPreference="Stop"
# จะแปลงเป็น error แล้วหยุดสคริปต์ทั้งที่ยังไม่มีอะไรพัง — ตัดสินจาก exit code แทน
function Invoke-Native($exe, $arguments, $failMessage) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $exe @arguments } finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0) { throw $failMessage }
}

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue)
if (-not $flutter) {
    throw "ไม่พบคำสั่ง flutter — ติดตั้ง Flutter SDK แล้วเพิ่มลง PATH ก่อน (https://docs.flutter.dev/get-started/install/windows)"
}

Push-Location $appDir
try {
    # --- 1. สร้างโฟลเดอร์ android/ ถ้ายังไม่มี -------------------------------
    # android/ ไม่ได้ commit ลง git (อยู่ใน .gitignore) เพราะเป็นไฟล์ที่สร้างใหม่ได้
    if (-not (Test-Path (Join-Path $appDir "android"))) {
        Step "สร้างโปรเจ็กต์ Android (flutter create)"
        Invoke-Native "flutter" @("create", "--platforms=android", ".") "flutter create ล้มเหลว"
        Ok "สร้าง android/ แล้ว"
    }

    # --- 2. ใส่สิทธิ์ + ชื่อแอปลง AndroidManifest ----------------------------
    # ตรงกับที่เขียนไว้ใน flutter_app\PLATFORM_SETUP.md
    Step "ตั้งค่าสิทธิ์ใน AndroidManifest"
    $manifest = Join-Path $appDir "android\app\src\main\AndroidManifest.xml"
    if (Test-Path $manifest) {
        $xml = Get-Content $manifest -Raw

        $perms = @(
            "android.permission.INTERNET",
            "android.permission.CAMERA",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.ACCESS_BACKGROUND_LOCATION",
            "android.permission.FOREGROUND_SERVICE",
            "android.permission.FOREGROUND_SERVICE_LOCATION",
            "android.permission.POST_NOTIFICATIONS",
            # ติดตามตำแหน่งจนกว่าจะออกจากระบบ: กันโหมดประหยัดแบตฆ่า service ทิ้ง
            # และกลับมาส่งพิกัดต่อเองหลังเปิดเครื่อง
            "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
            "android.permission.RECEIVE_BOOT_COMPLETED"
        )
        $missing = $perms | Where-Object { $xml -notmatch [regex]::Escape($_) }
        if ($missing) {
            $block = ($missing | ForEach-Object { "    <uses-permission android:name=`"$_`"/>" }) -join "`r`n"
            $xml = $xml -replace "(?m)^(\s*)<application", "$block`r`n`$1<application"
            Ok "เพิ่มสิทธิ์ $($missing.Count) รายการ"
        }

        # service ของ flutter_background_service (ติดตามตำแหน่งตอนแอปอยู่เบื้องหลัง)
        if ($xml -notmatch "flutter_background_service\.BackgroundService") {
            $svc = @"
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="location"
            android:exported="false" />
"@
            $xml = $xml -replace "(?m)^(\s*)</application>", "$svc`r`n`$1</application>"
            Ok "เพิ่ม BackgroundService"
        }

        # ชื่อใต้ไอคอน (ค่าเริ่มต้นจาก flutter create คือชื่อโปรเจ็กต์ อ่านไม่รู้เรื่อง)
        $xml = $xml -replace 'android:label="[^"]*"', "android:label=`"$AppLabel`""

        Set-Content $manifest $xml -Encoding UTF8 -NoNewline
        Ok "AndroidManifest พร้อม"
    }
    else {
        Warn "ไม่พบ AndroidManifest.xml — ข้ามขั้นตอนนี้"
    }

    # --- 3. minSdk --------------------------------------------------------------
    # ML Kit + background service ต้องการอย่างน้อย API 23 ส่วน Flutter 3.38 ตั้ง
    # ค่าเริ่มต้น (flutter.minSdkVersion) ไว้ที่ 24 อยู่แล้ว จึงปักเป็นตัวเลขตรง ๆ
    # ให้ build ที่เครื่องไหนก็ได้ APK ที่รองรับรุ่นเดียวกัน
    #
    # แล้วอ่านค่าจริงกลับมาส่งให้ publish-apk.ps1 เขียนลง release.json — หน้าเว็บ
    # จะได้บอกพนักงานถูกว่าต้องใช้ Android รุ่นไหน (ของเดิม hardcode ว่า 6.0 ทั้งที่
    # ไฟล์จริงต้องการ 7.0 คนใช้เครื่องเก่าจะโหลดไปแล้วติดตั้งไม่ได้ งงว่าพังตรงไหน)
    $minSdk = 24
    foreach ($name in @("android\app\build.gradle.kts", "android\app\build.gradle")) {
        $gradle = Join-Path $appDir $name
        if (-not (Test-Path $gradle)) { continue }
        $g = Get-Content $gradle -Raw
        $before = $g
        $g = $g -replace "minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = $minSdk"
        $g = $g -replace "minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion $minSdk"
        if ($g -ne $before) {
            Set-Content $gradle $g -Encoding UTF8 -NoNewline
            Ok "ตั้ง minSdk = $minSdk ใน $name"
        }
        # เผื่อมีคนแก้เป็นเลขอื่นไว้เอง — ยึดค่าที่อยู่ในไฟล์จริง
        if ($g -match "minSdk(?:Version)?\s*=?\s*(\d+)") { $minSdk = [int]$Matches[1] }
    }

    if ($Clean) {
        Step "ลบ build เก่า"
        Invoke-Native "flutter" @("clean") "flutter clean ล้มเหลว"
        Ok "ลบแล้ว"
    }

    # --- 4. ดึงแพ็กเกจ + สร้างไอคอนจากโลโก้เดียวกับเว็บ ----------------------
    Step "flutter pub get"
    Invoke-Native "flutter" @("pub", "get") "flutter pub get ล้มเหลว"
    Ok "แพ็กเกจครบ"

    Step "สร้างไอคอนแอปจากโลโก้ของเว็บ"
    # ค่าที่ใช้อยู่ในหัวข้อ flutter_launcher_icons ของ pubspec.yaml
    # (assets\icon\app-icon.png = frontend\public\logo-checkin.png บนพื้นขาว)
    Invoke-Native "flutter" @("pub", "run", "flutter_launcher_icons") "สร้างไอคอนล้มเหลว"
    Ok "ไอคอนตรงกับเว็บแล้ว"

    # --- 5. build APK ---------------------------------------------------------
    Step "build APK (release) — ใช้เวลาสักครู่"
    Invoke-Native "flutter" @("build", "apk", "--release") "flutter build apk ล้มเหลว"

    $apk = Join-Path $appDir "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $apk)) { throw "build เสร็จแต่ไม่พบไฟล์ $apk" }
    Ok "build เสร็จ"
}
finally { Pop-Location }

# --- 6. วางไฟล์ให้ backend แจก ------------------------------------------------
# ใช้สคริปต์ตัวเดียวกับที่เครื่อง production ใช้ตอนรับ APK ที่ build มาจากที่อื่น
# (เขียน release.json + ตรวจไฟล์ ที่เดียว จะได้ไม่หลุดกันคนละแบบ)
& (Join-Path $here "publish-apk.ps1") -ApkPath $apk -MinSdk $minSdk
