#!/bin/zsh
# Build PixelPet.app and wrap it in a drag-to-Applications disk image.
#   ./make-dmg.sh            → build/PixelPet-<version>.dmg
#   ./make-dmg.sh suffix     → build/PixelPet-<version>-suffix.dmg
set -e
cd "$(dirname "$0")"
./build-app.sh >/dev/null
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PixelPet.app/Contents/Info.plist)
NAME="PixelPet-$VER${1:+-$1}"
STAGE=build/dmg-stage
rm -rf "$STAGE" "build/$NAME.dmg"
mkdir -p "$STAGE"
cp -R build/PixelPet.app "$STAGE/PixelPet.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First launch.txt" <<TXT
PixelPet — first launch

1. Drag PixelPet into Applications.
2. The app is signed locally, not by Apple, so the first time macOS will refuse a double-click.
   Right-click (or Control-click) PixelPet in Applications and choose Open, then Open again.
   You only have to do this once.
3. Open PixelPet from the 🐾 menu-bar icon → Open PixelPet… for settings.
4. Window titles and page URLs need Accessibility access: System Settings → Privacy & Security
   → Accessibility → switch on PixelPet. Nothing leaves your Mac.

Stop it any time from the 🐾 menu → Quit PixelPet.
TXT
hdiutil create -quiet -volname "PixelPet" -srcfolder "$STAGE" -ov -format UDZO "build/$NAME.dmg"
rm -rf "$STAGE"
echo "build/$NAME.dmg ($(du -h "build/$NAME.dmg" | cut -f1))"
