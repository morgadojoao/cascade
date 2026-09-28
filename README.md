# Cascade

A small macOS menu bar app that tidies your windows. Double-click its icon in the menu bar and every open window is resized and stacked diagonally from the top-left corner of the display it is already on.

## Install

1. Open `Cascade-1.0.dmg` and drag **Cascade** onto **Applications**.
2. Launch Cascade from Applications, Launchpad or Spotlight. It appears in the menu bar (stacked-windows icon, near the clock) and has no Dock icon.
3. The first time you cascade, allow **Cascade** in System Settings > Privacy & Security > Accessibility, then try again.

The app is signed ad hoc, not with an Apple Developer ID. On a Mac other than the one that built it, macOS blocks the first launch: open System Settings > Privacy & Security and click **Open Anyway**.

## Use

| On the menu bar icon | What happens |
|---|---|
| Double-click | Cascades every window at the saved size, no dialog |
| Right-click or Control-click | Opens the menu |

The menu:

- **Select Windows...**: a checklist of every open window and a size field. Tick the ones you want (**All** / **None** help) and press **Cascade**. The size typed here is used for this cascade only.
- **Size (1200x800)...**: change the saved size used by double-click and pre-filled in Select Windows. Enter `width x height`, e.g. `1200x800` (`1200 x 800` and `1200,800` also work; minimum 100x100).
- **Run at Startup**: tick to start Cascade when you log in. A dash instead of a tick means macOS is waiting for you to allow it in System Settings > General > Login Items; clicking it opens that page.
- **Quit Cascade**.

Each display gets its own cascade. Windows are never made larger than their display. If a window can't be moved or resized, a summary at the end says which one and why.

## Build from source

```bash
./scripts/build.command
```
Builds, installs into `/Applications`, and launches (the dev loop; you re-allow Accessibility after every build).

```bash
./scripts/make_installer.command
```
Builds and packages `builds/Cascade-1.0.dmg`. The first run asks whether Terminal may control Finder (used to lay out the DMG window): click **Allow**.

Both can also be double-clicked in Finder. `scripts/build_app.sh` does the actual build into `builds/Cascade.app` and is used by both.

## Customise

Edit the properties at the top of `cascade.applescript` (`defaultSize` is the first-run size; `stepX`, `stepY`, `marginX`, `marginY` control the cascade) and rebuild. The version number is `VERSION` in `scripts/build_app.sh`. To change the icon, edit `scripts/make_icon.swift` and run `swift scripts/make_icon.swift`; the DMG background comes from `scripts/make_dmg_background.swift`.

## Troubleshooting

- **No menu bar icon:** the menu bar may be full (icons hide behind the notch). Quit a few other menu bar apps, or launch Cascade again, which opens Select Windows directly.
- **"No windows found" or nothing moves:** the app needs Accessibility permission. After rebuilding or reinstalling, remove Cascade from that list with the minus button and add it again.
- **Build fails with a non-ASCII or syntax error:** a special character got into the source, usually from saving in Script Editor. See `docs/APPLESCRIPT_GOTCHAS.md`.

Developers: start with `CLAUDE.md` and `docs/`.
