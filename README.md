# Cascade

A small macOS app that tidies your windows. Click the icon, tick the windows you want, enter a size, and press **Cascade**. The windows are resized and stacked diagonally from the top-left corner of the display each one is already on.

## Install

1. Double-click `scripts/build.command`, or run it from Terminal:
   ```bash
   ./scripts/build.command
   ```
   This builds `~/Applications/Cascade.app` and launches it.
2. Allow **Cascade** in System Settings > Privacy & Security > Accessibility, then launch it again.
3. Drag `Cascade.app` to your Dock for one-click access.

## Use

- All open windows are listed and ticked. Use **All** / **None** to change the selection quickly.
- Size is `width x height`, e.g. `1200x800` (`1200 x 800` and `1200,800` also work).
- Each display gets its own cascade. Windows are never made larger than their display.
- If a window can't be moved or resized, a summary at the end says which one and why.

## Customise

Edit the properties at the top of `cascade.applescript` (`defaultSize`, `stepX`, `stepY`, `marginX`, `marginY`) and rebuild. To change the icon, edit `scripts/make_icon.swift` and run `swift scripts/make_icon.swift`.

## Troubleshooting

- **Nothing moves:** the app needs Accessibility permission. After rebuilding, switch it off and on again in System Settings.
- **Build fails with a syntax error:** a non-ASCII character got into the source, usually from saving in Script Editor. See `docs/APPLESCRIPT_GOTCHAS.md`.

Developers: start with `CLAUDE.md` and `docs/`.
