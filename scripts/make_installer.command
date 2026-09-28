#!/bin/zsh
# Builds Cascade.app and packages it as builds/Cascade-<version>.dmg: a disk
# image that opens a Finder window with the app, an arrow, and an Applications
# shortcut to drag it onto.
# Double-click this file in Finder, or run ./scripts/make_installer.command.
#
# The first run asks for permission for Terminal to control Finder (used to
# lay out the window). Click Allow.

set -euo pipefail
cd "$(dirname "$0")/.."

VOL_NAME="Cascade"
OUT_DIR="builds"
STAGE="$OUT_DIR/dmg-stage"
TMP_DMG="$OUT_DIR/Cascade-tmp.dmg"
BG_1X="assets/dmg_background.png"
BG_2X="assets/dmg_background@2x.png"
# Finder window content size and icon centres, in points from the window's
# top-left. They must match the arrow drawn by make_dmg_background.swift.
WIN_W=600
WIN_H=400
APP_X=150
APPS_X=450
ICON_Y=190

finish() {
  # Only wait for a key when opened from Finder (no TTY in automation)
  if [[ -t 0 ]]; then read -k 1 "?$1 Press any key to close this window..."; echo; fi
}
cleanup() {
  [[ -n "${MOUNT_DIR:-}" && -d "$MOUNT_DIR" ]] && hdiutil detach "$MOUNT_DIR" -force -quiet || true
  rm -rf "$STAGE" "$TMP_DMG"
}
trap 'cleanup; finish "Installer build failed."' ERR

# 1. Build the app
./scripts/build_app.sh
APP="$OUT_DIR/Cascade.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT_DIR/Cascade-$VERSION.dmg"

# 2. Background image (1x + 2x in one HiDPI TIFF so it is sharp on Retina)
if [[ ! -f "$BG_1X" || ! -f "$BG_2X" ]]; then
  echo "Rendering DMG background ..."
  swift scripts/make_dmg_background.swift
fi

# 3. Stage the contents
echo "Staging ..."
rm -rf "$STAGE" "$TMP_DMG" "$DMG"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Cascade.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$STAGE/.background/background.tiff" >/dev/null

# 4. Writable image, mounted, so Finder can store the window layout in it.
# A volume left mounted by an earlier failed run would get a different name
# ("Cascade 1"), so detach it first.
if [[ -d "/Volumes/$VOL_NAME" ]]; then
  echo "Detaching stale /Volumes/$VOL_NAME ..."
  hdiutil detach "/Volumes/$VOL_NAME" -force -quiet || true
fi
echo "Creating disk image ..."
hdiutil create -quiet -volname "$VOL_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP_DMG"
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | awk -F'\t' '/\/Volumes\// { print $NF }')
[[ -d "$MOUNT_DIR" ]] || { echo "error: couldn't mount $TMP_DMG" >&2; false; }
echo "Mounted at $MOUNT_DIR"
# Finder addresses the disk by its mounted name, which is only "Cascade" if no
# other volume of that name is mounted. Refuse to lay out the wrong one.
[[ "$MOUNT_DIR" == "/Volumes/$VOL_NAME" ]] || { echo "error: mounted as $MOUNT_DIR, not /Volumes/$VOL_NAME; eject the other \"$VOL_NAME\" volume and retry" >&2; false; }

# 5. Window layout: icon view, no toolbar, background, icon positions.
# Finder's bounds include the title bar, hence the extra height.
echo "Laying out the Finder window ..."
osascript <<APPLESCRIPT
tell application "Finder"
	tell disk "$VOL_NAME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 120, 200 + $WIN_W, 120 + $WIN_H + 28}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to 128
		set text size of viewOptions to 13
		set background picture of viewOptions to file ".background:background.tiff"
		set position of item "Cascade.app" of container window to {$APP_X, $ICON_Y}
		set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
		update without registering applications
		delay 1
		close
	end tell
end tell
APPLESCRIPT

# Give Finder time to write .DS_Store, then make sure nothing else is left behind
sleep 2

# 6. Volume icon (shown on the desktop and in the Finder sidebar). Done after
# the Finder step: Finder removes a .VolumeIcon.icns written before it.
cp assets/Cascade.icns "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR" 2>/dev/null || echo "note: SetFile not found; the volume keeps the default icon"
rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes" 2>/dev/null || true
sync
hdiutil detach "$MOUNT_DIR" -quiet || { sleep 2; hdiutil detach "$MOUNT_DIR" -force -quiet; }
MOUNT_DIR=""

# 7. Compress to the final read-only image
echo "Compressing ..."
hdiutil convert -quiet "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$STAGE" "$TMP_DMG"
hdiutil verify -quiet "$DMG"

trap - ERR
echo ""
echo "Installer: $DMG"
echo ""
echo "Open it and drag Cascade onto Applications. Signed ad hoc (no Apple"
echo "Developer ID): on another Mac, a downloaded copy has to be allowed once in"
echo "System Settings > Privacy & Security > Open Anyway."
echo ""
[[ -t 0 ]] && open "$OUT_DIR"
finish "Done."
