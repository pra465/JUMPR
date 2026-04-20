# Jumper

**Instantly move your mouse cursor to the next screen — using just your keyboard.**

No more dragging the mouse across monitors. Press one key and your cursor teleports to the next display.

| Platform | Shortcut | Action |
|---|---|---|
| Mac | Cmd + ` | Jump cursor to next screen |
| Windows | Ctrl + ` | Jump cursor to next screen |

Cycles left-to-right through all connected displays and wraps back to the first.

---

## Installing on a Mac

You will need to type a couple of commands in a program called **Terminal**. It sounds scary, but you are just copy-pasting two lines — that is all.

### Step 1 — Open Terminal

Press **Command + Space**, type `Terminal`, and press **Enter**. A black or white window with a blinking cursor will appear.

### Step 2 — Install Python 3 (if you do not have it already)

Paste this line into Terminal and press **Enter**:

```
python3 --version
```

If you see something like `Python 3.x.x`, you are good — skip to Step 3.
If you see an error, visit **https://www.python.org/downloads/** and click the big yellow "Download Python" button. Run the installer, then come back here.

### Step 3 — Download this project

If you are reading this on GitHub, click the green **Code** button at the top of the page, then choose **Download ZIP**. Unzip the downloaded file somewhere easy to find, like your Desktop.

### Step 4 — Run the installer

In Terminal, type `cd ` (with a space after it), then drag the **mac** folder from the unzipped project into the Terminal window. The path will fill in automatically. Press **Enter**.

Then paste this line and press **Enter**:

```
bash install.sh
```

The installer will run through five steps. When it asks about Accessibility permission, follow the on-screen instructions to tick the checkbox — this is what lets the app move your cursor.

### Step 5 — Try it out

Press **Cmd + `** (the backtick key, top-left of the keyboard). Your cursor should jump to your next screen. That is it — you are done!

Jumper will start automatically every time you log in. To stop it, remove it from **System Settings → General → Login Items**.

---

## Installing on Windows

No Terminal needed on Windows — everything is done by right-clicking.

### Step 1 — Download this project

If you are reading this on GitHub, click the green **Code** button at the top of the page, then choose **Download ZIP**. Unzip the downloaded file somewhere easy to find, like your Desktop.

### Step 2 — Open the windows folder

Inside the unzipped project folder, open the folder called **windows**.

### Step 3 — Run the installer

Right-click the file named **install.ps1** and choose **"Run with PowerShell"**.

A blue window will appear and walk through five steps automatically:
- It will download and install AutoHotkey (the free tool that powers Jumper)
- It will add Jumper to your Startup so it runs every time you log in
- It will create a shortcut on your Desktop

If Windows asks *"Do you want to allow this app to make changes?"* click **Yes**.

### Step 4 — Try it out

Press **Ctrl + `** (the backtick key, top-left of the keyboard). Your cursor should jump to your next screen. You are done!

Jumper will start automatically every time you log in. To stop it, right-click the Jumper icon in your taskbar and choose **Exit**.

---

## Frequently Asked Questions

**Do I need to pay for anything?**
No. Jumper and all the tools it uses are completely free.

**Will this slow down my computer?**
No. The script is tiny and uses almost no resources while it is running in the background.

**I made a mistake during install. Can I start over?**
Yes. On Mac, run `bash install.sh` again. On Windows, right-click `install.ps1` and run it again — it is safe to run more than once.

**How do I uninstall it?**
See the **Uninstall** section below — one command does everything.

---

*Built with Python + pyobjc (Mac) and AutoHotkey v2 (Windows).*

---

## Troubleshooting

### Mac

**The shortcut Cmd+\` does nothing**
macOS requires you to explicitly enable each Quick Action before its shortcut fires. Go to **System Settings → Keyboard → Keyboard Shortcuts → Services**, scroll down to find **Jumper**, and make sure the checkbox next to it is ticked. If no shortcut is shown, click in the shortcut column and press Cmd+\`.

**The cursor does not move when I press the shortcut**
Jumper needs Accessibility permission to control the mouse. Open **System Settings → Privacy & Security → Accessibility**, find **Terminal** (or whichever app you used to run the installer) in the list, and make sure its toggle is on. You may need to remove and re-add the entry after granting permission.

**It jumps, but I cannot see where the cursor went**
The cursor jumped to a different screen — look at your other monitor. The blue ring highlight should appear there for half a second. If you only have one monitor, the shortcut does nothing (by design).

**The installer says pyobjc failed to install**
Run this line in Terminal, then run the installer again:
```
pip3 install pyobjc-framework-Quartz pyobjc-framework-Cocoa
```

**The wrong screen order / it cycles in the wrong direction**
Jumper follows the physical left-to-right arrangement shown in **System Settings → Displays**. Drag the display icons there to match how your monitors are physically positioned on your desk.

---

### Windows

**Ctrl+\` does nothing**
AutoHotkey may not be running. Look for the Jumper icon near the clock in your taskbar. If it is not there, double-click `jumper.ahk` in `%APPDATA%\jumper\` to start it. If that folder does not exist, run `install.ps1` again.

**The cursor does not jump**
Your monitors may be set to **Duplicate / Clone** mode, which makes Windows report them as a single display. Open **Settings → System → Display** and make sure the mode is set to **Extend these displays**.

**PowerShell says "cannot be loaded because running scripts is disabled"**
Right-click `install.ps1`, choose **Properties**, scroll to the bottom of the General tab, and click **Unblock**. Then right-click the file again and choose **Run with PowerShell**.

**It does not start automatically after a reboot**
The Startup shortcut may not have been created. Run `install.ps1` again — it is safe to run more than once and will recreate the shortcut.

**It jumps to the wrong monitor**
Jumper cycles monitors in the order Windows arranges them in **Settings → System → Display**. Drag the numbered display boxes there to match your physical desk layout and try again.

---

## Testing it works

After installing, you can run a quick automated test to confirm that display detection is working correctly on your specific hardware.

**Mac:**
```
bash mac/test.sh
```
The test moves the cursor to the centre of each connected display, then checks that Jumper correctly identifies which screen it is on each time. Results are printed as PASS / FAIL / SKIP.

**Windows:**
Double-click `windows/test.ahk`. A results window will appear showing PASS / FAIL / SKIP for each check. The cursor will jump around briefly during the test and return to its original position when done.

---

## Uninstall

**Mac:**
```
bash mac/uninstall.sh
```
This stops any running process, removes the installed script, deletes the Quick Action, removes the keyboard shortcut from system preferences, and removes the Login Item — all in one step.

**Windows:**
Right-click `windows/uninstall.ps1` and choose **Run with PowerShell**. This stops the running AutoHotkey process, deletes the script from AppData, and removes the Startup shortcut.
