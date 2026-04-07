#!/bin/bash
set -e
cd "$(dirname "$0")"
source ../scripts/build-kit.sh
build_app "Keys" \
  --resources "AppIcon.icns Sources/Keys/Resources/*.png" \
  --entitlements Keys.entitlements
