#!/usr/bin/env python3
# jumper v1.0.0 — teleport your cursor between screens with one key
"""
jumper.py  —  macOS edition
----------------------------------------------------------------------
Jumps the mouse cursor to the center of the next connected display.
Cycles left-to-right through all displays and wraps back to the first.

Designed to be called from a keyboard shortcut (Hammerspoon, Automator,
BetterTouchTool, etc.).  No Terminal window, no popups, no crashes.

Requires macOS 10.14+ and the pyobjc package, which ships pre-installed
on every modern Mac that has Xcode Command Line Tools.  Nothing else.
"""

import sys
import subprocess

# ---------------------------------------------------------------------------
# Import the two macOS frameworks we need.
# Quartz  — reads display geometry and moves the cursor at the hardware level.
# AppKit  — plays sounds and lets us draw a brief floating highlight ring.
#
# Both are part of pyobjc, which is bundled with macOS's own Python 3.
# If somehow they are missing, we exit without making any noise.
# ---------------------------------------------------------------------------
try:
    import Quartz
    import AppKit
except ImportError:
    sys.exit(0)


# ===========================================================================
# SECTION 1 — DISPLAY DISCOVERY
# Every function here reads the current hardware state at call time,
# so hot-plugging a monitor just works with no restart needed.
# ===========================================================================

def get_connected_displays():
    """
    Ask macOS for the full list of displays that are active right now.

    'Active' means connected, powered on, and not duplicating another
    display (i.e. not in mirror mode).  The list is re-read on every call
    so that plugging or unplugging a monitor is reflected immediately.

    Returns a plain Python list of integer display IDs.
    Returns an empty list if nothing can be read — all callers check length.
    """
    try:
        # CGGetActiveDisplayList takes: (max slots to fill, output array, output count)
        # pyobjc turns the two output arguments into extra return values.
        err, display_ids, count = Quartz.CGGetActiveDisplayList(32, None, None)
        if err == Quartz.kCGErrorSuccess and count > 0:
            return list(display_ids[:count])
    except Exception:
        pass

    # Fallback path: ask AppKit instead of Quartz.
    # NSScreen.screens() returns one object per display.
    # 'NSScreenNumber' inside deviceDescription() is the same integer ID.
    try:
        return [
            int(s.deviceDescription()['NSScreenNumber'])
            for s in AppKit.NSScreen.screens()
        ]
    except Exception:
        return []


def get_display_bounds(display_id):
    """
    Return the screen rectangle of a single display as a plain dict:
        { 'x', 'y', 'width', 'height' }

    All values are in Quartz global screen coordinates:
      • (0, 0) is the top-left corner of the primary (main) display.
      • Y increases downward.
      • Displays to the left of or above the primary have negative origins.

    This same coordinate system is used by CGWarpMouseCursorPosition and
    CGEventGetLocation, so no conversion is needed when comparing positions.

    Returns None if the display ID is not valid or an error occurs.
    """
    try:
        r = Quartz.CGDisplayBounds(display_id)
        return {
            'x':      r.origin.x,
            'y':      r.origin.y,
            'width':  r.size.width,
            'height': r.size.height,
        }
    except Exception:
        return None


def sort_displays_left_to_right(display_ids):
    """
    Re-order a list of display IDs so the leftmost display comes first.

    This makes 'jump to next display' always feel like moving to the right,
    regardless of the arbitrary order macOS returns IDs in.  When two
    displays share the same left edge (stacked vertically), the one with
    the smaller Y value (higher on screen) comes first.

    Returns a new sorted list without modifying the original.
    Falls back to the original order if sorting fails.
    """
    def sort_key(did):
        b = get_display_bounds(did)
        return (b['x'], b['y']) if b else (0, 0)

    try:
        return sorted(display_ids, key=sort_key)
    except Exception:
        return list(display_ids)


# ===========================================================================
# SECTION 2 — CURSOR POSITION
# ===========================================================================

def get_cursor_position():
    """
    Read the current mouse cursor position from the system.

    Creates a blank CGEvent just so we can call CGEventGetLocation on it —
    that function returns the current hardware cursor location regardless
    of what kind of event the object represents.

    Returns (x, y) as floats in Quartz screen coordinates, or None on error.
    """
    try:
        event = Quartz.CGEventCreate(None)
        pt = Quartz.CGEventGetLocation(event)
        return (pt.x, pt.y)
    except Exception:
        return None


def find_display_under_cursor(cursor_pos, display_ids):
    """
    Decide which display in the list the cursor is currently sitting on.

    Checks each display's bounding rectangle to see whether the cursor's
    (x, y) coordinates fall inside it.  Returns the index (0-based position
    in the list) of the matching display.

    Edge cases:
      • Cursor exactly on the boundary between two displays → left/upper wins.
      • Cursor position could not be read → returns 0 (the primary display).
      • No display contains the point (e.g. cursor in a gap) → returns 0.
    """
    if cursor_pos is None or not display_ids:
        return 0

    cx, cy = cursor_pos

    for idx, did in enumerate(display_ids):
        b = get_display_bounds(did)
        if b is None:
            continue
        in_x = b['x'] <= cx < b['x'] + b['width']
        in_y = b['y'] <= cy < b['y'] + b['height']
        if in_x and in_y:
            return idx

    return 0


# ===========================================================================
# SECTION 3 — CURSOR MOVEMENT
# ===========================================================================

def get_display_center(display_id):
    """
    Calculate the pixel coordinates of the exact center of a display.

    Returns (x, y) as floats in Quartz screen coordinates, or None if the
    display bounds cannot be read (e.g. the display was just disconnected).
    """
    b = get_display_bounds(display_id)
    if b is None:
        return None
    return (
        b['x'] + b['width']  / 2.0,
        b['y'] + b['height'] / 2.0,
    )


def move_cursor_to(x, y):
    """
    Teleport the mouse cursor to position (x, y) without making noise.

    Why CGWarpMouseCursorPosition instead of generating a mouse-moved event?
    Because warping does NOT fire a mouse-moved event in the target app.
    That means hovering over a button before the jump will not accidentally
    trigger tooltips or hover states after the cursor lands somewhere else.

    CGAssociateMouseAndMouseCursorPosition(True) must be called right after
    warping.  Without it, the physical mouse and the on-screen cursor become
    decoupled — moving the mouse after a warp feels 'sticky' until the OS
    re-syncs them, which can take several seconds.

    Errors are silently swallowed: worst case the cursor does not move.
    """
    try:
        Quartz.CGWarpMouseCursorPosition((x, y))
        Quartz.CGAssociateMouseAndMouseCursorPosition(True)
    except Exception:
        pass


# ===========================================================================
# SECTION 4 — FEEDBACK: SOUND
# ===========================================================================

def play_jump_sound():
    """
    Play a brief built-in system sound so the user knows the jump happened.

    Uses AppKit's NSSound, which reads directly from macOS's own sound
    library — no audio files to bundle with the script.

    'Pop' is the shortest and most subtle option in the standard set.
    Other choices: 'Tink', 'Ping', 'Purr'.  Change the name to suit taste.

    The .play() call is fire-and-forget: the script does not wait for the
    sound to finish.  If sound is muted or playback fails, nothing happens.
    """
    try:
        sound = AppKit.NSSound.soundNamed_("Pop")
        if sound:
            sound.play()
    except Exception:
        pass


# ===========================================================================
# SECTION 5 — FEEDBACK: VISUAL RING
# ===========================================================================

def show_cursor_ring(quartz_x, quartz_y):
    """
    Draw a translucent blue ring around the cursor's new position for
    about half a second, so the user can immediately spot where it landed
    on a large or unfamiliar monitor layout.

    Implementation notes
    --------------------
    • Uses a borderless, non-activating NSPanel (a floating macOS window)
      so the ring never steals focus from the app the user is working in.

    • The panel's content view has wantsLayer=True, which gives it a
      CoreAnimation layer.  We set the layer's cornerRadius to half its
      width to turn the square view into a circle, then give it a thick
      blue border and a transparent fill.

    • AppKit and Quartz use different coordinate systems.  Quartz puts
      (0,0) at the top-left of the primary display (Y increases downward).
      AppKit puts (0,0) at the bottom-left (Y increases upward).  We
      convert by subtracting the Quartz Y from the primary display height.

    • NSRunLoop.runUntilDate_() spins the main run loop for 0.5 seconds so
      macOS actually renders and displays the panel before the script exits.

    Fallback
    --------
    If the ring cannot be drawn for any reason (permission denied,
    sandboxed environment, older macOS), the function calls
    _show_applescript_notification() instead — a toast notification that
    appears in the corner of the screen.  If that also fails, we do nothing.
    """
    try:
        # Tell the shared NSApplication that we are a background-only tool.
        # 'Accessory' policy means no Dock icon appears and the app never
        # takes over the menu bar.
        app = AppKit.NSApplication.sharedApplication()
        app.setActivationPolicy_(
            AppKit.NSApplicationActivationPolicyAccessory
        )

        # ------------------------------------------------------------------
        # Coordinate conversion: Quartz → AppKit
        #
        # AppKit measures Y from the bottom of the primary display upward.
        # To place the ring window's bottom-left corner so that it is
        # visually centered on the cursor, we need:
        #
        #   appkit_x = quartz_x - (ring_size / 2)
        #   appkit_y = primary_height - quartz_y - (ring_size / 2)
        #              ^^^ flips the axis   ^^^ shifts up by half ring
        # ------------------------------------------------------------------
        primary_h = Quartz.CGDisplayBounds(
            Quartz.CGMainDisplayID()
        ).size.height

        ring_size = 72.0
        half      = ring_size / 2.0
        win_x     = quartz_x - half
        win_y     = primary_h - quartz_y - half

        # ------------------------------------------------------------------
        # Create the floating panel.
        #
        # Style mask breakdown (integers, because constants vary by pyobjc):
        #   0   = NSWindowStyleMaskBorderless  (no title bar, no chrome)
        #   128 = NSWindowStyleMaskNonactivatingPanel  (won't steal focus)
        # ------------------------------------------------------------------
        panel = AppKit.NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            AppKit.NSMakeRect(win_x, win_y, ring_size, ring_size),
            0 | 128,                          # borderless + non-activating
            AppKit.NSBackingStoreBuffered,
            False,
        )
        panel.setOpaque_(False)
        panel.setBackgroundColor_(AppKit.NSColor.clearColor())
        panel.setLevel_(1000)                 # float above all normal windows
        panel.setIgnoresMouseEvents_(True)    # clicks pass straight through
        panel.setAlphaValue_(0.85)
        panel.setHidesOnDeactivate_(False)    # stay visible even when switching apps
        panel.setCollectionBehavior_(
            1 << 0    # NSWindowCollectionBehaviorCanJoinAllSpaces — show on every Space
        )

        # ------------------------------------------------------------------
        # Build the circular ring using a CoreAnimation layer.
        #
        # Setting cornerRadius to half the view's size turns a square into
        # a circle.  We set borderWidth + borderColor but leave the
        # background transparent so only the ring outline is visible.
        # ------------------------------------------------------------------
        view = AppKit.NSView.alloc().initWithFrame_(
            AppKit.NSMakeRect(0, 0, ring_size, ring_size)
        )
        view.setWantsLayer_(True)
        layer = view.layer()

        # CGColorCreateGenericRGB(red, green, blue, alpha) — all values 0.0–1.0
        clear_color = Quartz.CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.0)
        blue_color  = Quartz.CGColorCreateGenericRGB(0.15, 0.55, 1.0, 1.0)

        layer.setBackgroundColor_(clear_color)
        layer.setCornerRadius_(half)
        layer.setBorderWidth_(5.0)
        layer.setBorderColor_(blue_color)

        panel.setContentView_(view)
        panel.orderFrontRegardless()

        # Spin the run loop just long enough for macOS to render the panel
        # and keep it visible so the user can see it.
        AppKit.NSRunLoop.currentRunLoop().runUntilDate_(
            AppKit.NSDate.dateWithTimeIntervalSinceNow_(0.45)
        )

        panel.orderOut_(None)   # hide the panel before the script exits

    except Exception:
        # The ring could not be drawn — try a notification toast instead.
        _show_applescript_notification()


def _show_applescript_notification():
    """
    Show a macOS notification as a last-resort visual cue.

    This is the fallback for show_cursor_ring().  It runs osascript in
    a subprocess so it cannot crash the main script.  The notification
    appears in the top-right corner (or Notification Center) and disappears
    on its own.  If notifications are disabled for Terminal or Python in
    System Settings → Notifications, nothing will appear — that is fine.
    """
    try:
        subprocess.run(
            [
                'osascript', '-e',
                'display notification "Cursor moved to next display" '
                'with title "Jumper"',
            ],
            capture_output=True,
            timeout=3,
        )
    except Exception:
        pass    # completely silent if AppleScript is also unavailable


# ===========================================================================
# SECTION 6 — MAIN ENTRY POINT
# ===========================================================================

def main():
    """
    Orchestrate the full jumper sequence.

    Called once per keypress by whatever keyboard shortcut manager the user
    has set up (Hammerspoon, BetterTouchTool, Automator Quick Action, etc.).
    Exits cleanly after the jump — it is not a long-running daemon.

    Steps
    -----
    1. Discover every display that is active right now (fresh read every call).
    2. If fewer than two displays are found, do nothing and exit quietly.
    3. Sort displays left-to-right for predictable, natural cycling.
    4. Read the current cursor position to know which display it is on.
    5. Advance to the next display index, wrapping around at the last one.
    6. Move the cursor to the center of that display.
    7. Play a short click sound for audio feedback.
    8. Draw a brief blue ring around the new cursor position for visual feedback.
    """

    # 1. Read display list fresh — picks up any monitors plugged in since last run
    display_ids = get_connected_displays()

    # 2. Single-display (or no display found) — nothing to jump to
    if len(display_ids) < 2:
        return

    # 3. Ensure a consistent left-to-right order regardless of macOS ID ordering
    display_ids = sort_displays_left_to_right(display_ids)

    # 4. Find out which display the cursor is sitting on right now
    cursor_pos  = get_cursor_position()
    current_idx = find_display_under_cursor(cursor_pos, display_ids)

    # 5. Move one step forward in the list; % wraps the last display back to 0
    next_idx   = (current_idx + 1) % len(display_ids)
    target_id  = display_ids[next_idx]

    # 6. Compute and apply the new cursor position
    target = get_display_center(target_id)
    if target is None:
        return  # display was disconnected between step 1 and now — bail safely
    move_cursor_to(*target)

    # 7 & 8. Audio + visual feedback (both are fire-and-forget, never crash)
    play_jump_sound()
    show_cursor_ring(*target)


if __name__ == '__main__':
    main()
