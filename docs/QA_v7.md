# QA v7

Build under test: `builds/Cascade-1.0.dmg` / `Cascade.app` 1.0 from commit `322702f` (code review fixes) onward. Cases are defined in `docs/PLAN_v7.md` section 5; A8 was added after the code review.

Result 2026-09-28: **all cases pass.**

## Automated

| ID | Check | Result | Notes |
|----|-------|--------|-------|
| A1 | Compile, ASCII, `zsh -n` on every script | PASS | `shellcheck` not installed, skipped. ASCII guard in `build_app.sh` tested with an injected `≥`: build refused, line printed. |
| A2 | `builds/Cascade.app`: `LSUIElement` true, `OSAAppletStayOpen` true, id `com.morgadoj.cascade`, version 1.0, `codesign --verify --deep --strict` OK, `applet.icns` present, no `Assets.car` | PASS | |
| A3 | Saved size via `osascript` calling the handlers | PASS | Nothing saved -> 1200x800; 1500x900 round-trips; `garbage` and `50x50` -> 1200x800; parse accepts `1200 x 800`, `1200,800`, rejects `abc`. |
| A4 | `cascadeAll()` in the running app via Apple Events | PASS | Run by the user. |
| A5 | Run at Startup toggled through the handlers, confirmed with `sfltool dumpbtm` / the LaunchAgent plist | PASS (via M8) | No LaunchAgent plist written, so SMAppService registered the login item; the fallback was not needed. |
| A6 | DMG: `hdiutil verify`; contains `Cascade.app` (valid signature), `Applications` symlink, `.background/background.tiff`, `.DS_Store` layout, `.VolumeIcon.icns` with the volume's custom-icon flag | PASS | Volume icon was missing at first (Finder deleted it); fixed by writing it after the layout step. |
| A7 | `make_installer.command` twice in a row | PASS | Also re-run after the review fixes. |
| A8 | After Quit, `codesign --verify --deep --strict` on the installed app still passes (applet property write-back) | PASS | Installed in `~/Applications`. After quit: valid on disk, satisfies its Designated Requirement, `main.scpt` byte-identical to the build. The user's first attempt pointed at `/Applications`, where no copy existed. |

## Manual (you)

| ID | Check | Result | Notes |
|----|-------|--------|-------|
| M1 | Fresh install from the DMG, launch, grant Accessibility | PASS | Installed to `~/Applications` rather than `/Applications`; works the same. |
| M2 | Single click: menu after a short pause | PASS | |
| M3 | Right-click and Control-click: menu immediately | PASS | |
| M4 | Double-click: everything cascades at the saved size, no menu or dialog | PASS | |
| M5 | Select Windows...: in front, size pre-filled, All / None / Return / Escape, cascade works | PASS | |
| M6 | Size...: `abc` and `50x50` rejected with hint; valid size saved, menu title updates, double-click uses it; Cancel changes nothing | PASS | |
| M7 | Size survives Quit and relaunch | PASS | |
| M8 | Run at Startup on -> log out/in -> Cascade in menu bar; off -> log out/in -> not. Tick matches Login Items | PASS | |
| M9 | Two displays: each gets its own cascade | PASS | |
| M10 | Claude / Teams cascade, or appear in the failure summary with a reason | PASS | |
| M11 | Quit Cascade quits; relaunch restores the icon | PASS | |
| M12 | Launching again while running opens the picker | PASS | |
