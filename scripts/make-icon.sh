#!/usr/bin/env bash
# Render the app icon and build the AppIcon.appiconset (all macOS sizes).
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="/tmp/snapkeep-icon-1024.png"
SET="Sources/Assets.xcassets/AppIcon.appiconset"

echo "→ Rendering base icon…"
swift scripts/render_icon.swift "$BASE"

mkdir -p "$SET"

# size:filename pairs for the macOS icon set
gen() { sips -z "$1" "$1" "$BASE" --out "$SET/$2" >/dev/null; }
gen 16   icon_16.png
gen 32   icon_16@2x.png
gen 32   icon_32.png
gen 64   icon_32@2x.png
gen 128  icon_128.png
gen 256  icon_128@2x.png
gen 256  icon_256.png
gen 512  icon_256@2x.png
gen 512  icon_512.png
cp "$BASE" "$SET/icon_512@2x.png" # 1024

cat > "$SET/Contents.json" <<'EOF'
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16@2x.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512@2x.png", "scale" : "2x" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
EOF

echo "✓ Built $SET"
