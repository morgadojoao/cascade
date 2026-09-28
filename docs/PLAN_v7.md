# Plan v7: status item clicks, saved size, run at startup, DMG installer

Status: **approved 2026-09-28, implemented**. Deviation: the 3.4a spike was skipped (the auto-mode sandbox would not register a login item); SMAppService is tried first and a LaunchAgent is the automatic fallback.

## 1. Goals

| # | Feature | Behaviour |
|---|---------|-----------|
| F1 | Double-click the menu bar icon | Cascades **every** listed window at the saved size, no dialog. Failure summary still appears if any window fails. |
| F2 | Right-click (or Control-click) the icon | Shows the menu (below). |
| F3 | Menu > **Select Windows...** | Opens the existing picker, unchanged except the size field is pre-filled with the saved size. |
| F4 | Menu > **Size (1200x800)...** | Small dialog to type a new size. Validated with the existing `parseSize()`. Saved as the new default; the menu title shows the current value. |
| F5 | Menu > **Run at Startup** | Checkbox item. Ticked = Cascade starts when you log in. The tick always reflects the real system state, read each time the menu opens. |
| F6 | Installer | `builds/Cascade-<version>.dmg`. Opening it shows a Finder window with the Cascade icon, an arrow, and an Applications folder alias to drag it onto. |

Final menu layout:

```
Select Windows...
Size (1200x800)...
-----------------
Run at Startup        [tick]
-----------------
Quit Cascade
```

## 2. Decisions (my recommendation first; tell me if you want otherwise)

- **D1. What a single left-click does.** You only specified double-click and right-click.
  - Recommended: a single left-click also opens the menu, after a short wait (the system double-click interval, about 0.3 to 0.5 s) to see whether a second click is coming. That keeps the icon usable for anyone who doesn't know about right-click, at the cost of a slight delay before the menu appears.
  - Alternative: a single click does nothing. No delay, but the icon looks broken to a normal click.
- **D2. Does the size typed in the picker become the default?**
  - Recommended: no. The picker size applies to that one run only, and only **Size...** changes the default. That keeps the saved value predictable for double-click.
  - Alternative: yes, the last size used anywhere becomes the default.
- **D3. Where "Run at Startup" is registered.**
  - Recommended: Apple's `SMAppService.mainAppService` (macOS 13+). This is what normal apps use. Cascade then appears under System Settings > General > Login Items, where you can also switch it off.
  - Fallback, if step 3.4a shows that `SMAppService` doesn't work for an ad-hoc-signed AppleScript applet: a LaunchAgent at `~/Library/LaunchAgents/com.morgadoj.cascade.plist` that runs `open -a Cascade` at login. Same checkbox, same behaviour; it shows in Login Items as "Allow in the Background".
- **D4. One build, two uses.** Today `build.command` installs into `~/Applications`. The DMG installs into `/Applications`. Two copies with the same bundle id would confuse the Accessibility and login-item settings.
  - Recommended: split the build into:
    - `scripts/build_app.sh`: non-interactive; produces `builds/Cascade.app`.
    - `scripts/build.command`: the dev loop; runs `build_app.sh`, copies the app into `/Applications` (not `~/Applications` any more), and launches it.
    - `scripts/make_installer.command`: runs `build_app.sh`, then packages the app into `builds/Cascade-1.0.dmg`.

    The old `~/Applications/Cascade.app` gets removed once, by hand (step 3.5).
  - `builds/` is added to `.gitignore`, so built apps and DMGs are never committed.

## 3. Implementation steps

Each step ends with a compile check (`osacompile -o /tmp/cw_check.scpt cascade.applescript`), the ASCII check (`grep -nP '[^\x00-\x7F]' cascade.applescript` prints nothing), and its own commit.

### 3.1 Refactor: separate "collect", "pick" and "cascade"

Right now `cascadeWindows()` does all three. Split it so double-click can skip the picker:

- `collectWindows()`: returns a record `{labels, pids, idx, titles, firstErr}`. This is the current System Events loop, unchanged.
- `showNoWindowsAlert(firstErr)`: the current "No windows found" alert, moved into its own handler.
- `cascadeChosen(wins, chosenIdx, winW, winH)`: the current per-display cascade loop and failure summary, unchanged.
- `cascadeWithPicker()`: collect, then picker (main-thread hop as today), then `cascadeChosen`.
- `cascadeAll()`: collect, then `cascadeChosen` with every index at the saved size.
- All of the above keep the existing outer `try` / `on error` / "Cascade failed" alert pattern.

No behaviour change in this step; the picker must work exactly as before. This is the riskiest code to touch, so it goes in alone.

### 3.2 Saved size (F4, and feeds F1 and F3)

- Storage: `NSUserDefaults's alloc()'s initWithSuiteName:"com.morgadoj.cascade"`, key `defaultSize`. A fixed suite name means it works the same from the app and from `osascript`. You can inspect it with `defaults read com.morgadoj.cascade`.
- `loadSize()`: returns the saved text if `parseSize()` accepts it, else the `defaultSize` property (1200x800). A corrupt value can never break anything.
- `saveSize(t)`: writes the value.
- `askForSize()`: `display dialog "Cascade window size (W x H):" default answer <current>` with buttons Cancel / Save. Loops on invalid input, with the same hint text the picker uses. Runs on the main thread and brings the app forward first, like the picker.
- The picker's size field pre-fills from `loadSize()`.
- The menu item title is updated to `Size (WxH)...` after saving.
- `defaultSize` stays as the first-run default. CLAUDE.md and the README get updated to say so.

### 3.3 Click handling on the status item (F1, F2, D1)

A status item that has a menu attached opens it on mouse-down and never reports clicks, so double-click can't be detected that way. Instead:

- Don't attach the menu permanently. Give the status item's button a target and action (`statusItemClicked:`), and set `sendActionOn:` to left mouse up plus right mouse up.
- In `statusItemClicked:`, read `NSApp's currentEvent()`:
  - Right mouse up, or left click with Control held: open the menu right away.
  - Left click with `clickCount()` 1: schedule `singleClickTimerFired:` after `NSEvent's doubleClickInterval()` using `performSelector:withObject:afterDelay:`. When it fires it opens the menu (D1).
  - Left click with `clickCount()` 2: cancel the pending single-click with `NSObject's cancelPreviousPerformRequestsWithTarget:me`, then `cascadeAll()`.
- To open the menu: attach it, call `button's performClick:`, and detach it again in the `menuDidClose:` delegate method. This is the standard replacement for the deprecated `popUpStatusItemMenu:`, and it keeps the native menu look and position.
- The menu is rebuilt, or at least refreshed, right before it opens, so the Size title and the Run at Startup tick are current.
- AppleScript has no bitwise AND. The Control-key test is `((flags div 262144) mod 2) is 1`, since NSEventModifierFlagControl is 1 << 18. A short comment will explain it.

### 3.4 Run at Startup (F5, D3)

- **3.4a Spike, done first:** a 10-line throwaway script to confirm that `SMAppService`'s `mainAppService()` `registerAndReturnError:`, `unregisterAndReturnError:` and `status()` work from an ad-hoc-signed applet on macOS 26. **I'll need you here** (see section 6) to confirm that Login Items shows Cascade and to approve any prompt. If it fails, switch to the LaunchAgent fallback. The rest of this step is the same either way, behind two handlers.
- `isRunAtStartupEnabled()` and `setRunAtStartup(flag)`. Errors go into a clear alert, never swallowed.
- The menu item toggles and re-reads the real state to set the tick.
- If macOS reports "requires approval", show an alert that explains it and opens Login Items settings.

### 3.5 Build split and installer (F6, D4)

- `scripts/build_app.sh` holds today's build steps (compile `-s`, icon, Info.plist, `LSUIElement`, bundle id, version, ad-hoc sign), writing to `builds/Cascade.app`. The version comes from a `VERSION` variable at the top of this script and goes into `CFBundleShortVersionString` and the DMG name.
- The `tccutil reset` moves to `build.command` only: the dev loop keeps resetting, while making an installer doesn't touch your permissions. The comment will note that it also clears the grant for the installed `/Applications` copy, since both share the bundle id.
- `scripts/make_dmg_background.swift` renders a 600x400 background, plus a @2x version, with a light gradient, an arrow and "Drag Cascade to Applications". It's written to `assets/dmg_background.png` and committed, in the same style as `make_icon.swift`.
- `scripts/make_installer.command`:
  1. Runs `build_app.sh`.
  2. Stages `Cascade.app`, a symlink `Applications -> /Applications`, and `.background/background.png`.
  3. `hdiutil create -format UDRW`, then attach.
  4. Uses Finder AppleScript to set the window: icon view, no toolbar, window size, 128 px icons, the background picture, and icon positions (app on the left, Applications on the right).
  5. Sets the volume icon to `Cascade.icns`, if `SetFile` is available; otherwise skips it with a message.
  6. Detaches, converts to compressed `UDZO` at `builds/Cascade-1.0.dmg`, removes the temporary image, and opens `builds/` in Finder.
- **Finder permission:** the Finder layout step makes Terminal control Finder, so macOS will ask once for Terminal to control Finder (Automation). **You need to click Allow.**
- **Limitation, documented in the README:** the app is signed ad hoc, not with an Apple Developer ID. The DMG works on this Mac. On another Mac, a downloaded copy is blocked by Gatekeeper until the user chooses **Open Anyway** in System Settings > Privacy & Security. Getting rid of that requires a paid Developer ID and notarization, which is out of scope.

## 4. Code review pass (after 3.1 to 3.5, before QA)

A separate reviewer (a fresh subagent with no stake in the code) goes through the whole diff against this checklist. I then fix what it finds and commit the fixes separately.

**Project rules (CLAUDE.md)**
- [ ] `cascade.applescript` is pure ASCII.
- [ ] Every path that creates AppKit UI (picker, size dialog, alerts from click handlers, the status item, menus) runs on the main thread.
- [ ] Window lookups go only through `findWindow()`, and processes are identified by `unix id`.
- [ ] Move, resize and move again stay in separate `try` blocks, and every failure reaches the summary. There is no new bare `try` without recording or showing the error.
- [ ] NSRect values go only through `rectParts()`.

**Correctness**
- [ ] Double-click never also opens the menu; a single click never also cascades.
- [ ] The status item and menu are held in properties, so nothing is released early.
- [ ] A saved size that is corrupt or missing falls back to 1200x800.
- [ ] The Run at Startup tick matches the real state after toggling, and after a change made in System Settings.
- [ ] `osascript cascade.applescript` still cascades once via the picker.

**Quality**
- [ ] Every handler has a header comment: what it does, its inputs and outputs, and any thread requirement.
- [ ] Names and indentation match the existing file; no dead code; no leftover debug output.
- [ ] Magic numbers (event types, masks, return codes) are named in comments.
- [ ] Shell scripts: `set -e`, quoted paths, a clear message for every step, a non-zero exit on failure, and they can be re-run safely (a stale mount or an existing DMG is handled). `zsh -n` passes, and `shellcheck` too if it's installed.

**Docs**
- [ ] README (use, install from DMG, Run at Startup, Gatekeeper note), CLAUDE.md (layout, handlers, build scripts), DEVELOPMENT_LOG (v7 entry) and BACKLOG (remove done items, add new open ones) all match the code.

## 5. QA pass

The results go in `docs/QA_v7.md`, one row per case with pass/fail and notes. I run the automated checks (A) myself. The manual checks (M) need your hands on the mouse; I'll send them to you as one numbered list to work through, and you reply with pass/fail and a screenshot of anything odd.

**Automated (me)**

| ID | Check |
|----|-------|
| A1 | Compile check, ASCII check, `zsh -n` on every script |
| A2 | `build_app.sh` produces `builds/Cascade.app` with `LSUIElement` = true, `OSAAppletStayOpen` = true, the right bundle id and version, a valid signature (`codesign --verify --deep --strict`), and the custom icon (no `Assets.car`) |
| A3 | Saved size: write, read back and corrupt the value with `defaults`; confirm `loadSize()` behaviour by calling the handler through `osascript` |
| A4 | `cascadeAll()` called in the running app through Apple Events (`tell application id "com.morgadoj.cascade" to cascadeAll()`). Windows move and the summary is correct. May prompt you once for Automation permission. |
| A5 | Run at Startup: toggle through the handlers, confirm with `launchctl` / `sfltool dumpbtm` (SMAppService) or the plist file (LaunchAgent), then toggle back |
| A6 | DMG: `hdiutil verify`, mount read-only, check that `Cascade.app`, the `Applications` symlink and `.background/background.png` are present and that the `.DS_Store` layout was written; unmount |
| A7 | `make_installer.command` run twice in a row succeeds (re-runnable) |

**Manual (you)**

| ID | Check |
|----|-------|
| M1 | Fresh install: remove the old `~/Applications/Cascade.app`, open the DMG, check the window looks right (icon, arrow, Applications), drag to Applications, launch from Launchpad or Spotlight, grant Accessibility |
| M2 | Single click on the icon: the menu appears after a short pause (D1) |
| M3 | Right-click and Control-click: the menu appears immediately |
| M4 | Double-click: every window cascades at the saved size, on each display separately, with no menu or dialog |
| M5 | Select Windows...: the picker opens in front with the size pre-filled from the saved value; All / None, Return and Escape work; the cascade works |
| M6 | Size...: invalid input (`abc`, `50x50`) shows the hint and stays open; a valid size saves, the menu title updates, the next double-click uses it; Cancel changes nothing |
| M7 | The size survives Quit and relaunch |
| M8 | Run at Startup: tick it, log out and back in (or restart), and Cascade is in the menu bar; untick it, log out and in, and it isn't. The tick matches System Settings > General > Login Items. |
| M9 | Two displays: double-click gives each display its own cascade from its own top-left |
| M10 | Electron apps (Claude, Teams) are included in the double-click cascade, or listed in the failure summary with a reason |
| M11 | Quit Cascade quits; relaunching restores the menu bar item |
| M12 | Relaunching while it's already running (from Spotlight) opens the picker |

Any failure goes back to section 3 with a targeted fix, then that case and anything near it gets re-tested. Release is done when every case passes or has an accepted, documented reason in BACKLOG.md.

## 6. Where I'll need you

1. **Step 3.4a:** after I build the spike, you open System Settings > General > Login Items and tell me whether Cascade is listed. About 1 minute.
2. **Every rebuild** clears Accessibility, so you re-allow Cascade when asked. I'll batch changes so this happens as rarely as possible.
3. **Step 3.5:** click **Allow** when macOS asks whether Terminal may control Finder (once), and **Allow** if asked whether Terminal may control Cascade (for A4, once).
4. **Step 3.5 / M1:** delete `~/Applications/Cascade.app` (I'll give you the exact command) so only the `/Applications` copy remains.
5. **QA:** the manual cases M1 to M12, including one logout for M8.

## 7. Commits

`refactor: split collect/pick/cascade` -> `saved size` -> `status item clicks and menu` -> `run at startup` -> `build split and DMG installer` -> `code review fixes` -> `QA fixes + QA_v7.md + docs`. Nothing is pushed until you say so.
