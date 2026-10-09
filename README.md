# Refs

A lightweight macOS menu-bar app for saving UI screenshots as design references. Each capture records
the app or website it came from and one line about what you like, and coding agents can read the
library over MCP.

## Build

Requires macOS 14+, Xcode 16+ (Swift 6 toolchain) on Apple Silicon.

```sh
swift test                 # core and MCP tests
./scripts/build-app.sh     # builds and signs build/Refs.app
open build/Refs.app
```

The script signs with your first Apple Development or Developer ID identity. Keep the same identity
between builds: macOS ties Screen Recording and browser Automation permissions to it.

## Use

- **⌘⇧2** captures an area, **⌘⇧3** a window. Space switches between the two while selecting, and Esc cancels.
- After capturing, type what you like and press Return. Esc discards.
- The library groups references by app (native apps) and website (browser captures).

⌘⇧3 is also macOS's "Save picture of screen" shortcut. Turn that off in System Settings › Keyboard ›
Keyboard Shortcuts › Screenshots, or pick another shortcut in Refs' Settings.

Permissions (a setup window walks through both on first launch):
- **Screen Recording** is required. Quit and reopen Refs after granting it.
- **Automation**, once per browser, to read the URL and title of the active tab. "Allow All Browsers"
  asks each installed browser in turn. Any browser with Safari- or Chrome-style tab scripting works
  (Safari, Chrome, Arc, Helium, Brave, Edge and other Chromium forks). Firefox and Zen don't support it,
  so captures from them record the window title only.

## Agents (MCP)

`Refs.app/Contents/MacOS/refs-mcp` is a read-only stdio MCP server. It reads the library folder directly,
so it works even when the app isn't running. Settings › Agents shows the exact setup for Claude Code,
Codex, Cursor and Claude Desktop, for example:

```sh
claude mcp add --scope user refs -- /Applications/Refs.app/Contents/MacOS/refs-mcp
```

Tools: `list_references(query?, app?, site?, limit?)`, `get_reference(id, include_image?, max_size?)`,
`list_sources()`.

## Storage

`~/Library/Application Support/Refs/Library/`, as `<id>.png` + `<id>.json` pairs. The folder can be changed
in Settings; `REFS_LIBRARY=/path` overrides it for both the app and the MCP helper.

## Layout

- `Sources/RefsCore`: reference model, library store, search, image coding
- `Sources/RefsMCP`, `Sources/refs-mcp`: MCP server and its stdio entry point
- `Sources/Refs`: the app (AppKit + SwiftUI)
- `mocks/`, `spikes/`: v1 UI mocks and research notes
