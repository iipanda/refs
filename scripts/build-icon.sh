#!/bin/zsh
# Compile the approved Quote artwork with native Default and Dark appearances.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
REFS_ICON_OUTPUT=$(mktemp -d "$PWD/build/refs-icon.XXXXXX")
trap 'rm -rf "$REFS_ICON_OUTPUT"' EXIT
xcrun actool Resources/Refs.icon \
  --compile "$REFS_ICON_OUTPUT" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon Refs \
  --output-partial-info-plist "$REFS_ICON_OUTPUT/icon-info.plist" \
  --output-format human-readable-text

# actool can report an export warning while returning success. Require both outputs.
[[ -s "$REFS_ICON_OUTPUT/Refs.icns" && -s "$REFS_ICON_OUTPUT/Assets.car" ]] || {
  echo "Icon compilation did not produce Refs.icns and Assets.car" >&2
  exit 1
}
cp "$REFS_ICON_OUTPUT/Refs.icns" "$REFS_ICON_OUTPUT/Assets.car" "$REFS_ICON_OUTPUT/icon-info.plist" build/
echo "Built build/Refs.icns and build/Assets.car"
