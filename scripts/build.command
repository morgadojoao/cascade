#!/bin/zsh
# Dev loop: builds Cascade.app, installs it into /Applications, launches it.
# Double-click this file in Finder, or run ./scripts/build.command.
# For a DMG to hand to someone, use make_installer.command instead.

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.morgadoj.cascade"
DEST="/Applications/Cascade.app"

finish() {
  # Only wait for a key when opened from Finder (no TTY in automation)
  if [[ -t 0 ]]; then read -k 1 "?$1 Press any key to close this window..."; echo; fi
}
trap 'finish "Build failed."' ERR

./scripts/build_app.sh
BUILT="builds/Cascade.app"

# Quit a running copy (it stays open in the menu bar) before replacing it
if pgrep -f "Cascade.app/Contents/MacOS/applet" >/dev/null; then
  echo "Quitting the running copy ..."
  osascript -e 'tell application id "'"$BUNDLE_ID"'" to quit' 2>/dev/null || true
  sleep 1
fi

echo "Installing to $DEST ..."
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

# The app is signed ad hoc, so macOS ties the Accessibility grant to this exact
# binary. After a rebuild the old grant still shows as "on" but no longer
# applies. Clear it so the new build asks for permission again. This also
# clears the grant of a copy installed from the DMG (same bundle id).
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

# Make Finder and Spotlight pick up the new icon and version
touch "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true

echo ""
echo "Installed: $DEST"
echo ""
if [[ -d "$HOME/Applications/Cascade.app" ]]; then
  echo "Warning: an old copy is still in ~/Applications. Quit it and remove it:"
  echo "  rm -rf ~/Applications/Cascade.app"
  echo ""
fi
echo "Launching it now. Every build needs Accessibility permission again:"
echo "right-click the menu bar icon > Select Windows..., allow Cascade when asked"
echo "(System Settings > Privacy & Security > Accessibility), then try again."
echo ""

open "$DEST"

trap - ERR
finish "Done."
