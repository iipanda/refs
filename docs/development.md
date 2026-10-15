# Build Refs from source

[← Back to Refs](../README.md)

Run the commands below from the repository root.

Requires macOS 14+, Xcode 26+ (Swift 6 toolchain and Icon Composer asset compiler) on Apple Silicon.

```sh
swift test                 # core and MCP tests
./scripts/build-app.sh     # builds and signs build/Refs.app
open build/Refs.app
```

The script prefers a Developer ID Application identity, then falls back to Apple Development or
ad-hoc signing. Override it with `REFS_SIGN_IDENTITY="..."`. Certificate-based signatures include
a secure timestamp and need network access. Keep the same identity between builds: macOS ties
Screen Recording and browser Automation permissions to it.

The app icon uses the selected hand-shaded Quote direction. Editable light and dark masters
are `Resources/AppIcon-light.svg`, `Resources/AppIcon.svg` and their `.vectorcraft` counterparts.
The dark tile uses a neutral gray gradient matched to the Icon Composer rendition.
`Resources/Refs.icon` packages PNG renders of that approved artwork for Default and Dark,
plus separate opaque white vector quotes for Clear/Mono. The authored depth is retained;
Composer supplies appearance switching and the Clear container rather than repainting the faces.
`scripts/build-icon.sh` compiles `Refs.icns` and `Assets.car`, which are included before signing.
Regular app builds do not require VectorCraft.

## Package a disk image

After exporting the notarized app from Xcode to `build/Refs-notarized/Refs.app`:

```sh
python3 -m venv build/dmg-tools
build/dmg-tools/bin/python -m pip install -r Resources/DMG/requirements.txt
build/dmg-tools/bin/python scripts/package-dmg.py
```

This writes `build/Refs-macOS.dmg`, signed with the app's Developer ID certificate.
The layout is in `scripts/package-dmg.py`; its Retina background is drawn by
`Resources/DMG/background.swift`. Submit the finished DMG for notarization and staple
its ticket before publishing it.

## Repository layout

- `Sources/RefsCore`: reference model, library store, search, image coding
- `Sources/RefsMCP`, `Sources/refs-mcp`: MCP server and its stdio entry point
- `Sources/Refs`: the app (AppKit + SwiftUI)
- `mocks/`, `spikes/`: v1 UI mocks and research notes
