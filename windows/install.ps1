#Requires -Version 3.0
<#
  install.ps1  —  Windows installer for Jumper

  What this script does, in plain English:
    1. Looks for AutoHotkey v2 in the usual locations.
       If it is not found, downloads and silently installs it.
    2. Copies jumper.ahk to a permanent home in AppData
       so the file survives if you move or delete this folder.
    3. Creates a shortcut in the Windows Startup folder so
       Jumper launches automatically every time you log in.
    4. Launches jumper.ahk right now — no reboot needed.

  How to run:
    Right-click install.ps1  ->  "Run with PowerShell"

  No administrator rights are required.
  If any step fails, a message is printed and the script continues.
#>


# ==============================================================================
# SECTION 1 — OUTPUT HELPERS
# These four functions are the only way this script prints to the screen.
# Each one uses a different colour so you can scan the output at a glance.
# ==============================================================================

# Print a green success line — used when a step finishes cleanly.
function Write-Ok($text) {
    Write-Host "  [OK]  $text" -ForegroundColor Green
}

# Print a yellow notice — used for non-fatal issues or extra information.
function Write-Note($text) {
    Write-Host " [NOTE] $text" -ForegroundColor Yellow
}

# Print a red failure line — used when a step could not be completed.
# The script always continues after calling this.
function Write-Fail($text) {
    Write-Host " [FAIL] $text" -ForegroundColor Red
}

# Print a bold white step header to visually separate each phase.
function Write-Step($text) {
    Write-Host ""
    Write-Host $text -ForegroundColor White
    Write-Host ("  " + "-" * ($text.Length - 2)) -ForegroundColor DarkGray
}


# ==============================================================================
# SECTION 2 — FIXED PATHS
# Every destination path used by this installer is defined here in one place
# so they are easy to change and impossible to mistype later.
# ==============================================================================

# Where this install.ps1 lives — jumper.ahk must be in the same folder.
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } `
              else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# The .ahk source file that sits next to this installer.
$SourceAhk = Join-Path $ScriptRoot "jumper.ahk"

# The permanent home for the installed script.
# %APPDATA% = C:\Users\YourName\AppData\Roaming  (never needs admin rights)
$InstallDir  = Join-Path $env:APPDATA "jumper"
$InstalledAhk = Join-Path $InstallDir "jumper.ahk"

# The Windows Startup folder — anything placed here launches at login.
$StartupFolder   = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$StartupShortcut = Join-Path $StartupFolder "Jumper.lnk"

# Temporary path for the AutoHotkey installer download.
$AhkInstallerPath = Join-Path $env:TEMP "ahk-v2-setup.exe"

# Where we will install AutoHotkey if it is not already present.
# LOCALAPPDATA = C:\Users\YourName\AppData\Local  (no admin rights needed)
$AhkUserInstallDir = Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey"

# The download URL for the AutoHotkey v2 installer.
$AhkDownloadUrl = "https://www.autohotkey.com/download/ahk-v2.exe"


# ==============================================================================
# SECTION 3 — AHK DISCOVERY HELPER
# Searches every known location where AutoHotkey v2 might live.
# Returns the full path to AutoHotkey64.exe, or $null if not found.
# ==============================================================================

function Find-AhkExe {
    # These are the standard locations AutoHotkey v2 uses after installation.
    # We check both the system-wide Program Files path and the per-user
    # AppData path so the function works whether or not admin was used.
    $candidates = @(
        # System-wide installs (need admin, but may already exist)
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
        # 32-bit Program Files on a 64-bit Windows
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey64.exe",
        # Per-user install performed by this script (no admin needed)
        "$AhkUserInstallDir\v2\AutoHotkey64.exe",
        "$AhkUserInstallDir\v2\AutoHotkey32.exe",
        # Older AHK v2 layout that puts the exe directly in the install root
        "$AhkUserInstallDir\AutoHotkey64.exe",
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    # Also check the registry — AHK writes its install directory there.
    foreach ($regPath in @("HKCU:\SOFTWARE\AutoHotkey", "HKLM:\SOFTWARE\AutoHotkey")) {
        try {
            $key = Get-ItemProperty -Path $regPath -ErrorAction Stop
            if ($key.InstallDir) {
                # Look for the v2 sub-folder first, then the root.
                foreach ($rel in @("v2\AutoHotkey64.exe", "AutoHotkey64.exe")) {
                    $full = Join-Path $key.InstallDir $rel
                    if (Test-Path $full) { return $full }
                }
            }
        } catch {
            # Registry key doesn't exist — skip silently.
        }
    }

    # Last resort: see if AHK is on the system PATH.
    $fromPath = Get-Command "AutoHotkey64.exe" -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }

    return $null   # AutoHotkey v2 was not found anywhere
}


# ==============================================================================
# BANNER
# ==============================================================================

Write-Host ""
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host "      Jumper  —  Windows Installer     " -ForegroundColor Cyan
Write-Host "  ==========================================" -ForegroundColor Cyan
Write-Host ""

# Enable TLS 1.2 for HTTPS downloads.
# Older Windows versions default to TLS 1.0, which many servers now reject.
[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor
    [Net.SecurityProtocolType]::Tls12

# Allow locally-written scripts to run (user scope only — no admin needed).
# This is what lets PowerShell execute .ps1 files at all on a default Windows install.
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
} catch {
    # Already set, or group policy prevents changes — either way, harmless.
}


# ==============================================================================
# STEP 1 — Find or install AutoHotkey v2
#
# AutoHotkey is the free runtime that reads jumper.ahk and turns it
# into a running program.  Without it, the .ahk file is just a text file.
#
# We search several known locations first.  Only if all of those fail do we
# download and install it.  The installer is run with /S (silent) so no
# setup wizard appears, and /D= points it at a user-writable folder so no
# administrator password prompt appears.
# ==============================================================================
Write-Step "Step 1 of 4 — Checking for AutoHotkey v2"

$AhkExe = Find-AhkExe

if ($AhkExe) {

    Write-Ok "AutoHotkey v2 is already installed"
    Write-Ok "Path: $AhkExe"

} else {

    Write-Note "AutoHotkey v2 was not found — downloading now (~10 MB)..."

    # ── Download ──────────────────────────────────────────────────────────────
    # Try Invoke-WebRequest first (PS 3+).  If that fails (e.g. older IE engine
    # not initialised), fall back to the .NET WebClient class, which works on
    # every version of Windows without any browser dependency.
    $downloaded = $false
    try {
        Invoke-WebRequest -Uri $AhkDownloadUrl `
                          -OutFile $AhkInstallerPath `
                          -UseBasicParsing `
                          -ErrorAction Stop
        $downloaded = $true
    } catch {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($AhkDownloadUrl, $AhkInstallerPath)
            $downloaded = $true
        } catch {
            Write-Fail "Download failed: $($_.Exception.Message)"
            Write-Note "Please install AutoHotkey v2 manually from  https://www.autohotkey.com"
            Write-Note "Then run this installer again."
        }
    }

    # ── Silent install ────────────────────────────────────────────────────────
    # /S          = silent mode (no wizard windows appear)
    # /D=<path>   = destination folder; must be the LAST argument for NSIS
    #               installers and must NOT be quoted.
    # Installing to LOCALAPPDATA\Programs means no UAC prompt is needed.
    if ($downloaded) {
        Write-Note "Installing AutoHotkey v2 silently..."
        try {
            $proc = Start-Process `
                        -FilePath  $AhkInstallerPath `
                        -ArgumentList "/S /D=$AhkUserInstallDir" `
                        -Wait -PassThru -ErrorAction Stop

            if ($proc.ExitCode -ne 0) {
                Write-Note "Installer exit code: $($proc.ExitCode) — trying system-wide install..."
                # If the user-level install silently failed, attempt without /D=
                # (this may show a UAC prompt but gives the best chance of success)
                Start-Process -FilePath $AhkInstallerPath -ArgumentList "/S" -Wait
            }
        } catch {
            Write-Fail "Could not run the installer: $($_.Exception.Message)"
        }

        # Remove the downloaded installer — it is no longer needed.
        try { Remove-Item $AhkInstallerPath -Force -ErrorAction SilentlyContinue } catch {}

        # Search again now that installation has run.
        $AhkExe = Find-AhkExe

        if ($AhkExe) {
            Write-Ok "AutoHotkey v2 installed successfully"
            Write-Ok "Path: $AhkExe"
        } else {
            Write-Fail "Could not locate AutoHotkey v2 after installation."
            Write-Note "Steps 3 and 4 will be skipped."
            Write-Note "After installing AutoHotkey manually, run this script again."
        }
    }
}


# ==============================================================================
# STEP 2 — Copy jumper.ahk to a permanent location in AppData
#
# We do not run the script directly from this installer folder because the
# user might move or delete it later.  Copying to AppData gives the script
# a stable home that survives those changes.
#
# %APPDATA%\jumper\  is the destination.  It is created if it does not
# already exist.  Running the installer twice just overwrites the file.
# ==============================================================================
Write-Step "Step 2 of 4 — Copying jumper.ahk to AppData"

$step2Ok = $false

if (-not (Test-Path $SourceAhk)) {

    Write-Fail "jumper.ahk not found at: $SourceAhk"
    Write-Note "Make sure jumper.ahk is in the same folder as install.ps1."

} else {

    try {
        # Create the destination folder if it does not already exist.
        # -Force means "do not complain if the folder is already there".
        New-Item -ItemType Directory -Force -Path $InstallDir -ErrorAction Stop |
            Out-Null   # swallow the directory-object output so it doesn't clutter the screen

        Copy-Item -Path $SourceAhk -Destination $InstalledAhk -Force -ErrorAction Stop

        $step2Ok = $true
        Write-Ok "Script copied to AppData\Roaming\jumper\"
        Write-Ok "Full path: $InstalledAhk"

    } catch {
        Write-Fail "Could not copy jumper.ahk: $($_.Exception.Message)"
        Write-Note "Check that you have write permission to $InstallDir"
    }
}


# ==============================================================================
# STEP 3 — Create a shortcut in the Windows Startup folder
#
# Windows reads the Startup folder when you log in and launches every
# shortcut it finds there.  By placing a shortcut to jumper.ahk here,
# Jumper will start automatically after every reboot without you having
# to do anything.
#
# The shortcut points to AutoHotkey64.exe with jumper.ahk as its
# argument, which is more reliable than pointing at the .ahk file directly
# (direct .ahk association is set by AHK's installer, but can be lost).
# ==============================================================================
Write-Step "Step 3 of 4 — Adding to Startup folder"

if (-not $step2Ok) {
    Write-Note "Skipping — jumper.ahk was not copied in Step 2."

} elseif (-not $AhkExe) {
    Write-Note "Skipping — AutoHotkey v2 path is unknown (Step 1 did not complete)."
    Write-Note "Once AutoHotkey is installed, create a shortcut manually:"
    Write-Note "  Target:  $AhkExe"
    Write-Note "  In:      $StartupFolder"

} else {

    try {
        # WScript.Shell is a built-in Windows COM object for creating shortcuts.
        # It has been available on every version of Windows since XP.
        $wsh = New-Object -ComObject WScript.Shell
        $sc  = $wsh.CreateShortcut($StartupShortcut)

        # TargetPath  = the program that actually runs (AutoHotkey itself)
        # Arguments   = what we pass to it (the path to our .ahk file, quoted
        #               because the path may contain spaces)
        $sc.TargetPath      = $AhkExe
        $sc.Arguments       = "`"$InstalledAhk`""
        $sc.WorkingDirectory = $InstallDir
        $sc.Description     = "Jumper — Ctrl+`` to jump between monitors"
        $sc.Save()

        Write-Ok "Startup shortcut created"
        Write-Ok "Jumper will launch automatically every time you sign in"
        Write-Ok "Shortcut: $StartupShortcut"

    } catch {
        Write-Fail "Could not create the Startup shortcut: $($_.Exception.Message)"
        Write-Note "To set it up manually, create a shortcut with:"
        Write-Note "  Target:    $AhkExe `"$InstalledAhk`""
        Write-Note "  Place it in: $StartupFolder"
    }
}


# ==============================================================================
# STEP 4 — Launch jumper.ahk right now
#
# The Startup shortcut only fires on the next login, so we launch the script
# immediately so you can test it without rebooting.
#
# The AHK script itself uses #SingleInstance Force, which means if an old
# copy is already running it will be replaced by this fresh launch — no
# duplicate instances.
# ==============================================================================
Write-Step "Step 4 of 4 — Launching Jumper"

if (-not $AhkExe) {
    Write-Note "Skipping — AutoHotkey v2 is not available."
    Write-Note "After installing AutoHotkey, double-click jumper.ahk to start."

} elseif (-not (Test-Path $InstalledAhk)) {
    Write-Note "Skipping — jumper.ahk was not installed (Step 2 failed)."

} else {

    try {
        Start-Process -FilePath $AhkExe -ArgumentList "`"$InstalledAhk`"" -ErrorAction Stop

        Write-Ok "Jumper is running!"
        Write-Ok "Look for the AutoHotkey icon ( H ) near the clock in your taskbar."
        Write-Ok "Right-click that icon to see options or to quit."

    } catch {
        Write-Fail "Could not launch Jumper: $($_.Exception.Message)"
        Write-Note "You can start it manually by double-clicking:"
        Write-Note "  $InstalledAhk"
    }
}


# ==============================================================================
# DONE
# ==============================================================================

Write-Host ""
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host "  All done! Press Ctrl+`` to jump between screens." -ForegroundColor Green
Write-Host "  =================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  How it works:" -ForegroundColor White
Write-Host "    Press Ctrl + `` (the backtick key, top-left of the keyboard)"
Write-Host "    Your cursor jumps to the centre of the next monitor."
Write-Host "    Keeps cycling left-to-right and wraps back to the first."
Write-Host ""
Write-Host "  To uninstall:" -ForegroundColor White
Write-Host "    1. Right-click the tray icon -> Exit"
Write-Host "    2. Delete the shortcut from your Startup folder:"
Write-Host "       $StartupShortcut"
Write-Host "    3. Delete the script folder:"
Write-Host "       $InstallDir"
Write-Host ""

# Keep the window open so the user can read the output.
# When run by double-click or "Run with PowerShell", the window would
# disappear instantly without this line.
Read-Host "  Press Enter to close this window"
