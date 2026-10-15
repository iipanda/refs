# Using Refs

[← Back to Refs](../README.md)

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

## Your library

`~/Library/Application Support/Refs/Library/`, as `<id>.png` + `<id>.json` pairs, with an additional `<id>.mp4` for videos. The folder can be changed
in Settings; `REFS_LIBRARY=/path` overrides it for both the app and the MCP helper.
The library also contains `tags.json`, a catalog of stable tag IDs, names, palette colors and
revisions. Reference sidecars store only their `tagIDs`, so renaming or recoloring a tag does not
rewrite references. Existing libraries with no catalog or tag IDs load as untagged, without a
migration rewrite. Tags travel with the library folder.
