#!/usr/bin/env bash
# =============================================================
#  uninstall.sh  —  Remove everything Jumper installed
#
#  Undoes every change made by install.sh:
#    1. Stops any running jumper.py process
#    2. Deletes the installed script from ~/Library/Application Scripts/
#    3. Deletes the Jumper Quick Action from ~/Library/Services/
#    4. Removes the Cmd+` keyboard shortcut from system preferences
#    5. Removes jumper.py from Login Items
#
#  Safe to run more than once — each step checks first and skips
#  gracefully if the thing it would remove is already gone.
#
#  Usage:  bash uninstall.sh
# =============================================================


# =============================================================
# OUTPUT HELPERS — same colour convention as install.sh
# =============================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✓${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
fail() { echo -e "  ${RED}✗${RESET}  $1"; }
step() { echo -e "\n${BOLD}$1${RESET}"; }


echo ""
echo "  ┌──────────────────────────────────────────────┐"
echo "  │    Jumper  —  Uninstaller (macOS)       │"
echo "  └──────────────────────────────────────────────┘"
echo ""


# =============================================================
# STEP 1 — Stop any running jumper.py process
#
# pgrep -f matches against the full command line, not just the
# process name, so it finds Python running jumper.py even
# if it was launched with a full path like /usr/bin/python3.
# =============================================================
step "Step 1 of 5 — Stopping any running Jumper process"

KILLED=0
while IFS= read -r pid; do
    if kill "$pid" 2>/dev/null; then
        KILLED=$((KILLED + 1))
    fi
done < <(pgrep -f "jumper\.py" 2>/dev/null || true)

if [ "$KILLED" -gt 0 ]; then
    ok "Stopped $KILLED running instance(s)"
else
    ok "Jumper was not running — nothing to stop"
fi


# =============================================================
# STEP 2 — Remove the installed script directory
#
# This is the permanent copy install.sh placed in Library.
# The original project folder you downloaded is NOT touched.
# =============================================================
step "Step 2 of 5 — Removing installed script"

INSTALL_DIR="$HOME/Library/Application Scripts/jumper"

if [ -d "$INSTALL_DIR" ]; then
    if rm -rf "$INSTALL_DIR" 2>/dev/null; then
        ok "Removed ~/Library/Application Scripts/jumper/"
    else
        fail "Could not remove $INSTALL_DIR"
        warn "Try removing it manually in Finder → ~/Library/Application Scripts/"
    fi
else
    ok "Script directory was not present — nothing to remove"
fi


# =============================================================
# STEP 3 — Remove the Automator Quick Action bundle
#
# macOS picks up Quick Actions from ~/Library/Services/.
# Deleting the bundle removes the entry from the Services menu.
# We also bounce the pbs daemon so the change takes effect
# immediately without needing a logout.
# =============================================================
step "Step 3 of 5 — Removing Quick Action from ~/Library/Services/"

WORKFLOW="$HOME/Library/Services/Jumper.workflow"

if [ -d "$WORKFLOW" ]; then
    if rm -rf "$WORKFLOW" 2>/dev/null; then
        ok "Removed Jumper.workflow"
        # Flushing pbs makes the Services menu refresh right away
        /System/Library/CoreServices/pbs -flush 2>/dev/null || true
        /usr/bin/killall pbs                2>/dev/null || true
        ok "Services menu refreshed"
    else
        fail "Could not remove $WORKFLOW"
        warn "Remove it manually in Finder: ~/Library/Services/"
    fi
else
    ok "Quick Action was not present — nothing to remove"
fi


# =============================================================
# STEP 4 — Remove the Cmd+` shortcut from pbs.plist
#
# install.sh wrote our shortcut into this file.  We read the
# plist, delete just our two keys, and write it back.  All
# other custom service shortcuts the user has set up are left
# completely untouched.
# =============================================================
step "Step 4 of 5 — Removing keyboard shortcut from preferences"

# Run a tiny Python script that edits pbs.plist safely.
# We capture stdout to decide which status line to print.
STEP4_MSG=$(python3 - 2>/dev/null <<'PYEOF'
import os, sys, plistlib

pbs_path = os.path.expanduser("~/Library/Preferences/pbs.plist")

# install.sh may have written either or both of these key variants
targets = [
    "(null) - Jumper - serviceViewer",   # macOS 13+
    "(null) - Jumper",                   # macOS 12 and earlier
]

try:
    with open(pbs_path, "rb") as f:
        data = plistlib.load(f)
except FileNotFoundError:
    print("not_present")
    sys.exit(0)
except Exception:
    print("unreadable")
    sys.exit(1)

status  = data.get("NSServicesStatus", {})
removed = [k for k in targets if k in status]

for k in removed:
    del status[k]

if not removed:
    print("not_present")
    sys.exit(0)

try:
    with open(pbs_path, "wb") as f:
        plistlib.dump(data, f)
    print("removed")
except Exception:
    print("write_failed")
    sys.exit(1)
PYEOF
)

case "$STEP4_MSG" in
    removed)
        ok "Keyboard shortcut removed from ~/Library/Preferences/pbs.plist"
        /usr/bin/killall pbs 2>/dev/null || true
        ;;
    not_present)
        ok "Keyboard shortcut was not registered — nothing to remove"
        ;;
    unreadable)
        fail "Could not read pbs.plist (file may be locked or corrupted)"
        warn "Remove manually: System Settings → Keyboard → Keyboard Shortcuts → Services"
        ;;
    write_failed)
        fail "Could not write to pbs.plist"
        warn "Remove manually: System Settings → Keyboard → Keyboard Shortcuts → Services"
        ;;
esac


# =============================================================
# STEP 5 — Remove jumper.py from Login Items
#
# Uses AppleScript (via osascript) to ask System Events to
# remove the entry by name.  The try/on error block ensures
# AppleScript never crashes even if the item was never added.
# =============================================================
step "Step 5 of 5 — Removing Login Item"

LOGIN_RESULT=$(osascript 2>/dev/null \
    -e 'tell application "System Events"' \
    -e '    try' \
    -e '        delete login item "jumper.py"' \
    -e '        return "removed"' \
    -e '    on error' \
    -e '        return "not_present"' \
    -e '    end try' \
    -e 'end tell')

case "$LOGIN_RESULT" in
    removed)
        ok "Removed from Login Items"
        ;;
    not_present)
        ok "Was not in Login Items — nothing to remove"
        ;;
    *)
        fail "Could not update Login Items automatically"
        warn "Remove manually: System Settings → General → Login Items"
        warn "Look for jumper.py and click the minus ( - ) button"
        ;;
esac


# =============================================================
# DONE
# =============================================================

echo ""
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │  Jumper has been completely removed.        │"
echo "  │  You can delete the project folder whenever      │"
echo "  │  you like — nothing else references it.          │"
echo "  └──────────────────────────────────────────────────┘"
echo ""
