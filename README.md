# Refs

A lightweight macOS menu-bar app for saving UI screenshots and videos as design references. Each capture records
the app or website it came from and one line about what you like, and coding agents can read the
library over MCP.

## Build

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

## Use

- **⌘⇧2** captures an area, **⌘⇧3** a window. Space switches between the two while selecting, and Esc cancels.
- **Record Area… / Record Window…** in the menu bar or File menu starts a silent video with the cursor visible. Select the source, then use the floating **Stop** button (or either capture shortcut) to finish. Videos are H.264 MP4 at up to 30 fps and 3840 pixels on the longest edge.
- Videos play in the save panel and Library inspector; double-click opens the movie in your default player. MCP supplies a poster frame and the movie path.
- After capturing, type what you like and press Return. Esc discards.
- The library groups references by app (native apps) and website (browser captures).
- Organize references with color-coded tags. Select a tag in the sidebar to filter the library;
  search also matches tag names. Add tags while saving, from the save panel's Add Tag button, or
  later from the inspector: the tag picker finds a tag as you type, and Return creates a new one with
  an automatic color. Select several cards to tag them together in the inspector or the context
  menu's Tags submenu. A dashed chip means only some selected references have that tag; click it
  to add it to all of them.
- Create a tag with the + beside Tags in the sidebar. Right-click a sidebar tag to rename it,
  choose a system color, or delete it. Deleting a tag
  removes it from references, including Trash, without deleting the references. Moving a reference
  to Trash keeps its tags for restoration.

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
so it works even when the app isn't running. Settings › Agents opens with a copyable prompt that asks
your coding agent to configure Refs and verify the connection. Collapsible manual instructions cover Claude Code, Codex, Cursor,
Claude Desktop, Pi Agent and OMP (Oh My Pi). For example:

```sh
claude mcp add --scope user refs -- /Applications/Refs.app/Contents/MacOS/refs-mcp
```

Tools:
- Read: `list_references(query?, app?, site?, tag?, limit?, kind?, cursor?, include_trashed?)`,
  `get_reference(id, include_image?, max_size?)`, `list_sources()`, `list_tags()`, `get_library_info()`.
  Filter `tag` by its stable ID or case-insensitive name. Free-text `query` also searches tag names.
  Reference metadata includes resolved tags with their IDs, names and colors; `list_tags` reports
  active-reference counts, and `get_library_info` includes `tag_count`.
- Add: `add_references(items: [{path, note?, title?, source?}])`. Supply 1–100 absolute local paths.
  PNG/JPEG/HEIC/WebP become PNG; MP4/MOV keep their container and receive a poster.
  Originals stay untouched. Identical media returns `existing` without overwriting metadata.
- Edit: `update_reference(id, patch, expected_revision)`. Read the revision first. Patch `note`,
  `title`, or `source: {app?, bundle_id?, url?}`. Omitted fields stay unchanged; null clears optional
  title, bundle ID or URL; an empty note clears the note. A stale revision returns the current reference.
- Manage: `trash_references(ids)` and `restore_references(ids)`. Trash retains media and notes.
  The app's removal actions use the same Trash, with Restore in the sidebar's Trash section.
- Tags: `create_tag(name, color?)`, `update_tag(id, name?, color?, expected_revision?)`,
  `delete_tag(id, expected_revision?)`, `tag_references(ids, tag_ids)`,
  `untag_references(ids, tag_ids)`. Names are trimmed and unique case-insensitively. Colors are
  `red`, `orange`, `yellow`, `green`, `mint`, `teal`, `blue`, `indigo`, `purple`, `pink`, `brown`,
  or `gray`; an omitted creation color picks an unused color where possible. Tag updates return
  a revision; pass `expected_revision` to reject stale rename, recolor or deletion requests.
  Bulk tagging accepts 1–100 reference IDs and tag IDs, adds or removes memberships without
  replacing other tags, and returns a result for every reference. Repeated membership changes
  are safe. Deleting a tag removes its memberships from active and trashed references.

Tools return structured results alongside readable text. Add/trash/restore/tag/untag return per-item results,
including partial failures; list returns `next_cursor`. The app refreshes when MCP writes to its
active library. Metadata edits use revisions and a cross-process library lock to prevent lost edits.
`get_library_info` reports the actual library path and counts; access failures are explicit errors.
Tag changes share the same library lock; membership changes advance reference revisions, so an
older `update_reference` request cannot overwrite them. Rename and color changes only update the
tag catalog. The app also refreshes its tags when another MCP process changes the library.

Example tool arguments for adding one existing reference:

```json
{"items":[{"path":"/absolute/path/menu.png","note":"Clear grouping","source":{"app":"Example App"}}]}
```

After creating a tag, use its returned ID to tag several references in one call:

```json
{"ids":["reference-id-1","reference-id-2"],"tag_ids":["tag-id"]}
```

## Storage

`~/Library/Application Support/Refs/Library/`, as `<id>.png` + `<id>.json` pairs, with an additional `<id>.mp4` for videos. The folder can be changed
in Settings; `REFS_LIBRARY=/path` overrides it for both the app and the MCP helper.
The library also contains `tags.json`, a catalog of stable tag IDs, names, palette colors and
revisions. Reference sidecars store only their `tagIDs`, so renaming or recoloring a tag does not
rewrite references. Existing libraries with no catalog or tag IDs load as untagged, without a
migration rewrite. Tags travel with the library folder.

## Layout

- `Sources/RefsCore`: reference model, library store, search, image coding
- `Sources/RefsMCP`, `Sources/refs-mcp`: MCP server and its stdio entry point
- `Sources/Refs`: the app (AppKit + SwiftUI)
- `mocks/`, `spikes/`: v1 UI mocks and research notes
