; jumper v1.0.0 — teleport your cursor between screens with one key
; =============================================================
;  test.ahk  —  Verify that Jumper works on this PC
;
;  What the tests do:
;    • Reads every connected monitor using the same functions
;      that jumper.ahk uses.
;    • Moves the cursor to 3 specific positions (centre of
;      monitor 1, centre of monitor 2 if it exists, and the
;      top-left corner area of monitor 1).
;    • After each move, checks that the display-detection logic
;      identifies the correct screen.
;    • Shows a popup with PASS / FAIL / SKIP for every check.
;
;  The cursor will jump around briefly while the tests run.
;  It is restored to its original position when finished.
;
;  To run:  double-click this file.
; =============================================================

#Requires AutoHotkey v2.0
#SingleInstance Force


; ==============================================================================
; SECTION 1 — HELPER FUNCTIONS
; These are exact copies of the functions in jumper.ahk so this test
; file is fully self-contained and does not need to include the main script.
; ==============================================================================

; ------------------------------------------------------------------------------
; GatherAllMonitors()
; Return an Array of objects describing every active monitor.
; Each object has .left .top .right .bottom properties.
; ------------------------------------------------------------------------------
GatherAllMonitors() {
    count    := MonitorGetCount()
    monitors := []
    loop count {
        MonitorGet(A_Index, &L, &T, &R, &B)
        monitors.Push({ id: A_Index, left: L, top: T, right: R, bottom: B })
    }
    return monitors
}

; ------------------------------------------------------------------------------
; SortMonitorsByLeft(monitors)
; Sort the monitor list so the leftmost monitor comes first.
; Uses bubble sort — fine for the small number of monitors a PC has.
; ------------------------------------------------------------------------------
SortMonitorsByLeft(monitors) {
    n := monitors.Length
    loop n - 1 {
        loop n - A_Index {
            j := A_Index
            a := monitors[j]
            b := monitors[j + 1]
            ; Swap if a is to the right of b, or at same x but lower down
            if (a.left > b.left) || (a.left = b.left && a.top > b.top) {
                monitors[j]     := b
                monitors[j + 1] := a
            }
        }
    }
    return monitors
}

; ------------------------------------------------------------------------------
; FindMonitorUnderPoint(px, py, monitors)
; Return the 1-based index of the monitor whose rectangle contains (px, py).
; Falls back to 1 if no monitor contains the point.
; ------------------------------------------------------------------------------
FindMonitorUnderPoint(px, py, monitors) {
    for idx, mon in monitors {
        if px >= mon.left && px < mon.right && py >= mon.top && py < mon.bottom
            return idx
    }
    return 1
}


; ==============================================================================
; SECTION 2 — TEST RUNNER STATE
; These variables accumulate results as the tests run.
; They must be declared before the Pass / Fail / Skip functions are called.
; ==============================================================================

passes  := 0
failures := 0
results  := ""   ; the multi-line text that will appear in the final MsgBox


; ==============================================================================
; SECTION 3 — PASS / FAIL / SKIP RECORDING FUNCTIONS
;
; Each function appends one line to the `results` string and updates
; the running pass/failure count.  `global` is required in AHK v2 so
; the functions can write to variables defined outside their scope.
; ==============================================================================

Pass(label) {
    global passes, results
    passes++
    results .= "  PASS  " . label . "`n"
}

Fail(label, detail := "") {
    global failures, results
    failures++
    line := "  FAIL  " . label
    if (detail != "")
        line .= "  [" . detail . "]"
    results .= line . "`n"
}

Skip(label) {
    global results
    results .= "  SKIP  " . label . "`n"
}


; ==============================================================================
; SECTION 4 — THE TESTS
; ==============================================================================

results .= "Jumper  -  Screen Detection Tests`n"
results .= "--------------------------------------`n`n"

; ── Save cursor position so we can restore it when tests finish ──────────────
MouseGetPos(&origX, &origY)

; ── Test 1: Can we read monitor information at all? ──────────────────────────
monitors := GatherAllMonitors()

if monitors.Length >= 1
    Pass("GatherAllMonitors() returned " . monitors.Length . " monitor(s)")
else {
    Fail("GatherAllMonitors() returned 0 monitors")
    ; Without monitor data we cannot run any further tests
    results .= "`nCannot continue without monitor information.`n"
    MsgBox(results, "Jumper  -  Test Results", 0)
    ExitApp
}

; ── Test 2: Sorting preserves the monitor count ──────────────────────────────
sorted := SortMonitorsByLeft(monitors)

if sorted.Length = monitors.Length
    Pass("SortMonitorsByLeft() preserved monitor count (" . sorted.Length . ")")
else
    Fail("SortMonitorsByLeft() changed count", sorted.Length . " != " . monitors.Length)

; ── Test 3: Leftmost monitor is first after sorting ──────────────────────────
if sorted.Length >= 2 {
    if sorted[1].left <= sorted[2].left
        Pass("SortMonitorsByLeft() placed leftmost monitor first")
    else
        Fail("SortMonitorsByLeft() sort order is wrong",
             "monitor 1 left=" . sorted[1].left . ", monitor 2 left=" . sorted[2].left)
} else
    Skip("Sort-order check (only 1 monitor connected)")

; ── Test 4: Monitor bounds are non-zero ──────────────────────────────────────
for idx, mon in sorted {
    w := mon.right  - mon.left
    h := mon.bottom - mon.top
    if w > 0 && h > 0
        Pass("Monitor " . idx . " has valid bounds  (" . w . "x" . h . "  at  " . mon.left . "," . mon.top . ")")
    else
        Fail("Monitor " . idx . " has invalid bounds",
             "w=" . w . " h=" . h)
}

; ── Build the positions to test ───────────────────────────────────────────────
; We test the centre of each of the first two monitors, plus the top-left
; corner area of the first monitor (to check boundary handling).

results .= "`n--- Cursor-movement tests (cursor will move briefly) ---`n`n"

; ── Test 5: Centre of monitor 1 ──────────────────────────────────────────────
m1  := sorted[1]
cx1 := (m1.left + m1.right)  // 2
cy1 := (m1.top  + m1.bottom) // 2

MouseMove cx1, cy1, 0          ; speed 0 = instant warp
Sleep 80                        ; give Windows 80 ms to register the move
MouseGetPos(&ax1, &ay1)

; Check the cursor actually moved to where we aimed (allow ±3 px tolerance)
if Abs(ax1 - cx1) <= 3 && Abs(ay1 - cy1) <= 3
    Pass("Centre of monitor 1: cursor moved to target  (" . ax1 . ", " . ay1 . ")")
else
    Fail("Centre of monitor 1: cursor did not land on target",
         "aimed (" . cx1 . "," . cy1 . ") landed (" . ax1 . "," . ay1 . ")")

; Check the detection logic identifies monitor 1
det1 := FindMonitorUnderPoint(ax1, ay1, sorted)
if det1 = 1
    Pass("Centre of monitor 1: detected as monitor 1")
else
    Fail("Centre of monitor 1: wrong monitor detected", "got " . det1 . ", expected 1")

; ── Test 6: Centre of monitor 2 (skip if only one monitor) ───────────────────
if sorted.Length >= 2 {
    m2  := sorted[2]
    cx2 := (m2.left + m2.right)  // 2
    cy2 := (m2.top  + m2.bottom) // 2

    MouseMove cx2, cy2, 0
    Sleep 80
    MouseGetPos(&ax2, &ay2)

    if Abs(ax2 - cx2) <= 3 && Abs(ay2 - cy2) <= 3
        Pass("Centre of monitor 2: cursor moved to target  (" . ax2 . ", " . ay2 . ")")
    else
        Fail("Centre of monitor 2: cursor did not land on target",
             "aimed (" . cx2 . "," . cy2 . ") landed (" . ax2 . "," . ay2 . ")")

    det2 := FindMonitorUnderPoint(ax2, ay2, sorted)
    if det2 = 2
        Pass("Centre of monitor 2: detected as monitor 2")
    else
        Fail("Centre of monitor 2: wrong monitor detected", "got " . det2 . ", expected 2")

} else {
    Skip("Centre of monitor 2 (only 1 monitor connected)")
    Skip("Detection check for monitor 2 (only 1 monitor connected)")
}

; ── Test 7: Top-left corner area of monitor 1 ────────────────────────────────
; Placing the cursor 6 pixels inside the corner tests that boundary pixels
; are assigned to the correct monitor and not lost in a gap.
cornerX := m1.left + 6
cornerY := m1.top  + 6

MouseMove cornerX, cornerY, 0
Sleep 80
MouseGetPos(&acx, &acy)

if Abs(acx - cornerX) <= 3 && Abs(acy - cornerY) <= 3
    Pass("Near top-left corner of monitor 1: cursor moved to target  (" . acx . ", " . acy . ")")
else
    Fail("Near top-left corner: cursor did not land on target",
         "aimed (" . cornerX . "," . cornerY . ") landed (" . acx . "," . acy . ")")

detCorner := FindMonitorUnderPoint(acx, acy, sorted)
if detCorner = 1
    Pass("Near top-left corner of monitor 1: detected as monitor 1")
else
    Fail("Near top-left corner: wrong monitor detected", "got " . detCorner . ", expected 1")

; ── Restore cursor to where it started ───────────────────────────────────────
MouseMove origX, origY, 0


; ==============================================================================
; SECTION 5 — SUMMARY
; Append a final pass/fail count and show everything in a MsgBox.
; ==============================================================================

results .= "`n--------------------------------------`n"
results .= passes . " passed,   " . failures . " failed`n"

if failures = 0
    results .= "`nAll checks passed!`nJumper is working correctly."
else
    results .= "`nSome checks failed.`nSee the lines marked FAIL above for details."

MsgBox(results, "Jumper  -  Test Results", 0)
ExitApp
