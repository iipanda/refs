#!/bin/zsh
# Builds a release Refs.app into build/.
#
# Signs with the first "Apple Development" or "Developer ID Application" identity in the keychain,
# or ad-hoc if there is none. A stable identity matters: macOS ties Screen Recording and Automation
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
  | grep -E '"(Developer ID Application|Apple Development):' | head -1 | sed -E 's/.*"(.*)"/\1/')}
IDENTITY=${IDENTITY:--}

# Sign the helper first, then the app, both with the hardened runtime.
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" \
  --identifier com.karolchudzik.refs.mcp "$APP/Contents/MacOS/refs-mcp"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" \
  --entitlements Resources/Refs.entitlements "$APP"
codesign --verify --strict "$APP"

echo "Built $APP (signed with: $IDENTITY)"
du -sh "$APP"
