#!/bin/bash
# Builds a Release copy of Disk Map and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project DiskMap.xcodeproj -scheme DiskMap -configuration Release \
  -derivedDataPath build/DerivedData build | grep -E "error|warning: |BUILD" || true
APP="build/DerivedData/Build/Products/Release/Disk Map.app"
[ -d "$APP" ] || { echo "Build failed"; exit 1; }
rm -rf "/Applications/Disk Map.app"
cp -R "$APP" /Applications/
# Keep the build copy out of Launchpad and Spotlight so only the installed app shows up.
"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -u "$APP" 2>/dev/null || true
echo "Installed to /Applications/Disk Map.app"
