#!/bin/bash
set -e
cd "$(dirname "$0")"

swift build -c release

APP=Keys.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Keys "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp Sources/Keys/Resources/*.png Sources/Keys/Resources/*.icns "$APP/Contents/Resources/" 2>/dev/null || true
touch "$APP"

# Sign if certificate exists
if security find-identity -v | grep -q "Keys Signing"; then
    codesign --force --deep --sign "Keys Signing" "$APP"
    echo "==> Built and signed Keys.app"
else
    codesign --force --sign - "$APP"
    echo "==> Built Keys.app (ad-hoc signed)"
fi

rm -rf /Applications/Keys.app
mv "$APP" /Applications/
open /Applications/Keys.app
