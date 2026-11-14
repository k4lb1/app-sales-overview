#!/bin/zsh
# Archives a Release build (the store bundle ID) and uploads it to App Store Connect, where it
# shows up in TestFlight. Uses the Apple ID signed in to Xcode.
# Usage: scripts/upload.sh <build>            archive and upload
#        scripts/upload.sh <build> --archive  archive only (registers the App ID on first use)
set -euo pipefail
cd "${0:A:h}/.."
BUILD=${1:?give the build number, e.g. scripts/upload.sh 2}
DD=~/Library/Developer/Xcode/DerivedData/AppSales
OUT=$(mktemp -d -t AppSales-upload)

if ! xcodebuild -project AppSales.xcodeproj -scheme AppSales -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DD" -archivePath "$OUT/AppSales.xcarchive" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive > "$OUT/archive.log" 2>&1; then
  grep -E "error:" "$OUT/archive.log" | sort -u | tail -5
  echo "ARCHIVE FAILED, Log: $OUT/archive.log"
  exit 1
fi
echo "Archive ok (build $BUILD)"
[[ ${2:-} == --archive ]] && exit 0

cat > "$OUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>H996R3Y4C5</string>
</dict>
</plist>
PLIST

if ! xcodebuild -exportArchive -archivePath "$OUT/AppSales.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/export" -allowProvisioningUpdates > "$OUT/upload.log" 2>&1; then
  grep -E "error" "$OUT/upload.log" | tail -5
  echo "UPLOAD FAILED, Log: $OUT/upload.log"
  exit 1
fi
echo "Uploaded. App Store Connect is processing the build (usually 5 to 30 minutes)."
