#!/bin/bash
set -e

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL=$(curl -sL https://api.github.com/repos/vladstudio/mac-keys/releases/latest \
  | grep browser_download_url | head -1 | cut -d'"' -f4)
curl -sL "$URL" -o "$TMP/Keys.zip"
unzip -q "$TMP/Keys.zip" -d "$TMP"

pkill -x Keys 2>/dev/null || true
rm -rf /Applications/Keys.app
mv "$TMP/Keys.app" /Applications/
open /Applications/Keys.app
echo "==> Installed Keys"
