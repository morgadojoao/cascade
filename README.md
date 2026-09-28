# Cascade

A small macOS menu bar app that tidies your windows. Click its icon in the menu bar, choose **Cascade Windows...**, tick the windows you want, enter a size, and press **Cascade**. The windows are resized and stacked diagonally from the top-left corner of the display each one is already on.

## Install

1. Double-click `scripts/build.command`, or run it from Terminal:
   ```bash
   ./scripts/build.command
   ```
   This builds `~/Applications/Cascade.app` and launches it.
2. Allow **Cascade** in System Settings > Privacy & Security > Accessibility, then launch it again.
3. Cascade now sits in the menu bar (stacked-windows icon, near the clock) and has no Dock icon. Choose **Quit Cascade** from its menu to remove it.
4. To have it there after every restart, add `Cascade.app` in System Settings > General > Login Items.

## Use

- All open windows are listed and ticked. Use **All** / **None** to change the selection quickly.
- Size is `width x height`, e.g. `1200x800` (`1200 x 800` and `1200,800` also work).
- Each display gets its own cascade. Windows are never made larger than their display.
- If a window can't be moved or resized, a summary at the end says which one and why.

## Customise

Edit the properties at the top of `cascade.applescript` (`defaultSize`, `stepX`, `stepY`, `marginX`, `marginY`) and rebuild. To change the icon, edit `scripts/make_icon.swift` and run `swift scripts/make_icon.swift`.

## Troubleshooting

- **No menu bar icon:** the menu bar may be full (icons hide behind the notch). Quit a few other menu bar apps, or relaunch Cascade, which opens the picker directly.
- **Nothing moves:** the app needs Accessibility permission. After rebuilding, switch it off and on again in System Settings.
- **Build fails with a syntax error:** a non-ASCII character got into the source, usually from saving in Script Editor. See `docs/APPLESCRIPT_GOTCHAS.md`.

Developers: start with `CLAUDE.md` and `docs/`.
