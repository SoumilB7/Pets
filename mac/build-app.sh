#!/bin/zsh
# Build PixelPet.app (a real bundle: icon, Info.plist, no dock icon) into build/.
set -e
cd "$(dirname "$0")"
APP=build/PixelPet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/PixelPet" \
  $(find Engine Design -name "*.swift" | sort) \
  -framework AppKit -framework ServiceManagement
python3 tools/make-icon.py >/dev/null
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PixelPet</string>
  <key>CFBundleDisplayName</key><string>PixelPet</string>
  <key>CFBundleIdentifier</key><string>com.soumil.pixelpet</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleExecutable</key><string>PixelPet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>A tiny pixel pet that lives on your windows.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
# Stable identity keeps the Accessibility grant across rebuilds (tools/make-signing-cert.sh creates it).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "PixelPet Dev"; then
  codesign --force --sign "PixelPet Dev" --identifier com.soumil.pixelpet "$APP" && echo "signed with PixelPet Dev"
else
  codesign --force --sign - "$APP" 2>/dev/null || true
  echo "ad-hoc signed (run tools/make-signing-cert.sh once for a stable identity)"
fi
echo "built $APP"
