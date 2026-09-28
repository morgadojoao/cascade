#!/bin/zsh
# Builds builds/Cascade.app from cascade.applescript. Non-interactive; used by
# build.command (dev loop) and make_installer.command (DMG).
#
#   ./scripts/build_app.sh        -> prints the path of the built app on the last line

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0"
BUNDLE_ID="com.morgadoj.cascade"   # must match appBundleId in cascade.applescript
SRC="cascade.applescript"
ICON="assets/Cascade.icns"
OUT_DIR="builds"
APP="$OUT_DIR/Cascade.app"
PLIST="$APP/Contents/Info.plist"

[[ -f "$SRC" ]] || { echo "error: $SRC not found" >&2; exit 1; }

# Refuse to build a file Script Editor has touched (see docs/APPLESCRIPT_GOTCHAS.md)
if perl -ne 'print "$.: $_" if /[^\x00-\x7F]/' "$SRC" | grep -q .; then
  echo "error: $SRC contains non-ASCII characters on these lines:" >&2
  perl -ne 'print "$.: $_" if /[^\x00-\x7F]/' "$SRC" >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  echo "Rendering icon ..."
  swift scripts/make_icon.swift
fi

mkdir -p "$OUT_DIR"
rm -rf "$APP"

echo "Compiling $SRC ..."
# -s = stay-open applet, so it keeps running in the menu bar
osacompile -s -o "$APP" "$SRC"

# Custom icon. osacompile ships its default icon in Assets.car, which macOS
# prefers over applet.icns, so drop it and point Info.plist at the .icns.
cp "$ICON" "$APP/Contents/Resources/applet.icns"
rm -f "$APP/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile applet" "$PLIST"

# Set a plist key, adding it if osacompile didn't write it
plist_set() {  # key type value
  /usr/libexec/PlistBuddy -c "Set :$1 $3" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"
}
plist_set CFBundleIdentifier string "$BUNDLE_ID"
plist_set CFBundleName string Cascade
plist_set CFBundleDisplayName string Cascade
plist_set CFBundleShortVersionString string "$VERSION"
plist_set CFBundleVersion string "$VERSION"
# Menu bar app: no Dock icon. The script checks this flag to decide whether to
# install its menu bar item or just open the picker once.
plist_set LSUIElement bool true

# Editing the bundle broke osacompile's ad-hoc signature; re-sign it.
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $APP (version $VERSION)"
echo "$APP"
