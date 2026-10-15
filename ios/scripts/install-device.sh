#!/bin/sh
# Builds a Release copy and installs it on a connected iPhone (cable, or Wi-Fi once paired).
# Free Apple ID signing expires after 7 days; run this again to renew.
#   DEVICE   device name or UDID (default: the first paired physical iPhone)
set -e
cd "$(dirname "$0")/.."
./scripts/generate.sh
DEVICE="${DEVICE:-$(xcrun devicectl list devices --hide-default-columns --columns Identifier --columns Model --hide-headers 2>/dev/null \
  | awk '$0 !~ /simulated/ && /iPhone/ { print $1; exit }')}"
[ -n "$DEVICE" ] || { echo "No iPhone found. Connect it with a cable (or join the same Wi-Fi once paired)."; exit 1; }
xcodebuild -project Moneybook.xcodeproj -scheme MoneybookiOS -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath build/device -allowProvisioningUpdates -quiet build
xcrun devicectl device install app --device "$DEVICE" build/device/Build/Products/Release-iphoneos/Moneybook.app
echo "Installed on $DEVICE"
