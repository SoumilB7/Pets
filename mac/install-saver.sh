#!/bin/zsh
# Build the screen saver and install it for this user, then open the Screen Saver settings.
set -e
cd "$(dirname "$0")"
./make-saver.sh
DEST=~/Library/Screen\ Savers
mkdir -p "$DEST"
rm -rf "$DEST/PixelPet.saver"
cp -R build/PixelPet.saver "$DEST/PixelPet.saver"
echo "Installed to $DEST/PixelPet.saver"
echo "System Settings → Screen Saver → pick PixelPet (under Other). Set 'Start after' to when you want it."
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension" 2>/dev/null || open "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
