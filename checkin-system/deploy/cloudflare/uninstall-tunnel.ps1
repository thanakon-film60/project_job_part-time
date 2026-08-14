# ===================================================================
# ถอน Cloudflare Tunnel service ออกจากเครื่อง
# ต้องรัน PowerShell แบบ "Run as Administrator"
# ===================================================================
[CmdletBinding()]
param(
    [string]$Cloudflared = "F:\Game\cloudflared-windows-amd64.exe"
)

$ErrorActionPreference = "Continue"

if (Get-Service cloudflared -ErrorAction SilentlyContinue) {
    Write-Host "หยุด service..." -ForegroundColor Cyan
    Stop-Service cloudflared -Force -ErrorAction SilentlyContinue
    Write-Host "ถอน service..." -ForegroundColor Cyan
    & $Cloudflared service uninstall
} else {
    Write-Host "ไม่พบ service ชื่อ cloudflared" -ForegroundColor Yellow
}

Get-Process cloudflared* -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "เรียบร้อย — DNS record ใน Cloudflare ยังอยู่ (ลบเองได้ที่ dash.cloudflare.com > DNS)" -ForegroundColor Green
