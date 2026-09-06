#!/bin/zsh
# Build build/PixelPet.saver — the screen-saver bundle. Shares Design/ and the settings model with the app.
set -e
cd "$(dirname "$0")"
OUT=build/PixelPet.saver
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
swiftc -O -emit-library -module-name PixelPetSaver \
  -o "$OUT/Contents/MacOS/PixelPet" \
  Saver/PetSaverView.swift Saver/Globals.swift \
  Engine/Core/Log.swift Engine/Core/Settings.swift \
  $(find Design -name "*.swift" | sort) \
  -framework AppKit -framework ScreenSaver
cp Saver/Info.plist "$OUT/Contents/Info.plist"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "PixelPet Dev"; then
  codesign --force --sign "PixelPet Dev" --identifier com.soumil.pixelpet.saver "$OUT"
else
  codesign --force --sign - "$OUT" 2>/dev/null || true
fi
echo "built $OUT"
