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
sleep 0.5
nohup "$DEST/PixelPet.app/Contents/MacOS/PixelPet" >/dev/null 2>&1 &   # direct launch: `open` can fail with -600 right after a replace
echo "Installed to $DEST/PixelPet.app and launched. Turn on 'Launch at login' in Preferences > App."
