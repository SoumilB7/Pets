#!/bin/zsh
# Build and install PixelPet.app into /Applications (falls back to ~/Applications).
set -e
cd "$(dirname "$0")"
./build-app.sh
pkill -x PixelPet 2>/dev/null || true
DEST=/Applications
[ -w "$DEST" ] || { DEST=~/Applications; mkdir -p "$DEST"; }
rm -rf "$DEST/PixelPet.app"
cp -R build/PixelPet.app "$DEST/PixelPet.app"
open "$DEST/PixelPet.app"
echo "Installed to $DEST/PixelPet.app and launched. Turn on 'Launch at login' in Preferences > App."
