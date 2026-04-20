#Requires -Version 3.0
<#
  uninstall.ps1  —  Remove everything Jumper installed on Windows

  Undoes every change made by install.ps1:
    1. Stops any running jumper.ahk AutoHotkey process
    2. Deletes the installed script from %APPDATA%\jumper\
    3. Removes the Startup shortcut so it no longer auto-runs at login

  Safe to run more than once — each step checks first and skips
  gracefully if the thing it would remove is already gone.

  How to run:
    Right-click uninstall.ps1  ->  "Run with PowerShell"
  No administrator rights required.
#>


# ==============================================================================
# OUTPUT HELPERS — same style as install.ps1
# ==============================================================================

function Write-Ok($text)   { Write-Host "  [OK]  $text" -ForegroundColor Green }
function Write-Note($text) { Write-Host " [NOTE] $text" -ForegroundColor Yellow }
function Write-Fail($text) { Write-Host " [FAIL] $text" -ForegroundColor Red }
function Write-Step($text) {
    Write-Host ""
    Write-Host $text -ForegroundColor White
    Write-Host ("  " + ("-" * [Math]::Max(0, $text.Length - 2))) -ForegroundColor DarkGray
}


# ==============================================================================
# FIXED PATHS — must exactly match what install.ps1 created
# ==============================================================================

# The folder where install.ps1 copied the script
$InstallDir       = Join-Path $env:APPDATA "jumper"
$InstalledAhk     = Join-Path $InstallDir  "jumper.ahk"

# The Startup shortcut install.ps1 created
$StartupFolder    = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$StartupShortcut  = Join-Path $StartupFolder "Jumper.lnk"


# ==============================================================================
# BANNER
# ==============================================================================

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "     Jumper  —  Uninstaller (Windows)       " -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""


# ==============================================================================
# STEP 1 — Stop any running jumper.ahk process
#
# AutoHotkey does not show up with a distinctive process name (it is just
# AutoHotkey64.exe for every script), so we use WMI/CIM to read the full
# command line of each AutoHotkey process and look for "jumper" in it.
# This avoids killing any other AutoHotkey scripts the user might have running.
# ==============================================================================
Write-Step "Step 1 of 3 — Stopping running Jumper process"

try {
    $ahkProcs = Get-CimInstance Win32_Process `
                    -Filter "Name LIKE 'AutoHotkey%'" `
                    -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -like "*jumper*" }

    if ($ahkProcs) {
        $stopped = 0
        foreach ($proc in $ahkProcs) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                $stopped++
            } catch {
                Write-Note "Could not stop process $($proc.ProcessId): $($_.Exception.Message)"
            }
        }
        Write-Ok "Stopped $stopped running instance(s) of Jumper"
    } else {
        Write-Ok "Jumper was not running — nothing to stop"
    }

} catch {
    # WMI query failed — this can happen in restricted environments.
    # Offer the user a manual fallback and continue.
    Write-Note "Could not query running processes: $($_.Exception.Message)"
    Write-Note "If Jumper is still running, right-click its tray icon and choose Exit."
}


# ==============================================================================
# STEP 2 — Delete the installed script folder
#
# This removes the copy of jumper.ahk that install.ps1 placed in AppData.
# The original project folder you downloaded is NOT touched.
# ==============================================================================
Write-Step "Step 2 of 3 — Removing installed files from AppData"

if (Test-Path $InstallDir) {
    try {
        # -Recurse removes the folder and everything inside it.
        # -Force removes read-only files without prompting.
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
        Write-Ok "Removed $InstallDir"
    } catch {
        Write-Fail "Could not remove $InstallDir"
        Write-Note "Error: $($_.Exception.Message)"
        Write-Note "Close any program that might have the .ahk file open, then try again."
    }
} else {
    Write-Ok "Install folder was not present — nothing to remove"
}


# ==============================================================================
# STEP 3 — Remove the Startup folder shortcut
#
# Windows reads this folder at login and launches every shortcut it finds.
# Deleting Jumper.lnk stops Jumper from auto-starting at boot.
# ==============================================================================
Write-Step "Step 3 of 3 — Removing Startup shortcut"

if (Test-Path $StartupShortcut) {
    try {
        Remove-Item -Path $StartupShortcut -Force -ErrorAction Stop
        Write-Ok "Removed $StartupShortcut"
        Write-Ok "Jumper will no longer launch automatically at login"
    } catch {
        Write-Fail "Could not remove $StartupShortcut"
        Write-Note "Error: $($_.Exception.Message)"
        Write-Note "Delete it manually from:"
        Write-Note "  $StartupFolder"
    }
} else {
    Write-Ok "Startup shortcut was not present — nothing to remove"
}


# ==============================================================================
# DONE
# ==============================================================================

Write-Host ""
Write-Host "  ====================================================" -ForegroundColor Cyan
Write-Host "  Jumper has been completely removed." -ForegroundColor Green
Write-Host "  You can delete the project folder whenever you like." -ForegroundColor Green
Write-Host "  ====================================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "  Press Enter to close this window"
