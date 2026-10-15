#!/bin/bash
# Builds a release binary and assembles an ad-hoc signed mac/build/Moneybook.app.
# Needs only the Command Line Tools (swift, sips, iconutil, codesign).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Moneybook.app
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

echo "==> swift build (release)"
swift build -c release --product Moneybook
BIN_DIR=$(swift build -c release --show-bin-path)

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Moneybook" "$APP/Contents/MacOS/Moneybook"

echo "==> icon"
ICON_WORK=build/icon
rm -rf "$ICON_WORK" && mkdir -p "$ICON_WORK/AppIcon.iconset"
swift scripts/make-icon.swift "$ICON_WORK/icon-1024.png" > /dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_WORK/icon-1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${s}x${s}.png" > /dev/null
  d=$((s * 2))
  sips -z $d $d "$ICON_WORK/icon-1024.png" --out "$ICON_WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Moneybook</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>app.moneybook.mac</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Moneybook</string>
  <key>CFBundleDisplayName</key><string>Moneybook</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <!-- Self-hosted servers on the LAN or localhost often use plain http. -->
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> codesign (ad-hoc)"
codesign --force --deep -s - "$APP"
codesign --verify --verbose=1 "$APP"
echo "Built $(pwd)/$APP"
