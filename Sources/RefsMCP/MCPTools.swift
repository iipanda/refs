import Foundation

extension MCPServer {
    private static let string: [String: Any] = ["type": "string"]
    private static let nullableString: [String: Any] = ["anyOf": [["type": "string"], ["type": "null"]]]
    private static let source = object(["app": ["type": "string", "minLength": 1], "bundle_id": nullableString, "url": nullableString])
    private static func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    private static func tool(_ name: String, _ description: String, _ schema: [String: Any],
                             readOnly: Bool = true, destructive: Bool = false, idempotent: Bool = true) -> [String: Any] {
        ["name": name, "description": description, "inputSchema": schema,
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": destructive, "idempotentHint": idempotent, "openWorldHint": false]]
    }
    private static let ids = object(["ids": ["type": "array", "items": ["type": "string", "minLength": 1], "minItems": 1, "maxItems": 100]], required: ["ids"])
    static let tools: [[String: Any]] = [
        tool("list_references", "Search saved references. Returns structured metadata, readable descriptions and next_cursor. Default limit 20; trash is hidden unless include_trashed is true.", object([
            "query": string, "app": string, "site": string,
            "limit": ["type": "integer", "minimum": 1, "maximum": 100],
            "kind": ["type": "string", "enum": ["image", "video"]], "cursor": string, "include_trashed": ["type": "boolean"]])),
        tool("get_reference", "Get metadata and revision, with an optional screenshot or video poster. include_image defaults true; max_size defaults 1024. Video paths point to the actual movie.", object([
            "id": string, "include_image": ["type": "boolean"], "max_size": ["type": "integer", "minimum": 128, "maximum": 4096]], required: ["id"])),
        tool("list_sources", "List active references' websites and apps with counts.", object([:])),
        tool("get_library_info", "Show the active library path, active/trashed counts, and supported local file formats. Access errors are reported, not treated as an empty library.", object([:])),
        tool("add_references", "Add 1–100 local image/video files. Copies originals, generates posters, and returns added/existing/failed per item. Identical media returns its existing reference without overwriting metadata, including trashed references.", object([
            "items": ["type": "array", "minItems": 1, "maxItems": 100,
                      "items": object(["path": ["type": "string", "minLength": 1], "note": string, "title": string, "source": source], required: ["path"])]]
            , required: ["items"]), readOnly: false),
        tool("update_reference", "Patch metadata using the current expected_revision. Omitted fields stay unchanged; null clears title, bundle_id or url. Empty note clears it. Conflicts return current_reference.", object([
            "id": string, "expected_revision": ["type": "integer", "minimum": 1],
            "patch": object(["note": string, "title": nullableString, "source": source])], required: ["id", "patch", "expected_revision"]), readOnly: false, idempotent: false),
        tool("trash_references", "Hide references while retaining their media and metadata for restore_references. Original imported files remain untouched. Returns per-id results.", ids, readOnly: false, destructive: true),
        tool("restore_references", "Restore references from library trash with their original IDs. Repeated restores are safe. Returns per-id results.", ids, readOnly: false),
    ]
}
