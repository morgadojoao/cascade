# CLAUDE.md — Cascade

A macOS menu bar app, written in AppleScript + AppleScriptObjC, that cascades windows diagonally **on whichever display each window is already on**. Double-clicking its menu bar icon cascades every window at a saved size; its menu (right-click, or a single click after a short pause) offers Select Windows... (a checklist picker with a size field), Size... (saves the default size), Run at Startup and Quit. It is built into a stay-open `.app` (no Dock icon) with `osacompile -s` and shipped as a drag-to-Applications DMG.

Status as of 2026-09-28: v6 (menu bar app) user-approved. v7 (clicks, saved size, Run at Startup, DMG) implemented and code-reviewed; manual QA pending, see `docs/QA_v7.md`. Read `docs/DEVELOPMENT_LOG.md` before changing anything; every design choice in the script exists because something simpler broke.

## Repo layout

```
cascade.applescript                # THE source. Single file.
scripts/build_app.sh               # Non-interactive build -> builds/Cascade.app (ASCII guard, icon, Info.plist, version, ad-hoc sign)
scripts/build.command              # Dev loop: build_app.sh, install to /Applications, reset Accessibility, launch
scripts/make_installer.command     # build_app.sh, then builds/Cascade-<version>.dmg with a laid-out Finder window
scripts/make_icon.swift            # Renders assets/Cascade.icns
scripts/make_dmg_background.swift  # Renders assets/dmg_background.png and @2x
assets/                            # Icon and DMG background (committed)
builds/                            # Build output (git-ignored)
docs/DEVELOPMENT_LOG.md            # Chronological record of every bug hit and how it was fixed
docs/APPLESCRIPT_GOTCHAS.md        # Rules for editing this file safely (encoding, threads, AX quirks)
docs/BACKLOG.md                    # Open items and ideas not yet done
docs/PLAN_v7.md, docs/QA_v7.md     # v7 plan and QA results
README.md                          # End-user instructions
```

## Hard rules for editing `cascade.applescript`

1. **Keep the file pure ASCII.** Never write `≥`, `≤`, `≠`, em dashes, or smart quotes. Spell comparisons out (`is greater than or equal to`). Script Editor rewrites `>=` as `≥` in Mac Roman on save, and that byte then breaks the file for the next edit. Before handing the file back, run `grep -nP '[^\x00-\x7F]' cascade.applescript` and expect no output. `build_app.sh` refuses to build a non-ASCII file.
2. **Do not open/save the source in Script Editor.** The user builds and runs the `.app`. If Script Editor is used for a quick compile check, do not save from it. If the file's whitespace suddenly changes to tabs and `>=` becomes a symbol, Script Editor touched it.
3. **All AppKit UI runs on the main thread.** Anything that creates an `NSAlert`/`NSWindow`/`NSView` must be reached through `my performSelectorOnMainThread:"handler:" withObject:(missing value) waitUntilDone:true`, passing data in and out through script `property` values (see `pickerLabels` / `pickerResult`). Script Editor runs scripts on a background thread; `osascript` and the compiled app do not, but the hop is harmless there. Status item, menu, menu-delegate and timer handlers are already called by AppKit on the main thread; each one must catch its own errors (`showError`), because an error left uncaught there only reaches the system log.
4. **Window lookups go through `findWindow(pid, index, title, shiftCount)`.** Identify processes by `unix id`, never by name. Prefer title match; fall back to index adjusted for windows already raised in that app (AXRaise reorders indices).
5. **Move before resize, each in its own `try`, and collect failures.** Some apps (Electron: Claude, Teams) reject one call but accept the other. Errors are appended to `failures` and shown in one summary alert at the end. Never silently swallow errors again.
6. **Handle both NSRect shapes.** `NSScreen frame()`/`visibleFrame()` may return a record `{origin:{x,y}, size:{width,height}}` or a nested list `{{x,y},{w,h}}`. Always go through `rectParts()`.
7. **Compile after every edit; watch for reserved words.** `st`, `current` and `startup` compile as terminology and fail as variable names. Event and record keys that must keep their case use pipes (`|type|`, `|Label|`).
8. Coordinates: System Events uses top-left origin, y down. AppKit uses bottom-left origin, y up. Flip with `primaryScreenHeight - (y + h)`. This is done once in `getScreens()`; downstream code works only in System Events coordinates.

## How to build and test

```
# Dev build: builds, installs to /Applications, resets Accessibility, launches
./scripts/build.command

# Installer: builds/Cascade-<version>.dmg (VERSION is at the top of build_app.sh)
./scripts/make_installer.command

# Build only -> builds/Cascade.app
./scripts/build_app.sh

# Compile-check only, no app produced (catches syntax errors fast)
osacompile -o /tmp/cw_check.scpt cascade.applescript && echo OK

# Run from source without building (no LSUIElement flag, so it opens the picker once)
osascript cascade.applescript

# Call a non-UI handler of the compiled script
osascript -e 'set s to load script POSIX file "/tmp/cw_check.scpt"' -e 'tell s to loadSize()'
```

Testing is mostly manual; the checklist is in `docs/QA_v7.md`. Run it with several apps open across two displays and confirm each display gets its own cascade starting at its own top-left, windows move and resize, and the summary alert lists any that did not. Test Electron apps specifically (Claude desktop, Microsoft Teams) since they were the ones that misbehaved.

Permissions: the compiled app needs its own Accessibility grant (System Settings > Privacy & Security > Accessibility). It is signed ad hoc, so the grant is tied to the exact binary and goes stale on every rebuild; `build.command` runs `tccutil reset Accessibility com.morgadoj.cascade` so the new build asks again. Keep one installed copy, in `/Applications` (`build_app.sh` unregisters the `builds/` copy from LaunchServices; an old `~/Applications/Cascade.app` must be deleted).

## Tunables (top of the script)

`defaultSize` ("1200x800", the first-run size; after that the saved size wins, see `defaults read com.morgadoj.cascade defaultSize`), `stepX` (40), `stepY` (32), `marginX` (20), `marginY` (20). The size is clamped so a window is never larger than the usable area of its display. `appBundleId` must match `BUNDLE_ID` in `build_app.sh`.

## Script structure (handlers)

- Lifecycle: `on run` installs the status item on the main thread if Info.plist has `LSUIElement` (built app), otherwise calls `cascadeWithPicker()` once (osascript). `on reopen` opens the picker. `on quit` clears properties holding AppKit objects before the applet saves its state.
- Menu bar: `setupStatusItem:` builds the status item and menu (not attached, so clicks reach the button). `statusItemClicked:` reads `NSApp's currentEvent()`: type 4 (right mouse up) or the Control flag (bit 18) opens the menu; a non-mouse event opens the menu; `clickCount` 2 cancels the pending timer and calls `cascadeAll()`; `clickCount` 1 schedules `singleClickTimerFired:` after `NSEvent's doubleClickInterval()`. `showStatusMenu()` refreshes, attaches the menu and calls `performClick:`; `menuDidClose:` detaches it. `refreshMenu()` sets the Size title and the Run at Startup tick (on / mixed / off). Actions: `selectWindowsFromMenu:`, `sizeFromMenu:`, `toggleStartupFromMenu:`, `quitFromMenu:`. Helpers: `newMenuItem`, `bringToFront()`, `showError(m, n)`.
- Cascading: `cascadeWithPicker()` (collect, picker on the main thread pre-filled with `loadSize()`, cascade), `cascadeAll()` (every window at the saved size, no activation), `collectWindows()` returns `{labels, pids, idx, titles, firstErr}`, `showNoWindowsAlert(errText)`, `cascadeChosen(wins, chosenIdx, winW, winH)` (per-display loop and failure summary).
- Saved size: `prefs()` (NSUserDefaults, domain `com.morgadoj.cascade`: standard defaults inside the app, the suite by name under osascript), `loadSize()` (falls back to `defaultSize` on a missing or invalid value), `saveSize(t)`, `askForSize()` (validation loop; Cancel changes nothing). The picker size is one-off; only Size... saves.
- Run at Startup: `runAtStartupState()` returns "on" / "approval" / "off"; `loginItemStatus()` (SMAppService status 0 not registered, 1 enabled, 2 requires approval, 3 not found); `setRunAtStartup(enable)` tries `SMAppService mainAppService` and falls back to the LaunchAgent `~/Library/LaunchAgents/com.morgadoj.cascade.login.plist` (`open -a <app path>`); `showApprovalNeeded()` opens Login Items; `launchAgentPath()`.
- `showPickerOnMainThread:` — main-thread wrapper; reads `pickerLabels` and `pickerSize`, writes `pickerResult`.
- `showPicker(labels)` — builds the NSAlert: NSScrollView of checkbox NSButtons, "Size (W x H)" NSTextField, All/None NSButtons (target `me`, actions `selectAllWindows:` / `selectNoWindows:`), buttons "Cascade" (return code 1000) and "Cancel". Loops on invalid size / empty selection.
- `findWindow(pid, wi, wTitle, shiftCount)` — robust window resolution.
- `getScreens()` / `rectParts(r)` / `screenIndexForPoint(px, py, screens)` — display geometry.
- `parseSize(t)` / `replaceText(t, a, b)` — accepts "1200x800", "1200 x 800", "1200,800"; minimum 100x100.

## Working style the user expects

The user (Unity developer, comfortable in Terminal) tests on their own Mac and reports back with a screenshot of the error dialog. Work in small, targeted fixes; keep the summary-alert diagnostics so failures are self-describing. Prefer changes that can be verified in one run. Do not ask permission for obvious next steps.
