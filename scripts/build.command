#!/bin/zsh
# Compiles cascade.applescript into ~/Applications/Cascade.app, gives it the
# custom icon (assets/Cascade.icns) and a bundle id, and launches it.
# Double-click this file in Finder to run it.

set -e
cd "$(dirname "$0")/.."

SRC="cascade.applescript"
ICON="assets/Cascade.icns"
DEST_DIR="$HOME/Applications"
APP="$DEST_DIR/Cascade.app"
BUNDLE_ID="com.morgadoj.cascade"

if [[ ! -f "$SRC" ]]; then
  echo "Couldn't find $SRC next to this script."
  echo "Put both files in the same folder and try again."
  read -k 1 "?Press any key to close..."
  exit 1
fi

mkdir -p "$DEST_DIR"

# Quit a running copy (it stays open in the menu bar) before replacing it
if pgrep -f "Cascade.app/Contents/MacOS/applet" >/dev/null; then
  osascript -e 'tell application id "'"$BUNDLE_ID"'" to quit' 2>/dev/null || true
  sleep 1
fi

# Remove any previous build so macOS doesn't get confused about permissions
if [[ -d "$APP" ]]; then
  echo "Replacing existing app at: $APP"
  rm -rf "$APP"
fi

echo "Compiling $SRC ..."
# -s = stay-open applet, so it keeps running in the menu bar
osacompile -s -o "$APP" "$SRC"

# Custom icon. osacompile ships its default icon in Assets.car, which macOS
# prefers over applet.icns, so drop it and point Info.plist at the .icns.
PLIST="$APP/Contents/Info.plist"
if [[ ! -f "$ICON" ]]; then
  echo "Rendering icon ..."
  swift scripts/make_icon.swift
fi
cp "$ICON" "$APP/Contents/Resources/applet.icns"
rm -f "$APP/Contents/Resources/Assets.car"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile applet" "$PLIST"

# Stable identity so macOS treats it like a normal app
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Cascade" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Cascade" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0" "$PLIST" 2>/dev/null || true

# Menu bar app: no Dock icon. The script checks this flag to decide whether to
# install its menu bar item or just cascade once.
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PLIST"

# Editing the bundle broke osacompile's ad-hoc signature; re-sign it.
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"

# The app is signed ad hoc, so macOS ties the Accessibility grant to this exact
# binary. After a rebuild the old grant still shows as "on" but no longer
# applies. Clear it so the new build asks for permission again.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

# Make Finder and the Dock pick up the new icon
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

echo ""
echo "Built: $APP"
echo ""
echo "Launching it now. Every build needs Accessibility permission again:"
echo "choose Cascade Windows... from the menu bar icon, allow Cascade when asked"
echo "(System Settings > Privacy & Security > Accessibility), then try again."
echo "To start it at login, add it in System Settings > General > Login Items."
echo ""

open "$APP"
open "$DEST_DIR"

read -k 1 "?Done. Press any key to close this window..."
