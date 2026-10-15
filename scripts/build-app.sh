#!/bin/zsh
# Builds a release Refs.app into build/.
#
# Prefers a "Developer ID Application" identity, then "Apple Development", then ad-hoc signing.
# A stable identity matters: macOS ties Screen Recording and Automation
# permissions to it, so ad-hoc builds lose their permissions on every rebuild.
# Override with REFS_SIGN_IDENTITY="..." (use "-" for ad-hoc).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
APP="$ROOT/build/Refs.app"

./scripts/build-icon.sh

swift build -c release --arch arm64 --product Refs
swift build -c release --arch arm64 --product refs-mcp
BIN=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/Refs.icns "$APP/Contents/Resources/Refs.icns"
cp build/Assets.car "$APP/Contents/Resources/Assets.car"
cp "$BIN/Refs" "$APP/Contents/MacOS/Refs"
cp "$BIN/refs-mcp" "$APP/Contents/MacOS/refs-mcp"
strip -x "$APP/Contents/MacOS/Refs" "$APP/Contents/MacOS/refs-mcp"

IDENTITY=${REFS_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F '"' '
      /"Developer ID Application:/ && !release { release = $2 }
      /"Apple Development:/ && !development { development = $2 }
      END { print release ? release : development }
    ')}
IDENTITY=${IDENTITY:--}

# Developer ID signatures need a secure timestamp for notarization.
REFS_TIMESTAMP=--timestamp
if [[ "$IDENTITY" == "-" ]]; then
  REFS_TIMESTAMP=--timestamp=none
fi

# Sign the helper first, then the app, both with the hardened runtime.
codesign --force --options runtime "$REFS_TIMESTAMP" --sign "$IDENTITY" \
  --identifier com.karolchudzik.refs.mcp "$APP/Contents/MacOS/refs-mcp"
codesign --force --options runtime "$REFS_TIMESTAMP" --sign "$IDENTITY" \
  --entitlements Resources/Refs.entitlements "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signed with: $IDENTITY)"
du -sh "$APP"
