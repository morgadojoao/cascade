# AppleScript / AppleScriptObjC gotchas for this project

Everything here was learned by hitting the problem. Treat these as constraints, not suggestions.

## File encoding and Script Editor

Script Editor is not a plain text editor. When it saves a `.applescript` file it reformats the source (tabs, symbol operators) and writes non-ASCII symbols such as `≥` in **Mac Roman**, not UTF-8. The file then contains a byte that every other tool reads as invalid, and the next round trip turns it into U+FFFD, which the compiler reports as `Expected "then", etc. but found unknown token.`

Rules:

- Never save the source from Script Editor. Compile-check from the terminal instead: `osacompile -o /tmp/check.scpt cascade.applescript`.
- Write all comparisons in words: `is greater than or equal to`, `is less than or equal to`, `is not equal to`. Do not use `>=`, `<=`, `≠`, `≥`, `≤`.
- No em dashes, curly quotes, or other Unicode anywhere in the file, including comments.
- Verify before committing: `grep -nP '[^\x00-\x7F]' cascade.applescript` must print nothing.

## Threads

AppKit UI objects (`NSAlert`, `NSWindow`, any `NSView`) may only be created on the main thread or you get `NSWindow should only be instantiated on the main thread! (-10000)`.

- Script Editor's Run button uses a background thread. `osascript` and compiled applets use the main thread.
- Pattern used here: `my performSelectorOnMainThread:"handlerName:" withObject:(missing value) waitUntilDone:true`. The handler must be a top-level `on handlerName:arg` handler. It cannot return a value, so pass data through script `property` variables (`pickerLabels` in, `pickerResult` out).
- Wrap the main-thread handler body in `try` and show errors with `display alert` there; otherwise they disappear.

## NSRect shape

`NSScreen`'s `frame()` and `visibleFrame()` come back either as a record `{origin:{x:, y:}, size:{width:, height:}}` or as a nested list `{{x, y}, {w, h}}` depending on the macOS/AppleScript version. Always unpack through `rectParts()`, which handles both.

## Coordinate systems

- AppKit: origin bottom-left of the primary display, y increases upward. Secondary displays can have negative or large offsets.
- System Events (accessibility): origin top-left of the primary display, y increases downward.
- Conversion: `seTop = primaryHeight - (cocoaY + cocoaHeight)`; x is unchanged. Done once in `getScreens()`.
- Inside a plain `NSView` (not flipped), the first row goes at the largest y. Row `i` of `n` is at `y = (n - i) * rowH`. Use `docView's scrollPoint:{0, docHeight}` to show the top.

## System Events window handling

- Identify processes by `unix id`, not by `name`. Names like `MSTeams` or localized names do not always resolve with `tell process "Name"`.
- `perform action "AXRaise"` moves that window to index 1 in its process and shifts the others by one. If you must fall back to index lookup, add the number of already-raised windows in that app with a higher original index.
- Prefer `every window of proc whose name is theTitle` when the title is non-empty and unique.
- Electron apps (Claude desktop, Microsoft Teams) can reject `set size` while accepting `set position`, or need a second `set position` after the resize. Do position, size, position, each in its own `try`.
- Never use a bare `try ... end try` around a positioning call without recording the error. Collect failures and show them once at the end.
- Enumerate with `every application process whose background only is false and visible is true`. Hidden apps (Cmd-H) are excluded on purpose.

## NSAlert with an accessory view

- `theAlert's addButtonWithTitle:` order matters: first button is the default (Return) and `runModal()` returns 1000 for it; second button returns 1001 and a button titled "Cancel" gets Escape automatically.
- `setAccessoryView:` takes any `NSView`; size it explicitly with `initWithFrame:`. The alert grows to fit.
- Checkbox: `NSButton` with `setButtonType:3` (`NSButtonTypeSwitch`), state 1 = on, 0 = off. `setLineBreakMode:4` truncates long titles with an ellipsis.
- Push button: `setBezelStyle:1` (`NSBezelStyleRounded`).
- `setTarget:me` plus `setAction:"someHandler:"` works for handlers defined at the top level of the script; keep the controls they touch in a `property` so the handler can reach them.
- Re-running `runModal()` on the same alert instance preserves the accessory view's state (ticks, typed text), which is how validation retries work.

## Building and permissions

- `osacompile -o "Name.app" source.applescript` produces a standalone applet; no Xcode needed.
- The applet needs its own Accessibility grant. Rebuilding creates a new binary and macOS may need the permission toggled off and on in System Settings > Privacy & Security > Accessibility before positioning works again. Symptom of a missing grant: the picker appears but nothing moves and the failure summary is empty or reports "not allowed assistive access" (-1719/-25211).
