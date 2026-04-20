[CmdletBinding()]
param(
    [Parameter()]
    [string]$TimeZoneId = (Get-TimeZone).Id,

    [Parameter()]
    [switch]$IsDualBootMachine,

    [Parameter()]
    [switch]$ShowProtectedOsFiles,

    [Parameter()]
    [switch]$ConfigureDockedLaptopBehavior,

    [Parameter()]
    [switch]$ExtendDisplays
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $found = winget list --exact --id $Id --accept-source-agreements 2>$null
    if ($LASTEXITCODE -eq 0 -and $found) {
        Write-Host "Already installed: $Id"
        return
    }

    winget install --exact --id $Id `
	--no-upgrade `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements
}

# =========================
# 0. Safety
# =========================
if (-not (Test-IsAdmin)) {
    Write-Error "Please run this script as Administrator."
    exit 1
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget not found. Ensure App Installer is installed."
    exit 1
}

# Validate timezone early
try {
    Get-TimeZone -Id $TimeZoneId -ErrorAction Stop | Out-Null
} catch {
    Write-Error "Invalid TimeZoneId '$TimeZoneId'. Try: Get-TimeZone -ListAvailable"
    exit 1
}

# =========================
# 1. File Explorer settings
# =========================
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "HideFileExt" -Value 0

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "Hidden" -Value 1

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "ShowSuperHidden" -Value ([int]$ShowProtectedOsFiles.IsPresent)

# =========================
# 2. Core Dev Tools
# =========================
Install-WingetPackage -Id "Microsoft.VisualStudioCode"
Install-WingetPackage -Id "Git.Git"
Install-WingetPackage -Id "OpenJS.NodeJS"
Install-WingetPackage -Id "pnpm.pnpm"
Install-WingetPackage -Id "Zen-Team.Zen-Browser"
Install-WingetPackage -Id "marlocarlo.psmux"

# =========================
# 3. Komorebi prerequisites + install
# NOTE: requires commercial licenses for using at work.
# =========================
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name 'LongPathsEnabled' -Value 1

Install-WingetPackage -Id "LGUG2Z.komorebi"
Install-WingetPackage -Id "AutoHotkey.AutoHotkey"


# =========================
# 4. Optional workflow prefs: docked laptop behavior, extend displays
# =========================

# TODO fix komorebi, preferably to be similar to Niri
#if ($DisableWindowsSnap) {
#    reg add "HKCU\Control Panel\Desktop" /v WindowArrangementActive /d 0 /f | Out-Null
#    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v SnapAssist /t REG_DWORD /d 0 /f | Out-Null
#    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v SnapAssistFlyout /t REG_DWORD /d 0 /f | Out-Null
#    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v SnapFill /t REG_DWORD /d 0 /f | Out-Null
#    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v JointResize /t REG_DWORD /d 0 /f | Out-Null
#}

if ($ConfigureDockedLaptopBehavior) {
    powercfg /setacvalueindex scheme_current sub_buttons lidaction 0
    powercfg /setdcvalueindex scheme_current sub_buttons lidaction 0
    powercfg /setactive scheme_current
}

if ($ExtendDisplays) {
    DisplaySwitch.exe /extend
}

# =========================
# 5. Timezone + optional dual boot RTC handling
# =========================
Set-TimeZone -Id $TimeZoneId

if ($IsDualBootMachine) {
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v DisableAutoDaylightTimeSet /t REG_DWORD /d 0 /f | Out-Null

    w32tm /config /manualpeerlist:"time.windows.com,0x8 time.google.com,0x8" /syncfromflags:manual /update
    net start w32time 2>$null | Out-Null
    w32tm /resync /rediscover
}


# Restart explorer once at end
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

Write-Host "=========== Setup complete! =================================="
Write-Host "TimeZoneId: $TimeZoneId"
Write-Host "Dual boot RTC fix applied: $($IsDualBootMachine.IsPresent)"
Write-Host "Restart your terminal, and reboot if you changed display/power/time settings."