#!/bin/bash
# Replace app icon from a single PNG source (generates adaptive icon)
# Usage: ./update-icon.sh <icon.png> [--bg COLOR]
#
# Examples:
#   ./update-icon.sh icon.png
#   ./update-icon.sh icon.png --bg "#1a1a1a"
set -e

cd "$(dirname "$0")"

SRC=""
BG="#111111"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bg) BG="$2"; shift 2 ;;
    -*) echo "Unknown option: $1"; exit 1 ;;
    *) SRC="$1"; shift ;;
  esac
done

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "Usage: $0 <icon.png> [--bg COLOR]"
  echo "  Provide a PNG file (512x512 recommended)"
  echo "  --bg   Background color for adaptive icon (default: #111111)"
  exit 1
fi

if ! command -v magick &>/dev/null; then
  echo "Error: ImageMagick not found (brew install imagemagick)"
  exit 1
fi

RES="app/src/main/res"

# Legacy icons (pre-Android 8)
magick "$SRC" -resize 48x48   "$RES/mipmap-mdpi/ic_launcher.png"
magick "$SRC" -resize 72x72   "$RES/mipmap-hdpi/ic_launcher.png"
magick "$SRC" -resize 96x96   "$RES/mipmap-xhdpi/ic_launcher.png"
magick "$SRC" -resize 144x144 "$RES/mipmap-xxhdpi/ic_launcher.png"
magick "$SRC" -resize 192x192 "$RES/mipmap-xxxhdpi/ic_launcher.png"

# Adaptive icon foreground (108dp canvas, icon scaled to 66% safe zone)
# mdpi=108, hdpi=162, xhdpi=216, xxhdpi=324, xxxhdpi=432
magick "$SRC" -resize 72x72 -gravity center -background none -extent 108x108 "$RES/mipmap-mdpi/ic_launcher_foreground.png"
magick "$SRC" -resize 108x108 -gravity center -background none -extent 162x162 "$RES/mipmap-hdpi/ic_launcher_foreground.png"
magick "$SRC" -resize 144x144 -gravity center -background none -extent 216x216 "$RES/mipmap-xhdpi/ic_launcher_foreground.png"
magick "$SRC" -resize 216x216 -gravity center -background none -extent 324x324 "$RES/mipmap-xxhdpi/ic_launcher_foreground.png"
magick "$SRC" -resize 288x288 -gravity center -background none -extent 432x432 "$RES/mipmap-xxxhdpi/ic_launcher_foreground.png"

# Adaptive icon XML
mkdir -p "$RES/mipmap-anydpi-v26"
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
EOF

# Update background color
COLORS="$RES/values/colors.xml"
if [ -f "$COLORS" ] && grep -q 'ic_launcher_background' "$COLORS"; then
  sed -i '' "s|<color name=\"ic_launcher_background\">.*</color>|<color name=\"ic_launcher_background\">$BG</color>|" "$COLORS"
elif [ -f "$COLORS" ]; then
  sed -i '' "s|</resources>|    <color name=\"ic_launcher_background\">$BG</color>\n</resources>|" "$COLORS"
fi

echo "Icon updated from $(basename "$SRC") (adaptive, bg=$BG)"
