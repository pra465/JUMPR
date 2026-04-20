#!/usr/bin/env bash
# =============================================================
#  install.sh  —  macOS installer for Jumper
#
#  What this script does, step by step:
#    1. Checks that Python 3 is installed and that the pyobjc
#       library is available; installs pyobjc via pip if not.
#    2. Copies jumper.py to a permanent home inside your
#       ~/Library folder so it is safe even if you move this
#       installer directory.
#    3. Builds an Automator Quick Action (.workflow bundle) that
#       calls jumper.py when triggered from any app.
#    4. Writes the Cmd+` keyboard shortcut into macOS's service
#       preferences file (pbs.plist) so the Quick Action fires
#       without opening any menu.
#    5. Adds jumper.py to your Login Items so it is
#       available after every reboot.
#
#  Usage:
#    Open Terminal, drag this file into the window, press Enter.
#    Each step prints a status line. If a step fails, the
#    script prints a friendly message and moves on.
# =============================================================


# =============================================================
# OUTPUT HELPERS
# Coloured tick / cross / warning symbols so the user can scan
# the output at a glance without reading every word.
# =============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail() { echo -e "  ${RED}✗${RESET}  $1"; }
head() { echo -e "\n${BOLD}$1${RESET}"; }


# =============================================================
# FIXED PATHS
# All destination paths are derived here so every step below
# can share them without repeating the same strings.
# =============================================================

# Where this install.sh lives (and where jumper.py sits next to it)
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PY="$INSTALLER_DIR/jumper.py"

# Permanent home for the installed script inside the user's Library
INSTALL_DIR="$HOME/Library/Application Scripts/jumper"
INSTALL_PY="$INSTALL_DIR/jumper.py"

# macOS reads *.workflow bundles from this folder to populate the Services menu
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW="$SERVICES_DIR/Jumper.workflow"


# =============================================================
# BANNER
# =============================================================

echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │       Jumper  —  Installer      │"
echo "  └──────────────────────────────────────┘"
echo ""


# =============================================================
# STEP 1 — Check Python 3 and install pyobjc if missing
#
# jumper.py uses two Apple frameworks (Quartz and AppKit)
# that are exposed to Python through a package called pyobjc.
# pyobjc ships pre-installed with Xcode's command-line tools,
# but we check anyway and install it via pip if it is absent.
# =============================================================
head "Step 1 of 5 — Checking Python 3 and pyobjc"

# Find the python3 binary, trying common locations in order.
PYTHON3="$(command -v python3 2>/dev/null)"
if [ -z "$PYTHON3" ]; then
    PYTHON3="$(command -v /usr/bin/python3 2>/dev/null)"
fi

if [ -z "$PYTHON3" ]; then
    fail "Python 3 is not installed on this Mac."
    fail "Download it from  https://www.python.org/downloads/  then run this script again."
    echo ""
    exit 1
fi

ok "Python 3 found  ($("$PYTHON3" --version 2>&1))"

# Check whether pyobjc's Quartz bindings are importable.
# If not, install the two pyobjc packages that jumper.py needs.
if "$PYTHON3" -c "import Quartz" &>/dev/null 2>&1; then
    ok "pyobjc is already installed"
else
    warn "pyobjc not found — installing now (may take up to a minute)..."
    if "$PYTHON3" -m pip install --quiet --upgrade \
            pyobjc-framework-Quartz \
            pyobjc-framework-Cocoa 2>/dev/null; then
        ok "pyobjc installed successfully"
    else
        fail "Could not install pyobjc automatically."
        warn "If the script doesn't work, install it yourself by running:"
        warn "  pip3 install pyobjc-framework-Quartz pyobjc-framework-Cocoa"
        # Not fatal — continue and let the user sort it out later
    fi
fi

# Make sure the source file is actually here before we try to copy it.
if [ ! -f "$SOURCE_PY" ]; then
    fail "jumper.py was not found next to install.sh."
    fail "Keep both files in the same folder and run install.sh again."
    echo ""
    exit 1
fi


# =============================================================
# STEP 2 — Copy jumper.py to ~/Library/Application Scripts
#
# We give the script a permanent home that survives if the user
# moves or deletes the original download folder.
# ~/Library/Application Scripts/ is the standard macOS location
# for helper scripts associated with a specific app or service.
# =============================================================
head "Step 2 of 5 — Installing jumper.py"

if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
    if cp "$SOURCE_PY" "$INSTALL_PY" 2>/dev/null \
       && chmod +x "$INSTALL_PY" 2>/dev/null; then
        ok "Script installed"
        ok "Location: ~/Library/Application Scripts/jumper/jumper.py"
    else
        fail "Could not copy jumper.py. Check that you have write permission to ~/Library."
    fi
else
    fail "Could not create the install directory. Check disk space and permissions."
fi


# =============================================================
# STEP 3 — Create an Automator Quick Action (.workflow bundle)
#
# A Quick Action is a special kind of workflow that macOS adds
# to the Services menu (available in every app via the menu bar
# or right-click).  It lives as a folder ending in .workflow
# inside ~/Library/Services/.
#
# The bundle contains two files:
#   Contents/Info.plist      — registers this as a macOS Service
#   Contents/document.wflow  — tells Automator what to run
#
# We build both files using Python's built-in plistlib module
# so the XML encoding is always correct.
# =============================================================
head "Step 3 of 5 — Creating Automator Quick Action"

mkdir -p "$SERVICES_DIR"

# Run a self-contained Python snippet that writes both plist files.
# <<'PYEOF' (note the single quotes) means bash will NOT expand
# any $variables or backticks inside — the block is Python-only.
"$PYTHON3" - <<'PYEOF'
import os, sys, uuid, plistlib

# ── Paths ──────────────────────────────────────────────────
home         = os.path.expanduser("~")
workflow_dir = os.path.join(home, "Library", "Services", "Jumper.workflow")
contents_dir = os.path.join(workflow_dir, "Contents")
install_py   = os.path.join(home, "Library", "Application Scripts",
                            "jumper", "jumper.py")

try:
    os.makedirs(contents_dir, exist_ok=True)
except Exception as e:
    print(f"cannot create workflow directory: {e}", file=sys.stderr)
    sys.exit(1)

# ── document.wflow ─────────────────────────────────────────
# This is the Automator workflow definition.  It contains one
# action: "Run Shell Script", configured to call jumper.py.
# The UUID is freshly generated so macOS treats this as unique.
action_uuid = str(uuid.uuid4()).upper()

document = {
    # Automator version metadata (macOS ignores values that are too new)
    "AMApplicationBuild":   "521",
    "AMApplicationVersion": "2.10",
    "AMDocumentVersion":    "2",

    # The list of actions in this workflow (just one: run a shell script)
    "actions": [
        {
            "action": {
                # What types of input this action will accept
                # (Optional = True means it is fine with no input at all)
                "AMAccepts": {
                    "Container": "List",
                    "Optional":  True,
                    "Types":     ["com.apple.cocoa.string"],
                },
                "AMActionVersion": "2.0.3",
                # What types of output this action produces (none, in our case)
                "AMProvides": {
                    "Container": "List",
                    "Types":     ["com.apple.cocoa.string"],
                },
                # Path to the Automator action bundle that handles shell scripts
                "ActionBundlePath":
                    "/System/Library/Automator/Run Shell Script.action",
                "ActionName": "Run Shell Script",

                # The actual settings passed to the "Run Shell Script" action
                "ActionParameters": {
                    # The shell command that runs when the shortcut is pressed
                    "COMMAND_STRING": f'/usr/bin/env python3 "{install_py}"',
                    # Tells Automator we are using bash (not the user's login shell)
                    "CheckedForUserDefaultShell": True,
                    # 0 = pass nothing as stdin; 1 = pass selected text
                    "inputMethod": 0,
                    "shell":       "/bin/bash",
                    "source":      "",
                },
                "BundleIdentifier": "com.apple.RunShellScript",
                "CFBundleVersion":  "2.0.3",
                "CanShowSelectedItemsWhenRun": False,
                "CanShowWhenRun":    True,
                "Category":         ["AMCategoryUtilities"],
                "Class Name":       "RunShellScriptAction",
                # Unique ID for this instance of the action
                "UUID":             action_uuid,
                "arguments":        {},
                "isViewVisible":    1,
            },
            "isViewVisible": 1,
        }
    ],
    "connectors": {},

    # workflowMetaData marks this as a "Service" (Quick Action) that
    # takes no input and produces no output, and is available everywhere.
    "workflowMetaData": {
        "serviceInputTypeIdentifier":  "com.apple.automator.no-input",
        "serviceOutputTypeIdentifier": "com.apple.automator.no-output",
        "serviceProcessesInput":       0,
        "workflowTypeIdentifier":      "com.apple.automator.servicesMenu",
    },
}

wflow_path = os.path.join(contents_dir, "document.wflow")
try:
    with open(wflow_path, "wb") as f:
        plistlib.dump(document, f)
except Exception as e:
    print(f"cannot write document.wflow: {e}", file=sys.stderr)
    sys.exit(1)

# ── Info.plist ─────────────────────────────────────────────
# This file tells macOS that the bundle is a Service.
# NSMenuItem.default is the name that appears in the Services menu.
# NSRequiredContext being empty means it works in every application.
info = {
    "NSServices": [
        {
            "NSMenuItem":       {"default": "Jumper"},
            "NSMessage":        "runWorkflowAsService",
            # Empty context dict = no restriction on which app is in front
            "NSRequiredContext": {},
            # Empty send/return arrays = takes no input, returns nothing
            "NSSendTypes":      [],
            "NSReturnTypes":    [],
        }
    ]
}

info_path = os.path.join(contents_dir, "Info.plist")
try:
    with open(info_path, "wb") as f:
        plistlib.dump(info, f)
except Exception as e:
    print(f"cannot write Info.plist: {e}", file=sys.stderr)
    sys.exit(1)

print("ok")
PYEOF

STEP3_EXIT=$?

if [ "$STEP3_EXIT" -eq 0 ]; then
    ok "Quick Action bundle created at ~/Library/Services/Jumper.workflow"

    # Tell the pbs (pasteboard services) daemon to rescan the Services
    # folder so the new Quick Action shows up immediately without a logout.
    # pbs auto-restarts after being killed, so this is safe.
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
    /usr/bin/killall pbs                2>/dev/null || true
    ok "Services menu refreshed"
else
    fail "Could not create the Quick Action bundle."
    warn "You can create one manually: open Automator → New Document → Quick Action"
    warn "Add a 'Run Shell Script' action, paste:  python3 \"$INSTALL_PY\""
    warn "Save it as  Jumper  in ~/Library/Services/"
fi


# =============================================================
# STEP 4 — Register Cmd+` as the keyboard shortcut
#
# macOS stores keyboard shortcuts for Services in a preferences
# file called pbs.plist.  We read the existing file, add our
# entry for the Jumper service, and write it back.
#
# The key_equivalent string uses single characters as modifiers:
#   @  =  Cmd     $  =  Shift     ^  =  Ctrl     ~  =  Option
# So "@`" means Cmd + backtick.
#
# Note: ~/Library/KeyBindings/DefaultKeyBinding.dict is a
# different file — it only handles text-editing bindings inside
# NSTextView, NOT Services shortcuts. pbs.plist is the right one.
# =============================================================
head "Step 4 of 5 — Registering keyboard shortcut  (Cmd + \`)"

"$PYTHON3" - <<'PYEOF'
import os, sys, plistlib

pbs_path = os.path.expanduser("~/Library/Preferences/pbs.plist")

# macOS uses these exact key patterns for Automator Quick Actions.
# We write both variants because the exact string macOS generates
# can differ slightly between OS versions.
service_keys = [
    "(null) - Jumper - serviceViewer",   # macOS 13+
    "(null) - Jumper",                   # macOS 12 and earlier
]

# The shortcut definition:
#   key_equivalent "@`"  =  Cmd + backtick
#   enabled_services_menu 1  =  show in the Services menu
#   enabled_context_menu  1  =  show in right-click context menus
shortcut_entry = {
    "enabled_context_menu": 1,
    "enabled_services_menu": 1,
    "key_equivalent": "@`",
    "presentation_modes": {
        "Context":  1,
        "Services": 1,
    },
}

# Read the existing pbs.plist if it exists, or start fresh.
try:
    with open(pbs_path, "rb") as f:
        data = plistlib.load(f)
except FileNotFoundError:
    data = {}
except Exception as e:
    # If the file is corrupt or unreadable, start from an empty dict.
    # The worst case is that other custom service shortcuts are lost,
    # but that is better than crashing the installer.
    data = {}

# Ensure the NSServicesStatus dictionary exists inside the plist.
if "NSServicesStatus" not in data:
    data["NSServicesStatus"] = {}

# Write our shortcut entry under both key variants.
for key in service_keys:
    data["NSServicesStatus"][key] = shortcut_entry

try:
    with open(pbs_path, "wb") as f:
        plistlib.dump(data, f)
    print("ok")
except Exception as e:
    print(f"cannot write pbs.plist: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

STEP4_EXIT=$?

if [ "$STEP4_EXIT" -eq 0 ]; then
    ok "Shortcut Cmd+\` written to ~/Library/Preferences/pbs.plist"

    # Bounce the pbs daemon again so the new shortcut is live immediately.
    /usr/bin/killall pbs 2>/dev/null || true
    ok "Keyboard shortcut is now active"
else
    fail "Could not register the keyboard shortcut automatically."
    warn "You can set it manually:"
    warn "  System Settings → Keyboard → Keyboard Shortcuts → Services"
    warn "  Find 'Jumper' and assign  Cmd + \`"
fi


# =============================================================
# STEP 5 — Add jumper.py to Login Items
#
# Login Items are programs or scripts macOS opens automatically
# every time you log in.  We use AppleScript (via the osascript
# command) to add our script to that list.
#
# What happens at login:
#   macOS opens jumper.py with Python, which performs one
#   cursor jump and exits.  This confirms the script still works
#   after a reboot and serves as a gentle reminder that it is
#   installed.
#
# You can remove it at any time:
#   System Settings → General → Login Items → remove jumper.py
# =============================================================
head "Step 5 of 5 — Adding to Login Items"

# Pass the install path into AppleScript using a separate -e line
# so the path string is correctly quoted even if it contains spaces.
osascript \
    -e "set scriptPath to \"$INSTALL_PY\"" \
    -e 'tell application "System Events"' \
    -e '    try' \
    -e '        -- Remove any old entry with the same name to avoid duplicates' \
    -e '        set existing_names to name of every login item' \
    -e '        repeat with item_name in existing_names' \
    -e '            if item_name as string is "jumper.py" then' \
    -e '                delete login item "jumper.py"' \
    -e '            end if' \
    -e '        end repeat' \
    -e '    end try' \
    -e '    -- Add the script as a hidden login item (hidden = no window pops up)' \
    -e '    make login item at end with properties {path:scriptPath, hidden:true, name:"jumper.py"}' \
    -e 'end tell' \
    2>/dev/null

STEP5_EXIT=$?

if [ "$STEP5_EXIT" -eq 0 ]; then
    ok "Added to Login Items — will run at every login"
else
    fail "Could not add to Login Items automatically."
    warn "You can add it manually:"
    warn "  System Settings → General → Login Items → click +"
    warn "  Navigate to:  ~/Library/Application Scripts/jumper/jumper.py"
fi


# =============================================================
# DONE
# =============================================================

echo ""
echo "  ┌────────────────────────────────────────────────────┐"
echo "  │                                                    │"
echo "  │   All done! Press Cmd+\` to jump between screens.   │"
echo "  │                                                    │"
echo "  │   If the shortcut doesn't respond right away:     │"
echo "  │     • Log out and back in, OR                     │"
echo "  │     • Open System Settings → Keyboard →           │"
echo "  │       Keyboard Shortcuts → Services               │"
echo "  │       and tick the checkbox next to Jumper    │"
echo "  │                                                    │"
echo "  └────────────────────────────────────────────────────┘"
echo ""
