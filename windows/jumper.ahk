; jumper v1.0.0 — teleport your cursor between screens with one key
; =============================================================
;  jumper.ahk  —  Windows version  (AutoHotkey v2)
;
;  What this script does
;  ---------------------
;  Press Ctrl + ` (the backtick key, top-left of the keyboard)
;  and your mouse cursor jumps to the centre of the next monitor.
;  It cycles left-to-right through every connected screen and
;  wraps back to the first after the last one.
;
;  Everything runs silently in the background — no window ever
;  appears.  Look for the tray icon near the clock to know it
;  is running.  Right-click the tray icon to see options.
;
;  To start:  double-click this file.
;  To quit:   right-click the tray icon → Exit.
; =============================================================


; =============================================================
; REQUIRED DIRECTIVES
; These lines must come before anything else in the file.
; =============================================================

; Tell AutoHotkey this file is written in v2 syntax.
; If someone tries to run it with v1, they get a clear error.
#Requires AutoHotkey v2.0

; If this script is already running, bring the existing copy
; to the front instead of starting a second one.
#SingleInstance Force

; Keep the script alive forever, even when no hotkey is being
; held down.  Without this line, AHK would exit immediately.
Persistent


; =============================================================
; SECTION 1 — TRAY ICON SETUP
; Runs once when the script first loads.
; The tray icon near the clock is the only visible sign that
; Jumper is running.
; =============================================================

; Text that appears when the user hovers over the tray icon.
A_IconTip := "Jumper  •  Ctrl+`` to jump displays"

; Build a custom right-click menu from scratch.
; We delete the default AHK menu items first so the user only
; sees our two options, not a bunch of AHK-internal entries.
A_TrayMenu.Delete()                                   ; wipe default items
A_TrayMenu.Add("About Jumper", TrayAbout)        ; information item
A_TrayMenu.Add()                                      ; thin separator line
A_TrayMenu.Add("Exit", (*) => ExitApp())              ; quit option

; Double-clicking the tray icon opens the About box.
A_TrayMenu.Default := "About Jumper"


; =============================================================
; SECTION 2 — THE HOTKEY
; Ctrl + `` (backtick).
; In AHK v2:  ^  = Ctrl,  `` `` = the backtick key itself.
; =============================================================

^``::
{
    ; ----------------------------------------------------------
    ; Step 1 — Read every connected monitor right now.
    ; We do this on every single keypress so that plugging in
    ; or unplugging a monitor is automatically detected with no
    ; restart needed.
    ; ----------------------------------------------------------
    monitors := GatherAllMonitors()

    ; ----------------------------------------------------------
    ; Step 2 — If there is only one monitor, do nothing and
    ; return immediately.  No sound, no tooltip, no fuss.
    ; ----------------------------------------------------------
    if monitors.Length < 2
        return

    ; ----------------------------------------------------------
    ; Step 3 — Sort monitors left-to-right.
    ; Windows can return monitor IDs in any order internally.
    ; Sorting by the left edge makes "next monitor" always mean
    ; "the one to the right", which feels natural to the user.
    ; ----------------------------------------------------------
    monitors := SortMonitorsByLeft(monitors)

    ; ----------------------------------------------------------
    ; Step 4 — Find which monitor the cursor is on right now.
    ; ----------------------------------------------------------
    MouseGetPos(&cursorX, &cursorY)
    currentIdx := FindMonitorUnderPoint(cursorX, cursorY, monitors)

    ; ----------------------------------------------------------
    ; Step 5 — Calculate the index of the next monitor.
    ; Mod() gives us the remainder after division, which makes
    ; the list wrap: after the last monitor, index goes back to 0,
    ; and we add 1 because AHK arrays are 1-based.
    ; ----------------------------------------------------------
    nextIdx := Mod(currentIdx, monitors.Length) + 1
    target  := monitors[nextIdx]

    ; ----------------------------------------------------------
    ; Step 6 — Move the cursor to the exact centre of the
    ; next monitor.  Speed 0 means instant — no sliding animation.
    ; ----------------------------------------------------------
    centerX := (target.left + target.right)  // 2
    centerY := (target.top  + target.bottom) // 2
    MouseMove centerX, centerY, 0

    ; ----------------------------------------------------------
    ; Step 7 — Play a soft Windows system sound.
    ; "*64" is the "Asterisk / Information" chime — the same
    ; gentle two-note sound Windows plays for info notifications.
    ; It is short, quiet, and not alarming.
    ; ----------------------------------------------------------
    SoundPlay "*64"

    ; ----------------------------------------------------------
    ; Step 8 — Show a tooltip near the cursor for 800 ms.
    ; The label says which screen number the user just landed on,
    ; counting from 1 (leftmost) so it matches what they see.
    ; Offset 24 px right and 40 px up so the tooltip does not
    ; sit directly under the arrow tip of the cursor.
    ; ----------------------------------------------------------
    label := "Jumped to screen " nextIdx
    ToolTip label, centerX + 24, centerY - 40

    ; SetTimer with a negative value fires exactly once after
    ; the given number of milliseconds, then stops.
    ; Calling ToolTip() with no arguments clears the tooltip.
    SetTimer () => ToolTip(), -800
}


; =============================================================
; SECTION 3 — MONITOR HELPER FUNCTIONS
; These functions are called from the hotkey block above.
; =============================================================

; -------------------------------------------------------------
; GatherAllMonitors()
;
; Ask Windows for the list of every display that is currently
; active (connected and powered on).  Returns an Array of
; objects, each describing one monitor with four coordinates:
;   .left   — x pixel of the left edge
;   .top    — y pixel of the top edge
;   .right  — x pixel of the right edge (exclusive)
;   .bottom — y pixel of the bottom edge (exclusive)
;
; Coordinates are in Windows virtual screen space, where (0, 0)
; is the top-left corner of the primary monitor and Y increases
; downward.  Monitors to the left of the primary can have
; negative .left values.
; -------------------------------------------------------------
GatherAllMonitors() {
    count    := MonitorGetCount()
    monitors := []

    loop count {
        ; MonitorGet fills four variables with the edges of monitor N.
        ; The & prefix means "put the result here" (pass by reference).
        MonitorGet(A_Index, &L, &T, &R, &B)
        monitors.Push({ id: A_Index, left: L, top: T, right: R, bottom: B })
    }

    return monitors
}


; -------------------------------------------------------------
; SortMonitorsByLeft(monitors)
;
; Sort a list of monitor objects so the one with the smallest
; left-edge coordinate comes first (leftmost screen = index 1).
;
; Uses bubble sort — perfectly fast for 2–8 monitors.
;
; Tiebreaker: if two monitors share the same left edge (e.g.
; one is directly above the other), the one with the smaller
; top value (higher on the desktop) comes first.
;
; Returns the same array re-ordered in place, and also as the
; return value so callers can write:  list := SortByLeft(list)
; -------------------------------------------------------------
SortMonitorsByLeft(monitors) {
    n := monitors.Length

    ; Outer loop: each pass guarantees the largest unsorted item
    ; has bubbled to its correct position at the end.
    loop n - 1 {
        ; Inner loop: compare adjacent pairs and swap if out of order.
        loop n - A_Index {
            j := A_Index
            a := monitors[j]
            b := monitors[j + 1]

            ; Decide whether these two neighbours need to be swapped.
            ; Primary sort key:   left edge (smaller = further left = comes first)
            ; Secondary sort key: top edge  (smaller = higher up = comes first)
            needSwap := (a.left > b.left)
                     || (a.left = b.left && a.top > b.top)

            if needSwap {
                monitors[j]     := b
                monitors[j + 1] := a
            }
        }
    }

    return monitors
}


; -------------------------------------------------------------
; FindMonitorUnderPoint(px, py, monitors)
;
; Check which monitor rectangle contains the point (px, py).
; Returns the 1-based index of the matching monitor in the array.
;
; The check is:
;   left <= px < right   AND   top <= py < bottom
;
; The right and bottom edges are exclusive (the pixel at x=right
; belongs to the next monitor, not this one) — this matches how
; Windows itself defines monitor boundaries.
;
; Falls back to index 1 (the leftmost monitor) if:
;   • The point falls in a gap between monitors.
;   • The cursor position could not be read.
;   • The monitors array is empty.
; -------------------------------------------------------------
FindMonitorUnderPoint(px, py, monitors) {
    for idx, mon in monitors {
        if px >= mon.left && px < mon.right
        && py >= mon.top  && py < mon.bottom
            return idx
    }
    return 1   ; safe default — use the leftmost monitor
}


; =============================================================
; SECTION 4 — TRAY MENU HANDLERS
; =============================================================

; -------------------------------------------------------------
; TrayAbout(*)
;
; Show a small popup that explains what Jumper does and
; lists the keyboard shortcut.  The asterisk (*) in the
; parameter list is required by AHK v2 for menu callbacks —
; it silently accepts the extra arguments AHK passes in.
; -------------------------------------------------------------
TrayAbout(*) {
    MsgBox(
        "Jumper`n"
        "──────────────────────────────`n`n"
        "Hotkey:   Ctrl + `` (backtick)`n`n"
        "Jumps the mouse cursor to the centre of the`n"
        "next monitor to the right.  Cycles through all`n"
        "connected displays and wraps back to the first.`n`n"
        "• Monitors are detected fresh on every keypress`n"
        "  so hot-plugging just works.`n`n"
        "• Right-click the tray icon to exit.",
        "About Jumper",
        "OK"
    )
}
