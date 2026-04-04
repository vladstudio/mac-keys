#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP=/tmp/Keys.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp .build/release/Keys "$APP/Contents/MacOS/"
cp Sources/Keys/Resources/*.png Sources/Keys/Resources/*.icns "$APP/Contents/Resources/" 2>/dev/null || true
codesign --force --options runtime --entitlements Keys.entitlements \
  --sign "Apple Development: vlad@vlad.studio (8BFN33K4YK)" "$APP"

pkill -x Keys 2>/dev/null || true
rm -rf /Applications/Keys.app
mv "$APP" /Applications/
touch /Applications/Keys.app
open /Applications/Keys.app
echo "==> Installed Keys.app"
