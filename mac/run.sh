#!/bin/zsh
# Dev loop: build the .app bundle and relaunch it from build/.
set -e
cd "$(dirname "$0")"
./build-app.sh
pkill -x PixelPet 2>/dev/null || true
sleep 0.3
nohup ./build/PixelPet.app/Contents/MacOS/PixelPet >/dev/null 2>&1 &
echo "PixelPet running. Stop with: pkill -x PixelPet"
