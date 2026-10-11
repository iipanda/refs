#!/bin/zsh
# Packages the selected icon master into the standard macOS size representations.
set -euo pipefail

cd "$(dirname "$0")/.."
REFS_ICON_MASTER="$PWD/Resources/AppIcon.png"
REFS_ICON_SET="$PWD/build/Refs.iconset"
mkdir -p "$REFS_ICON_SET"

for REFS_ICON_SIZE in 16 32 128 256 512; do
  sips -z "$REFS_ICON_SIZE" "$REFS_ICON_SIZE" "$REFS_ICON_MASTER" \
    --out "$REFS_ICON_SET/icon_${REFS_ICON_SIZE}x${REFS_ICON_SIZE}.png" >/dev/null
  REFS_ICON_RETINA_SIZE=$((REFS_ICON_SIZE * 2))
  sips -z "$REFS_ICON_RETINA_SIZE" "$REFS_ICON_RETINA_SIZE" "$REFS_ICON_MASTER" \
    --out "$REFS_ICON_SET/icon_${REFS_ICON_SIZE}x${REFS_ICON_SIZE}@2x.png" >/dev/null
done

iconutil --convert icns "$REFS_ICON_SET" --output "$PWD/build/Refs.icns"
echo "Built build/Refs.icns"
