#!/usr/bin/env bash
#
# Build a distributable md-fire.dmg from a Release build of the app.
#
# Usage:
#   make dmg              # builds Release, then packages (recommended)
#   scripts/make-dmg.sh   # packages an already-built Release app
#
# The DMG contains the app, an /Applications symlink (drag-to-install), and a
# Russian install/description note shown the moment the disk image is mounted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build-release/Build/Products/Release/md-fire.app"
STAGE="$ROOT/dist/dmg-stage"
DMG="$ROOT/md-fire.dmg"
VOL="md-fire"
NOTE="📕 Установка — прочти меня.txt"

if [ ! -d "$APP" ]; then
  echo "✗ Release build not found: $APP"
  echo "  Build it first:"
  echo "    xcodebuild -project md-fire.xcodeproj -scheme md-fire \\"
  echo "      -configuration Release -derivedDataPath .build-release build"
  exit 1
fi

echo "▸ Staging DMG contents…"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/md-fire.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/scripts/dmg-readme.txt" "$STAGE/$NOTE"

echo "▸ Creating compressed disk image…"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

rm -rf "$STAGE"
echo "✓ Built $DMG ($(du -sh "$DMG" | cut -f1))"
