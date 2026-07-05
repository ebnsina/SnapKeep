#!/usr/bin/env bash
# Generate the Xcode project and build a release SnapKeep.app into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ xcodegen not found. Install it with: brew install xcodegen"
  exit 1
fi

echo "→ Generating Xcode project…"
xcodegen generate

echo "→ Building release…"
xcodebuild \
  -project SnapKeep.xcodeproj \
  -scheme SnapKeep \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/dd \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -3

mkdir -p build
rm -rf build/SnapKeep.app
cp -R .build/dd/Build/Products/Release/SnapKeep.app build/SnapKeep.app

echo "✓ Built build/SnapKeep.app — open it with:  open build/SnapKeep.app"
