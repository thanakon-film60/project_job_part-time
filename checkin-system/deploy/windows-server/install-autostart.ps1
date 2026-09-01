# Install all production components and configure them to start with Windows.
# Run from an elevated Windows PowerShell prompt.
[CmdletBinding()]
param(
    [switch]$SkipIis,
    [switch]$SkipTunnel,
    # Skip the logon task that reopens the control panel window on every boot.
    [switch]$SkipGui
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    throw "Run PowerShell as Administrator, then run this installer again."
}

$deployDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$windowsDir = Join-Path $deployDir "windows-server"

function Step([string]$message) {
    Write-Host "`n==> $message" -ForegroundColor Cyan
}

if (-not $SkipIis) {
    Step "Install the IIS website (the IIS service starts automatically)"
    & (Join-Path $windowsDir "install-iis-site.ps1")
}

Step "Install FastAPI as an AtStartup Scheduled Task"
& (Join-Path $windowsDir "install-backend-task.ps1")

if (-not $SkipTunnel) {
    Step "Install Cloudflare Tunnel as an Automatic Windows service"
    & (Join-Path $deployDir "cloudflare\setup-tunnel.ps1") -InstallService
}

if (-not $SkipGui) {
    # The three components above already come up on their own at boot. This last
    # task reopens the control panel at logon so the operator can see that they
    # did, and restarts anything that failed to come up.
    Step "Install the control panel as an AtLogOn Scheduled Task"
    & (Join-Path $windowsDir "install-gui-autostart.ps1")
}

Step "Verify automatic startup"
$task = Get-ScheduledTask -TaskName "MardodiCheckinAPI" -ErrorAction SilentlyContinue
$iis = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
$tunnel = Get-Service -Name "cloudflared" -ErrorAction SilentlyContinue
$gui = Get-ScheduledTask -TaskName "ThanakonCheckinPanel" -ErrorAction SilentlyContinue

$result = @(
    [PSCustomObject]@{
        Component = "FastAPI backend"
        Startup   = if ($task) { "AtStartup" } else { "Not installed" }
        Status    = if ($task) { $task.State } else { "Missing" }
    }
    [PSCustomObject]@{
        Component = "IIS website"
        Startup   = if ($iis) { $iis.StartType } else { "Not installed" }
        Status    = if ($iis) { $iis.Status } else { "Missing" }
    }
    [PSCustomObject]@{
        Component = "Cloudflare Tunnel"
        Startup   = if ($tunnel) { $tunnel.StartType } else { "Not installed" }
        Status    = if ($tunnel) { $tunnel.Status } else { "Missing" }
    }
    [PSCustomObject]@{
        Component = "Control panel (GUI)"
        Startup   = if ($gui) { "AtLogOn" } else { "Not installed" }
        Status    = if ($gui) { $gui.State } else { "Missing" }
    }
)
$result | Format-Table -AutoSize

Write-Host "`nAutomatic startup installation completed." -ForegroundColor Green
