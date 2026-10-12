#!/bin/zsh
# Builds the signed macOS app and packages the landing-page download.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
REFS_DOWNLOAD_DIR="$PWD/landing/downloads"
REFS_DOWNLOAD_ARCHIVE="$REFS_DOWNLOAD_DIR/Refs-macOS.zip"
mkdir -p "$REFS_DOWNLOAD_DIR"
ditto -c -k --sequesterRsrc --keepParent "$PWD/build/Refs.app" "$REFS_DOWNLOAD_ARCHIVE"
echo "Packaged $REFS_DOWNLOAD_ARCHIVE"
