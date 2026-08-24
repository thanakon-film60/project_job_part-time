# ============================================================================
#  build + deploy ระบบเช็คอิน ขึ้น production ในคลิกเดียว
#
#  ทำอะไรบ้าง:
#    1. อัปเดต config ของ Cloudflare Tunnel (F:\Game\config.yml) ให้เป็นเวอร์ชัน
#       ล่าสุดที่รวมทุกโดเมนไว้ไฟล์เดียว แล้วผูก DNS ของโดเมนที่ยังไม่เคยผูก
#    2. npm install + npm run build (React)
#    3. copy ไฟล์ที่ build แล้วขึ้น IIS (C:\inetpub\checkin)
#    4. restart backend (Scheduled Task) เพื่อโหลด API ตัวใหม่
#    5. ทดสอบผ่านโดเมนจริงว่าขึ้นถูกต้อง
#
#  ⚠️ ต้องรันแบบ Administrator — ใช้ BUILD_DEPLOY.bat จะยกสิทธิ์ให้เอง
# ============================================================================
[CmdletBinding()]
param(
    # build แอป Flutter เป็น APK ให้พนักงานโหลดจากหน้าเว็บด้วย (ต้องมี Flutter SDK)
    # ไม่ใส่ = ข้ามไป ใช้ APK ตัวเดิมที่วางไว้แล้ว (ไฟล์อยู่รอดข้าม deploy)
    [switch]$BuildApk,
    [string]$Cloudflared = "F:\Game\cloudflared-windows-amd64.exe",
    [string]$LiveConfig  = "F:\Game\config.yml",
    [string]$TunnelName  = "Film_Part-Time"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = 'Build + Deploy - ระบบเช็คอิน' } catch {}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function ErrMsg($msg) { Write-Host "    [X]  $msg" -ForegroundColor Red }

Clear-Host
Write-Host ''
Write-Host '  ╔════════════════════════════════════════════════════╗' -ForegroundColor Cyan
Write-Host '  ║   🚀  Build + Deploy — ระบบเช็คอิน THANAKON-ROOM     ║' -ForegroundColor Cyan
Write-Host '  ╚════════════════════════════════════════════════════╝' -ForegroundColor Cyan

# --- ต้องเป็น Administrator --------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    ErrMsg 'ต้องรันแบบ Administrator (ใช้ BUILD_DEPLOY.bat แล้วกด Yes)'
    Read-Host '  กด Enter เพื่อปิด' | Out-Null
    exit 1
}

# --- 1. sync tunnel config + ผูก DNS ที่ยังขาด -------------------------------
Step "อัปเดต config ของ Cloudflare Tunnel"
$repoConfig = Join-Path $here "deploy\cloudflare\config.yml"
if (-not (Test-Path $repoConfig)) {
    Warn "ไม่พบ $repoConfig — ข้ามขั้นตอนนี้"
}
elseif (-not (Test-Path $Cloudflared)) {
    Warn "ไม่พบ cloudflared ที่ $Cloudflared — ข้ามขั้นตอนนี้"
}
else {
    # เทียบก่อนว่าต่างจริงไหม จะได้ไม่ต้อง restart service โดยไม่จำเป็น
    $needsUpdate = $true
    if (Test-Path $LiveConfig) {
        $a = (Get-FileHash $repoConfig).Hash
        $b = (Get-FileHash $LiveConfig).Hash
        $needsUpdate = ($a -ne $b)
    }

    if ($needsUpdate) {
        Copy-Item $repoConfig $LiveConfig -Force
        Ok "copy config ไป $LiveConfig แล้ว"

        # ผูก DNS ให้ทุก hostname ใน config (ซ้ำได้ ไม่เสียหาย)
        $hostnames = Select-String -Path $repoConfig -Pattern '^\s*-\s*hostname:\s*(\S+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value }
        foreach ($h in $hostnames) {
            & $Cloudflared tunnel route dns $TunnelName $h *>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Ok "ผูก DNS $h" } else { Warn "$h — น่าจะผูกไว้อยู่แล้ว (ข้ามได้)" }
        }

        if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
            Restart-Service cloudflared -Force
            Ok "restart tunnel service แล้ว"
        }
        else {
            Warn "ไม่พบ service ชื่อ cloudflared — ถ้ายังไม่ได้ติดตั้ง ให้ใช้ deploy\cloudflare\setup-tunnel.ps1 -InstallService"
        }
    }
    else {
        Ok "config เป็นเวอร์ชันล่าสุดอยู่แล้ว ไม่ต้องแก้"
    }
}

# เตือนถ้ามี cloudflared ตัวอื่นรันอยู่นอก service (สาเหตุที่เว็บสลับไปมา)
$strayTunnels = Get-Process cloudflared* -ErrorAction SilentlyContinue
if ($strayTunnels -and $strayTunnels.Count -gt 1) {
    Warn "พบโปรเซส cloudflared $($strayTunnels.Count) ตัว — ถ้าเว็บสลับไปมาระหว่างสองระบบ ให้ปิดตัวที่ไม่ใช่ service ทิ้ง"
}

# --- 1b. build APK ของแอป Flutter (เฉพาะเมื่อสั่ง -BuildApk) ------------------
if ($BuildApk) {
    Step "build แอป Flutter เป็น APK"
    try {
        & (Join-Path $here "deploy\windows-server\build-flutter-apk.ps1")
        Ok "ได้ไฟล์ APK ใหม่แล้ว — หน้าแรกของพนักงานจะเห็นเวอร์ชันนี้"
    }
    catch {
        Warn "build APK ไม่สำเร็จ: $($_.Exception.Message)"
        Warn "deploy เว็บต่อไปตามปกติ — พนักงานยังโหลด APK ตัวเดิมได้อยู่"
    }
}

# --- 2-5. build + copy + restart + ทดสอบ -------------------------------------
Step "เริ่ม build และ deploy"
& (Join-Path $here "deploy\windows-server\deploy-update.ps1")

Write-Host ''
Write-Host '  ──────────────────────────────────────────────────────' -ForegroundColor DarkGray
Write-Host '   เสร็จแล้ว — เมนูใหม่ "แผนที่ติดตามพนักงาน" อยู่ใน sidebar' -ForegroundColor Green
Write-Host '   ของ Boss ที่  https://thanakronpart-time.com' -ForegroundColor Green
Write-Host '  ──────────────────────────────────────────────────────' -ForegroundColor DarkGray
Write-Host ''
Read-Host '  กด Enter เพื่อปิดหน้าต่างนี้' | Out-Null
