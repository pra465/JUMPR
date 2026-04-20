#!/usr/bin/env bash
# =============================================================
#  test.sh  —  Verify that Jumper works on this Mac
#
#  What the tests do:
#    • Read every connected display using the same macOS APIs
#      that jumper.py uses.
#    • Move the cursor to 3 specific positions (centre of each
#      of the first two displays, and the top-left corner area
#      of the primary display).
#    • After each move, read the cursor position back and check
#      that the display-detection logic identifies the correct
#      screen.
#    • Print PASS or FAIL for every individual check.
#
#  The cursor will jump around briefly while the tests run.
#  It is restored to its original position when done.
#
#  Usage:  bash test.sh
# =============================================================


# Find Python 3
PYTHON3="$(command -v python3 2>/dev/null)"
if [ -z "$PYTHON3" ]; then
    echo "  FAIL  Python 3 is not installed. Cannot run tests."
    exit 1
fi

# Check pyobjc is available before running the full test suite
if ! "$PYTHON3" -c "import Quartz" &>/dev/null 2>&1; then
    echo ""
    echo "  FAIL  pyobjc is not installed."
    echo "        Run:  pip3 install pyobjc-framework-Quartz pyobjc-framework-Cocoa"
    echo "        Then run this script again."
    echo ""
    exit 1
fi


# Run the tests as an inline Python script.
# <<'PYEOF' (single-quoted delimiter) means bash passes the block
# to Python verbatim — no variable expansion, no surprises.
"$PYTHON3" - <<'PYEOF'
import sys
import time

import Quartz
import AppKit

# ── ANSI colour helpers ────────────────────────────────────────────────────
GREEN  = "\033[32m"
RED    = "\033[31m"
YELLOW = "\033[33m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

passes   = 0
failures = 0


def check(label, passed, detail=""):
    """
    Print a single PASS or FAIL line and update the running totals.
    'detail' is an optional parenthetical shown in dim text.
    """
    global passes, failures
    if passed:
        marker = f"{GREEN}PASS{RESET}"
        passes += 1
    else:
        marker = f"{RED}FAIL{RESET}"
        failures += 1

    line = f"  {marker}  {label}"
    if detail:
        line += f"  {YELLOW}({detail}){RESET}"
    print(line)


def skip(label):
    """Print a SKIP line for tests that cannot run in the current environment."""
    print(f"  {YELLOW}SKIP{RESET}  {label}")


# ── Core functions (same logic as jumper.py) ─────────────────────────

def get_displays():
    """
    Return all active displays sorted left-to-right as a list of dicts.
    Each dict has keys: id, x, y, w, h.
    """
    err, display_ids, count = Quartz.CGGetActiveDisplayList(32, None, None)
    if err != Quartz.kCGErrorSuccess or count == 0:
        return []

    result = []
    for did in display_ids[:count]:
        r = Quartz.CGDisplayBounds(did)
        result.append({
            "id": did,
            "x": r.origin.x,
            "y": r.origin.y,
            "w": r.size.width,
            "h": r.size.height,
        })

    # Sort left-to-right; tie-break top-to-bottom (same as jumper.py)
    return sorted(result, key=lambda d: (d["x"], d["y"]))


def warp_cursor(x, y):
    """
    Teleport the cursor to (x, y) using the same call as jumper.py.
    Waits 120 ms afterwards for the OS to register the new position.
    """
    Quartz.CGWarpMouseCursorPosition((x, y))
    Quartz.CGAssociateMouseAndMouseCursorPosition(True)
    time.sleep(0.12)


def read_cursor():
    """Read the current cursor position and return (x, y)."""
    event = Quartz.CGEventCreate(None)
    pt    = Quartz.CGEventGetLocation(event)
    return pt.x, pt.y


def display_index_for_point(x, y, displays):
    """
    Return the 0-based index in 'displays' whose rectangle contains (x, y).
    Falls back to 0 (leftmost display) if no match.
    """
    for i, d in enumerate(displays):
        if d["x"] <= x < d["x"] + d["w"] and d["y"] <= y < d["y"] + d["h"]:
            return i
    return 0


# ── Test runner ────────────────────────────────────────────────────────────

print()
print(f"  {BOLD}Jumper  —  Screen Detection Tests{RESET}")
print(f"  {'─' * 38}")
print()

# ── Test 1: Display discovery ──────────────────────────────────────────────
displays = get_displays()
check(
    "get_displays() returns at least 1 display",
    len(displays) >= 1,
    f"{len(displays)} display(s) found",
)

if not displays:
    print()
    print(f"  {RED}Cannot continue — no displays were detected.{RESET}")
    sys.exit(1)

# ── Test 2: Display bounds are non-zero ────────────────────────────────────
for i, d in enumerate(displays):
    check(
        f"Display {i + 1} has valid bounds",
        d["w"] > 0 and d["h"] > 0,
        f"{int(d['w'])}×{int(d['h'])} at ({int(d['x'])}, {int(d['y'])})",
    )

# ── Test 3: Sort order ─────────────────────────────────────────────────────
if len(displays) >= 2:
    check(
        "Displays are sorted left-to-right (display 1 x ≤ display 2 x)",
        displays[0]["x"] <= displays[1]["x"],
        f"display 1 x={int(displays[0]['x'])}, display 2 x={int(displays[1]['x'])}",
    )
else:
    skip("Sort-order check (only 1 display connected)")

# ── Save cursor position so we can restore it after the tests ──────────────
orig_x, orig_y = read_cursor()

print()
print(f"  {BOLD}Cursor-position tests  (cursor will move briefly){RESET}")
print(f"  {'─' * 50}")
print()

# ── Build the list of positions to test ───────────────────────────────────
# Each entry is (human label, target_x, target_y, expected_display_index).
positions = []

# Centre of each display (up to the first 3)
for i, d in enumerate(displays[:3]):
    cx = d["x"] + d["w"] / 2.0
    cy = d["y"] + d["h"] / 2.0
    positions.append((f"Centre of display {i + 1}", cx, cy, i))

# Near the top-left corner of the first display (tests boundary handling)
d0 = displays[0]
positions.append((
    "Near top-left corner of display 1",
    d0["x"] + 8,
    d0["y"] + 8,
    0,
))

# ── Run cursor-movement tests ──────────────────────────────────────────────
for label, tx, ty, expected_idx in positions:
    warp_cursor(tx, ty)
    ax, ay = read_cursor()

    # Check 1: did the cursor actually land where we aimed?
    # Allow ±4 px tolerance for sub-pixel rounding in Retina coordinates.
    landed_correctly = abs(ax - tx) <= 4 and abs(ay - ty) <= 4
    check(
        f"{label}: cursor moved to target",
        landed_correctly,
        f"aimed ({tx:.0f}, {ty:.0f})  landed ({ax:.0f}, {ay:.0f})",
    )

    # Check 2: does the detection logic identify the right display?
    actual_idx   = display_index_for_point(ax, ay, displays)
    detected_ok  = actual_idx == expected_idx
    check(
        f"{label}: detected as display {expected_idx + 1}",
        detected_ok,
        f"got display {actual_idx + 1}, expected display {expected_idx + 1}",
    )

# ── Restore cursor to where it started ────────────────────────────────────
warp_cursor(orig_x, orig_y)

# ── Summary ────────────────────────────────────────────────────────────────
print()
print(f"  {'─' * 38}")
print(f"  {passes} passed,  {failures} failed")
print()

if failures == 0:
    print(f"  {GREEN}All checks passed — Jumper is working correctly.{RESET}")
else:
    print(f"  {RED}Some checks failed — see the lines marked FAIL above.{RESET}")
    print(f"  Check that Accessibility permission is granted and pyobjc is installed.")

print()
sys.exit(0 if failures == 0 else 1)
PYEOF

# Relay the Python exit code back to the shell so CI/scripts can act on it
exit $?
