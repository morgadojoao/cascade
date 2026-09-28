# Backlog

Open items, unverified fixes, and ideas. Nothing here is committed work; the script is considered done for the user's current needs.

## Needs confirmation

- **Electron windows (Claude desktop, Microsoft Teams).** In v2 these two windows did not move. v3 changed lookup to pid+title, split move/resize into independent steps, and added the failure summary. The user has not reported the problem since and called the final build "perfect", but never explicitly confirmed those two apps now cascade. If they still fail, the summary alert will name the failing step; likely next moves are `set frontmost of process to true` before positioning, or a short `delay 0.1` between move and resize.
- **All / None buttons in the compiled app.** They rely on `setTarget:me` / `setAction:` dispatching back into the script. This worked in the tested run but is the part most sensitive to how the script is hosted. Re-check after any change to how the picker is invoked.

- **v7 manual QA** (`docs/QA_v7.md`, M1-M12). In particular:
  - Single click vs double-click: the timer is cancelled with `cancelPreviousPerformRequestsWithTarget:me`, which relies on ASObjC bridging `me` to the same object each time. If a double-click ever also opens the menu, switch to a click-serial property passed as `withObject:` and checked in `singleClickTimerFired:`.
  - `performClick:` with the menu attached must open the menu, not re-send `statusItemClicked:`.
  - Which Run at Startup mechanism is used (SMAppService or the LaunchAgent fallback) on the user's Mac.
- **LaunchAgent fallback: tick vs "Allow in the Background".** If Cascade uses the LaunchAgent and the user switches it off in System Settings, the plist still exists and the menu still shows a tick. `launchctl print-disabled gui/$UID` may expose that state; not verified.
- **Applet property write-back on quit.** Stay-open applets save top-level properties into `main.scpt` on quit, which could invalidate the ad-hoc signature. `on quit` clears the AppKit-object properties; QA A8 checks that the signature still verifies after a quit.

## Ideas (not requested)

- Developer ID signing and notarization, so the DMG opens on other Macs without "Open Anyway" (needs a paid Apple Developer account).
- LaunchAgent uses the app's path when enabled; moving the app afterwards needs Run at Startup toggled off and on.
- Per-app filter or "only this display" toggle in the picker.
- Option to cascade toward the bottom-right instead of top-left, or to centre the cascade block on the display.
- Sort the checklist by app name, or group rows under app headers.
- Restore previous window positions (undo) by writing the pre-cascade frames to a temp file.
- A global hotkey without the Shortcuts app, e.g. a tiny Swift/Hammerspoon wrapper. Out of scope unless the user asks.
- Skip windows that are minimized or on another Space; currently they are listed and the AX calls simply fail into the summary.

## Known limitations

- Windows with identical titles inside the same app fall back to index-based lookup, which is correct only if no window in that app was raised out of order.
- Apps that ignore accessibility resize (fixed-size windows) still get moved; they appear in the summary as a resize failure, which is expected rather than a bug.
- Full-screen (Spaces) windows cannot be moved by System Events and will be reported as failures.
