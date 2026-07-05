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

# Sign with the stable self-signed dev identity if present, so macOS keeps the
# Screen Recording grant across rebuilds. Run ./scripts/make-dev-cert.sh once to set up.
IDENTITY="SnapKeep Dev"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" build/SnapKeep.app >/dev/null 2>&1 \
    && echo "✓ Signed with '$IDENTITY' (Screen Recording grant persists)."
else
  # No dev cert (e.g. CI): apply a *valid* ad-hoc signature so downloads show the
  # normal "unidentified developer" prompt instead of "damaged" (a broken seal).
  echo "ℹ︎  No '$IDENTITY' cert — applying an ad-hoc signature."
  codesign --force --deep --sign - build/SnapKeep.app >/dev/null 2>&1 \
    && echo "✓ Ad-hoc signed (Screen Recording grant resets each rebuild)."
  echo "   Run ./scripts/make-dev-cert.sh once for a stable dev identity."
fi

echo "✓ Built build/SnapKeep.app — open it with:  open build/SnapKeep.app"
