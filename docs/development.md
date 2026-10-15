# Build Refs from source

[← Back to Refs](../README.md)

Run the commands below from the repository root.

Requires macOS 14+, Xcode 26+ (Swift 6 toolchain and Icon Composer asset compiler) on Apple Silicon.

```sh
swift test                 # core and MCP tests
./scripts/build-app.sh     # builds and signs build/Refs.app
open build/Refs.app
```

The script signs with your first Apple Development or Developer ID identity. Keep the same identity
between builds: macOS ties Screen Recording and browser Automation permissions to it.

The app icon uses the selected hand-shaded Quote direction. Editable light and dark masters
are `Resources/AppIcon-light.svg`, `Resources/AppIcon.svg` and their `.vectorcraft` counterparts.
The dark tile uses a neutral gray gradient matched to the Icon Composer rendition.
`Resources/Refs.icon` packages PNG renders of that approved artwork for Default and Dark,
plus separate opaque white vector quotes for Clear/Mono. The authored depth is retained;
Composer supplies appearance switching and the Clear container rather than repainting the faces.
`scripts/build-icon.sh` compiles `Refs.icns` and `Assets.car`, which are included before signing.
Regular app builds do not require VectorCraft.

## Repository layout

- `Sources/RefsCore`: reference model, library store, search, image coding
- `Sources/RefsMCP`, `Sources/refs-mcp`: MCP server and its stdio entry point
- `Sources/Refs`: the app (AppKit + SwiftUI)
- `mocks/`, `spikes/`: v1 UI mocks and research notes
