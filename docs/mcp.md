# Connect your coding agent

[← Back to Refs](../README.md)

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
