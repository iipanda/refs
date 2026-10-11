# Refs

A lightweight macOS menu-bar app for saving UI screenshots and videos as design references. Each capture records
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

The app icon uses the selected Quote direction. `Resources/AppIcon.png` is the dark icon master;
`scripts/build-icon.sh` packages its standard macOS sizes into `build/Refs.icns`, which the app build
includes before signing. The editable dark sources are `Resources/AppIcon.svg` and
`Resources/AppIcon.vectorcraft`; the light sources are `Resources/AppIcon-light.svg` and
`Resources/AppIcon-light.vectorcraft`. The PNG master keeps regular app builds independent of VectorCraft.

## Use

- **⌘⇧2** captures an area, **⌘⇧3** a window. Space switches between the two while selecting, and Esc cancels.
- **Record Area… / Record Window…** in the menu bar or File menu starts a silent video with the cursor visible. Select the source, then use the floating **Stop** button (or either capture shortcut) to finish. Videos are H.264 MP4 at up to 30 fps and 3840 pixels on the longest edge.
- Videos play in the save panel and Library inspector; double-click opens the movie in your default player. MCP supplies a poster frame and the movie path.
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

`Refs.app/Contents/MacOS/refs-mcp` is a stdio MCP server that reads and manages the library folder directly,
so it works even when the app isn't running. Settings › Agents shows the exact setup for Claude Code,
Codex, Cursor and Claude Desktop, for example:

```sh
claude mcp add --scope user refs -- /Applications/Refs.app/Contents/MacOS/refs-mcp
```

Tools:
- Read: `list_references(query?, app?, site?, limit?, kind?, cursor?, include_trashed?)`,
  `get_reference(id, include_image?, max_size?)`, `list_sources()`, `get_library_info()`.
- Add: `add_references(items: [{path, note?, title?, source?}])`. Supply 1–100 absolute local paths.
  PNG/JPEG/HEIC/WebP become PNG; MP4/MOV keep their container and receive a poster.
  Originals stay untouched. Identical media returns `existing` without overwriting metadata.
- Edit: `update_reference(id, patch, expected_revision)`. Read the revision first. Patch `note`,
  `title`, or `source: {app?, bundle_id?, url?}`. Omitted fields stay unchanged; null clears optional
  title, bundle ID or URL; an empty note clears the note. A stale revision returns the current reference.
- Manage: `trash_references(ids)` and `restore_references(ids)`. Trash retains media and notes.
  The app's removal actions use the same Trash, with Restore in the sidebar's Trash section.

Tools return structured results alongside readable text. Add/trash/restore return per-item results,
including partial failures; list returns `next_cursor`. The app refreshes when MCP writes to its
active library. Metadata edits use revisions and a cross-process library lock to prevent lost edits.
`get_library_info` reports the actual library path and counts; access failures are explicit errors.

Example tool arguments for adding one existing reference:

```json
{"items":[{"path":"/absolute/path/menu.png","note":"Clear grouping","source":{"app":"Example App"}}]}
```

## Storage

`~/Library/Application Support/Refs/Library/`, as `<id>.png` + `<id>.json` pairs, with an additional `<id>.mp4` for videos. The folder can be changed
in Settings; `REFS_LIBRARY=/path` overrides it for both the app and the MCP helper.

## Layout

- `Sources/RefsCore`: reference model, library store, search, image coding
- `Sources/RefsMCP`, `Sources/refs-mcp`: MCP server and its stdio entry point
- `Sources/Refs`: the app (AppKit + SwiftUI)
- `mocks/`, `spikes/`: v1 UI mocks and research notes
