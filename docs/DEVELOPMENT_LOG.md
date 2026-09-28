# Development log

Chronological record of how `cascade.applescript` reached its current state. Each entry is a problem that was actually hit, its cause, and the fix now in the code. All dates are 2026-09-28; the whole thing was built in one session.

## v1 — two-dialog version

Original request: a macOS script that first asks which windows to cascade, has a size field with a default value, and a Cascade button.

First implementation used the built-in `choose from list` for the window picker (multiple selection, all pre-selected) followed by `display dialog` with a `default answer` size field and buttons `{"Cancel", "Cascade"}`. Windows were enumerated with System Events (`every application process whose background only is false and visible is true`, then `every window of p`), labelled `"N. App - Title"`, and re-found later by process **name** and window **index**. Screen size came from Finder's `bounds of window of desktop`. Cascade started at a fixed `{20, 50}` offset and wrapped to a new column when it ran off screen.

Result: compiled and ran, but only knew about one screen.

## v2 — per-display cascade

Request: "The windows should cascade in the screen they're in."

Added `use framework "AppKit"` and `getScreens()`, which reads `NSScreen screens()` and converts each display's `frame()` and `visibleFrame()` to System Events coordinates (top-left origin) by flipping with the primary display's height. Each chosen window's centre point is tested against the full frames to choose its display; each display keeps its own cascade cursor (`curX`, `curY`, `wraps` parallel lists). The requested size is clamped to the display's usable area minus margins. `startX/startY` were replaced by `marginX/marginY` since `visibleFrame` already excludes the menu bar and Dock.

### Bug: `Can't get size of {{0.0, 0.0}, {2056.0, 1329.0}}. (-1728)`

Cause: on the user's macOS, an `NSRect` comes back from AppleScriptObjC as a nested **list** `{{x, y}, {w, h}}`, not the record `{origin:{x:…}, size:{width:…}}` the code assumed.

Fix: added `rectParts(r)` which tries the record form and falls back to the list form, returning a flat `{x, y, w, h}`.

## v3 — robustness for Electron apps

Report: "Some windows are not being cascaded — the Claude desktop window and the MS Teams window."

Root cause could not be observed because every failure was inside a bare `try` that swallowed the error. Three changes were made together so the next run would either work or explain itself:

1. **Lookup by pid + title, not name + index.** Windows are now recorded with the process's `unix id`, original index, and title. `findWindow()` resolves via `first application process whose unix id is pid`, then `every window whose name is wTitle` if that yields exactly one match, else `window (index + shiftCount)`. `shiftCount` is the number of already-raised windows in the same app that had a higher original index, because `AXRaise` moves a window to index 1 and shifts the others down.
2. **Move, then resize, then move again**, each in its own `try`. Previously `set size` ran first and any error aborted the block before `set position` ever executed.
3. **Failure summary.** Errors are collected into `failures` as `"App - Title -> move: <msg>"` and shown in one `display alert` at the end.

Outcome: the user did not report the Claude/Teams problem again after this change, but it was also not explicitly confirmed fixed. See `BACKLOG.md`.

## v4 — single dialog

Request: "consolidate the resolution setting into the window picker window."

`choose from list` cannot host a text field, so the picker was rebuilt as an `NSAlert` with an accessory `NSView`:

- `NSScrollView` (bezel border, vertical scroller, capped at ~12 rows) containing a plain `NSView` document view with one checkbox `NSButton` per window (`setButtonType:3`, `setState:1`, `setLineBreakMode:4` for tail truncation). AppKit views have a bottom-left origin, so row `i` is placed at `y = (n - i) * rowH` and `docView's scrollPoint:{0, listH}` scrolls to the top.
- `NSTextField labelWithString:"Size (W x H):"` plus an editable `NSTextField` pre-filled with `defaultSize`.
- "All" and "None" `NSButton`s with `setTarget:me` and `setAction:"selectAllWindows:"` / `"selectNoWindows:"`; the handlers iterate the `checkBoxes` property.
- Alert buttons "Cascade" (first, so it is default and returns 1000) and "Cancel" (second, gets Escape automatically).
- Validation loop: on bad size or empty selection, the alert's informative text is changed to a hint and `runModal()` is called again on the same alert so the user's ticks and text survive.

Labels dropped the `"N. "` prefix because the checkbox index is now the lookup key directly; `labelIndex()` was removed.

### Bug: `NSWindow should only be instantiated on the main thread! (-10000)`

Cause: Script Editor's Run button executes scripts on a background thread. AppKit requires window creation on the main thread.

Fix: `on run` sets `pickerLabels`, clears `pickerResult`, then calls `my performSelectorOnMainThread:"showPickerOnMainThread:" withObject:(missing value) waitUntilDone:true`. The `showPickerOnMainThread:` handler calls `showPicker()` and stores the result in `pickerResult`. Any error inside is shown with `display alert` from the main thread so it does not vanish.

### Bug: `Syntax Error — Expected "then", etc. but found unknown token.`

Cause: Script Editor had re-saved the `.applescript` file earlier, converting `>=` into the `≥` symbol encoded in **Mac Roman** (single byte 0xB3). A later read/write of the file as UTF-8 turned that byte into U+FFFD, which the AppleScript compiler rejects.

Fix: replaced with `is greater than or equal to`. The file is now verified pure ASCII. Rule recorded in `APPLESCRIPT_GOTCHAS.md`: never let Script Editor save the source file.

## v5 — shipping as an app

User confirmed the script works ("It's perfect now") and asked how to run it without Script Editor.

Answer: `osacompile -o ~/Applications/"Cascade.app" cascade.applescript`, then grant the app Accessibility permission on first run and drag it to the Dock. Optional global hotkey via Shortcuts app: an "Open App" action pointing at the app, with a keyboard shortcut assigned in the shortcut's details pane.

The user wrote `scripts/build.command` (a double-clickable zsh script) that removes any previous build, runs `osacompile` into `~/Applications`, launches the app, opens the folder, and prints the permission reminder. It has been adjusted to `cd` to the repo root so it works from `scripts/`.

## v6 - icon, git, menu bar app

- Custom icon: `scripts/make_icon.swift` renders `assets/Cascade.icns`. build.command copies it over `applet.icns`, deletes `Assets.car` and `CFBundleIconName` (otherwise macOS keeps showing the default script icon), sets `CFBundleIdentifier` to `com.morgadoj.cascade`, and re-signs ad hoc because editing the bundle invalidates osacompile's signature.
- `build.command` was committed without the execute bit and Finder refused to run it ("could not be executed because you do not have appropriate access privileges"). Fixed with `chmod u+x`; git tracks it as 100755.
- Request: "live in the mac top bar". The app is now compiled stay-open (`osacompile -s`) with `LSUIElement` true (no Dock icon). `on run` installs an `NSStatusItem` whose menu calls `cascadeFromMenu:` (target `me`, same dispatch mechanism as the All / None buttons). The old `on run` body is now `cascadeWindows()`, which starts with `NSApp's activateIgnoringOtherApps:true` because an LSUIElement app is never frontmost by itself and the picker would otherwise open without keyboard focus. When there is no `LSUIElement` flag (running the source with osascript) it cascades once as before. build.command quits a running copy before replacing it.
- Not yet tested by the user.

### Bug: "No windows found" although Cascade.app is ticked in Accessibility

Cause (most likely): the app is signed ad hoc, so the TCC grant is pinned to that build's code hash. After a rebuild the list still shows Cascade as on, but the grant no longer matches the new binary. System Events still lists processes, then `every window of p` fails for each one; that error was swallowed, so the user only saw "No windows found".

Fix: the first window-read error is now included in the alert, with a button that opens the Accessibility settings pane. build.command runs `tccutil reset Accessibility com.morgadoj.cascade` after signing so each build asks for permission again cleanly. Immediate workaround: remove Cascade from the list with the minus button and add it again (or run the tccutil reset once).

## v7 - clicks, saved size, Run at Startup, DMG installer

User confirmed the v6 menu bar app works after the `tccutil reset` fix. Request: double-click the icon to cascade everything at the saved size; right-click menu with Select Windows... and Size... (saved as default); a Run at Startup checkbox; a drag-to-Applications DMG in `builds/`. Planned in `docs/PLAN_v7.md` (approved with the recommended decisions D1-D4).

- **Refactor.** `cascadeWindows()` split into `collectWindows()`, `cascadeChosen()`, `cascadeWithPicker()` and `cascadeAll()` so double-click can skip the picker. The per-display loop is unchanged.
- **Clicks.** A status item with a menu attached opens it on mouse-down and never reports clicks, so the menu is attached only while open: the button has target `me`, action `statusItemClicked:`, `sendActionOn:20` (left-up 4 + right-up 16). The handler reads `NSApp's currentEvent()`: event type 4 or the Control flag (`(flags div 262144) mod 2`, since AppleScript has no bitwise AND) opens the menu; `clickCount` 2 cancels the pending single-click and cascades; `clickCount` 1 schedules `singleClickTimerFired:` with `performSelector:withObject:afterDelay:` using `NSEvent's doubleClickInterval()`. The menu opens via `setMenu:` + `performClick:` and is detached in the `menuDidClose:` delegate method.
- **Saved size.** NSUserDefaults, key `defaultSize`. Inside the app that has to be `standardUserDefaults()` (opening the app's own bundle id with `initWithSuiteName:` is refused); under osascript the suite is opened by name, so both read the same domain. `loadSize()` validates with `parseSize()` and falls back to 1200x800.
- **Run at Startup.** The planned SMAppService spike (3.4a) was skipped: the auto-mode sandbox would not register a login item. Instead the code tries `SMAppService mainAppService` first and automatically falls back to a LaunchAgent that runs `open -a <app path>`. Which path wins on the user's Mac is checked in QA (M8).
- **Build split.** `build_app.sh` builds into `builds/`; `build.command` installs into `/Applications` (not `~/Applications` any more); `make_installer.command` makes the DMG.
- **Compile errors from reserved words:** `st` and `current` (then, in the review fixes, `startup`) are terminology in the standard additions. Renamed to `svcStatus`, `sizeText`, `startupState`.
- **ASCII guard.** `grep '[^[:print:]]'` did not catch UTF-8 multi-byte characters under the default locale; replaced with a perl byte check. The review then found that `perl ... | grep -q .` can pass silently under `pipefail` (SIGPIPE), so the output is captured in a variable instead.
- **DMG volume icon vanished.** `.VolumeIcon.icns` plus `SetFile -a C` was written before the Finder layout step; after Finder's `update` / `close` the file was gone and the flag cleared. Moving the step after the Finder layout fixed it.
- **DMG background arrow.** Semi-transparent arrow head and shaft overlapped into a darker band; the arrow is drawn opaque.

### Code review (fresh subagent, checklist in PLAN_v7 section 4)

Fixed: Run at Startup counted "requires approval" (status 2) as on, so after switching Cascade off in System Settings the tick stayed and a click unregistered it; it now shows a mixed state and opens Login Items. Unregistering was attempted on status 3 and could show a false error. Errors in AppKit-invoked handlers (timer, menu delegate, menu actions) were lost; each now calls `showError`. `clickCount()` on a non-mouse event (VoiceOver) would throw; such events open the menu. `on quit` clears AppKit-object properties before the applet saves state. The DMG layout now refuses a volume mounted as "Cascade 1". The `builds/` copy is unregistered from LaunchServices so only `/Applications/Cascade.app` resolves by bundle id. Missing header comments added. Deferred to BACKLOG: LaunchAgent disabled in System Settings still shows ticked; single/double-click separation to be confirmed by hand.

### QA

All automated and manual cases in `docs/QA_v7.md` pass. Run at Startup registered through SMAppService (no LaunchAgent written). The user installed into `~/Applications`; after Quit the signature still verifies and `main.scpt` is unchanged, so the applet does not write its properties back.
