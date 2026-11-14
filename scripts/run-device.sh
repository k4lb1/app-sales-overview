#!/bin/zsh
# Builds the Debug app ("AppSales Dev", its own bundle ID next to the later store app) and starts it
# on the connected iPhone. Usage: scripts/run-device.sh [device-id]
set -euo pipefail
cd "${0:A:h}/.."
DD=~/Library/Developer/Xcode/DerivedData/AppSales
DEVICE=${1:-$(xcrun devicectl list devices 2>/dev/null | awk '(/connected/ || /available/) && /physical/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}
[[ -n $DEVICE ]] || { echo "No connected iPhone found."; exit 1; }

LOG=$(mktemp -t AppSales-build)
if ! xcodebuild -project AppSales.xcodeproj -scheme AppSales -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DD" -allowProvisioningUpdates build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | tail -5
  echo "BUILD FAILED, Log: $LOG"
  exit 1
fi
echo "Build ok"
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Debug-iphoneos/AppSales.app" > /dev/null
echo "Installed"
xcrun devicectl device process launch --device "$DEVICE" studio.oxdeploy.appsales.dev > /dev/null
echo "Launched"
