#!/bin/bash
set -e
cd "$(dirname "$0")"

CURRENT=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
CURRENT=${CURRENT:-0.0}
VERSION=${1:-${CURRENT%.*}.$((${CURRENT##*.} + 1))}
echo "==> $CURRENT -> $VERSION"

plutil -replace CFBundleShortVersionString -string "$VERSION" Info.plist
plutil -replace CFBundleVersion -string "$VERSION" Info.plist

swift build -c release

APP=/tmp/Keys.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
cp .build/release/Keys "$APP/Contents/MacOS/"
cp Sources/Keys/Resources/*.png Sources/Keys/Resources/*.icns "$APP/Contents/Resources/" 2>/dev/null || true
codesign --force --options runtime --entitlements Keys.entitlements \
  --sign "Developer ID Application: CHANGE_ME (TEAM_ID)" "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" /tmp/Keys.zip
xcrun notarytool submit /tmp/Keys.zip \
  --apple-id "vlad@vlad.studio" --team-id "TEAM_ID" \
  --password "@keychain:AC_PASSWORD" --wait
xcrun stapler staple "$APP"

rm /tmp/Keys.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" /tmp/Keys.zip

git add Info.plist
git commit -m "v$VERSION"
git tag "v$VERSION"
git push --tags

gh release create "v$VERSION" /tmp/Keys.zip --title "v$VERSION" --notes ""
echo "==> Released v$VERSION"
