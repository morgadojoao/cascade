# CLAUDE.md — Cascade

A macOS utility, written in AppleScript + AppleScriptObjC, that shows one dialog listing every open window, lets the user tick the ones they want and enter a size, then cascades the ticked windows diagonally **on whichever display each window is already on**. It is built into a standalone `.app` with `osacompile`.

Status as of 2026-09-28: **working and user-approved ("perfect")**. Read `docs/DEVELOPMENT_LOG.md` before changing anything; every design choice in the script exists because something simpler broke.

## Repo layout

```
cascade.applescript   # THE source. Single file. Edit this, nothing else.
scripts/build.command         # Double-click (or run) to compile -> ~/Applications/Cascade.app (adds icon, bundle id, re-signs)
scripts/make_icon.swift       # Renders assets/Cascade.icns (swift scripts/make_icon.swift)
assets/Cascade.icns           # App icon copied into the bundle by build.command
docs/DEVELOPMENT_LOG.md       # Chronological record of every bug hit and how it was fixed
docs/APPLESCRIPT_GOTCHAS.md   # Rules for editing this file safely (encoding, threads, AX quirks)
docs/BACKLOG.md               # Open items and ideas not yet done
README.md                     # End-user instructions
```

## Hard rules for editing `cascade.applescript`

1. **Keep the file pure ASCII.** Never write `≥`, `≤`, `≠`, em dashes, or smart quotes. Spell comparisons out (`is greater than or equal to`). Script Editor rewrites `>=` as `≥` in Mac Roman on save, and that byte then breaks the file for the next edit. Before handing the file back, run `grep -nP '[^\x00-\x7F]' cascade.applescript` and expect no output.
2. **Do not open/save the source in Script Editor.** The user builds and runs the `.app`. If Script Editor is used for a quick compile check, do not save from it. If the file's whitespace suddenly changes to tabs and `>=` becomes a symbol, Script Editor touched it.
3. **All AppKit UI runs on the main thread.** Anything that creates an `NSAlert`/`NSWindow`/`NSView` must be reached through `my performSelectorOnMainThread:"handler:" withObject:(missing value) waitUntilDone:true`, passing data in and out through script `property` values (see `pickerLabels` / `pickerResult`). Script Editor runs scripts on a background thread; `osascript` and the compiled app do not, but the hop is harmless there.
4. **Window lookups go through `findWindow(pid, index, title, shiftCount)`.** Identify processes by `unix id`, never by name. Prefer title match; fall back to index adjusted for windows already raised in that app (AXRaise reorders indices).
5. **Move before resize, each in its own `try`, and collect failures.** Some apps (Electron: Claude, Teams) reject one call but accept the other. Errors are appended to `failures` and shown in one summary alert at the end. Never silently swallow errors again.
6. **Handle both NSRect shapes.** `NSScreen frame()`/`visibleFrame()` may return a record `{origin:{x,y}, size:{width,height}}` or a nested list `{{x,y},{w,h}}`. Always go through `rectParts()`.
7. Coordinates: System Events uses top-left origin, y down. AppKit uses bottom-left origin, y up. Flip with `primaryScreenHeight - (y + h)`. This is done once in `getScreens()`; downstream code works only in System Events coordinates.

## How to build and test

```
# Build (also launches the app and opens ~/Applications)
./scripts/build.command

# Or by hand
mkdir -p ~/Applications
osacompile -o ~/Applications/"Cascade.app" cascade.applescript

# Compile-check only, no app produced (catches syntax errors fast)
osacompile -o /tmp/cw_check.scpt cascade.applescript && echo OK

# Run from source without building
osascript cascade.applescript
```

Testing is manual: run it with several apps open across two displays and confirm each display gets its own cascade starting at its own top-left, ticked windows move and resize, and the summary alert lists any that did not. Test Electron apps specifically (Claude desktop, Microsoft Teams) since they were the ones that misbehaved.

Permissions: the compiled app needs its own Accessibility grant (System Settings > Privacy & Security > Accessibility). Rebuilding produces a new binary; if positioning silently does nothing after a rebuild, toggle the app off and on in that list.

## Tunables (top of the script)

`defaultSize` ("1200x800"), `stepX` (40), `stepY` (32), `marginX` (20), `marginY` (20). The size is clamped so a window is never larger than the usable area of its display.

## Script structure (handlers)

- `on run` — enumerate windows via System Events, call picker on main thread, then cascade per display.
- `showPickerOnMainThread:` — main-thread wrapper; reads `pickerLabels`, writes `pickerResult`.
- `showPicker(labels)` — builds the NSAlert: NSScrollView of checkbox NSButtons, "Size (W x H)" NSTextField, All/None NSButtons (target `me`, actions `selectAllWindows:` / `selectNoWindows:`), buttons "Cascade" (return code 1000) and "Cancel". Loops on invalid size / empty selection.
- `findWindow(pid, wi, wTitle, shiftCount)` — robust window resolution.
- `getScreens()` / `rectParts(r)` / `screenIndexForPoint(px, py, screens)` — display geometry.
- `parseSize(t)` / `replaceText(t, a, b)` — accepts "1200x800", "1200 x 800", "1200,800"; minimum 100x100.

## Working style the user expects

The user (Unity developer, comfortable in Terminal) tests on their own Mac and reports back with a screenshot of the error dialog. Work in small, targeted fixes; keep the summary-alert diagnostics so failures are self-describing. Prefer changes that can be verified in one run. Do not ask permission for obvious next steps.
