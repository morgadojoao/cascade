# QA v7

Build under test: `builds/Cascade-1.0.dmg` / `Cascade.app` 1.0 from commit `322702f` (code review fixes) onward. Cases are defined in `docs/PLAN_v7.md` section 5; A8 was added after the code review.

## Automated

| ID | Check | Result | Notes |
|----|-------|--------|-------|
| A1 | Compile, ASCII, `zsh -n` on every script | PASS | `shellcheck` not installed, skipped. ASCII guard in `build_app.sh` tested with an injected `≥`: build refused, line printed. |
| A2 | `builds/Cascade.app`: `LSUIElement` true, `OSAAppletStayOpen` true, id `com.morgadoj.cascade`, version 1.0, `codesign --verify --deep --strict` OK, `applet.icns` present, no `Assets.car` | PASS | |
| A3 | Saved size via `osascript` calling the handlers | PASS | Nothing saved -> 1200x800; 1500x900 round-trips; `garbage` and `50x50` -> 1200x800; parse accepts `1200 x 800`, `1200,800`, rejects `abc`. |
| A4 | `cascadeAll()` in the running app via Apple Events | PENDING | Needs v7 installed in /Applications and your Automation approval. |
| A5 | Run at Startup toggled through the handlers, confirmed with `sfltool dumpbtm` / the LaunchAgent plist | PENDING | Sandbox won't register login items from here; covered by M8. |
| A6 | DMG: `hdiutil verify`; contains `Cascade.app` (valid signature), `Applications` symlink, `.background/background.tiff`, `.DS_Store` layout, `.VolumeIcon.icns` with the volume's custom-icon flag | PASS | Volume icon was missing at first (Finder deleted it); fixed by writing it after the layout step. |
| A7 | `make_installer.command` twice in a row | PASS | Also re-run after the review fixes. |
| A8 | After Quit, `codesign --verify --deep --strict /Applications/Cascade.app` still passes (applet property write-back) | PENDING | Needs v7 installed. |

## Manual (you)

| ID | Check | Result | Notes |
|----|-------|--------|-------|
| M1 | Fresh install from the DMG, launch, grant Accessibility | | |
| M2 | Single click: menu after a short pause | | |
| M3 | Right-click and Control-click: menu immediately | | |
| M4 | Double-click: everything cascades at the saved size, no menu or dialog | | |
| M5 | Select Windows...: in front, size pre-filled, All / None / Return / Escape, cascade works | | |
| M6 | Size...: `abc` and `50x50` rejected with hint; valid size saved, menu title updates, double-click uses it; Cancel changes nothing | | |
| M7 | Size survives Quit and relaunch | | |
| M8 | Run at Startup on -> log out/in -> Cascade in menu bar; off -> log out/in -> not. Tick matches Login Items | | |
| M9 | Two displays: each gets its own cascade | | |
| M10 | Claude / Teams cascade, or appear in the failure summary with a reason | | |
| M11 | Quit Cascade quits; relaunch restores the icon | | |
| M12 | Launching again while running opens the picker | | |
