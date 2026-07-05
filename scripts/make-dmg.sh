#!/usr/bin/env bash
# Build a release SnapKeep.app and package it into a distributable .dmg with an
# Applications drop target. Output: build/SnapKeep-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/SnapKeep.app"
if [ ! -d "$APP" ]; then
  echo "→ No build yet — running bootstrap…"
  ./scripts/bootstrap.sh
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.1.0")
DMG="build/SnapKeep-$VERSION.dmg"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/SnapKeep.app"
ln -s /Applications "$STAGE/Applications"

echo "→ Building ${DMG} …"
rm -f "$DMG"
hdiutil create -volname "SnapKeep" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ $DMG"
echo "  Drag SnapKeep to Applications to install."
