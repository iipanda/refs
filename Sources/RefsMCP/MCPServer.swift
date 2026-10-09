import Foundation
import RefsCore

/// A minimal, read-only MCP server over newline-delimited JSON-RPC (the stdio transport).
///
/// It implements only what the reference library needs: `initialize`, `ping`, `tools/list` and
/// `tools/call`. Notifications are accepted and ignored.
public final class MCPServer {
    public static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static let defaultImageSize = 1024

    private let store: LibraryStore
    private let version: String

    public init(store: LibraryStore, version: String = "0.1.0") {
        self.store = store
        self.version = version
    }

    /// Handles one JSON-RPC message. Returns the serialized response, or `nil` for notifications.
    public func handle(_ line: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let message = object as? [String: Any]
        else {
            return encode(errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let method = message["method"] as? String else {
            // A response or malformed message. Nothing to answer.
            return nil
        }
        guard let id = message["id"], !(id is NSNull) else {
            // Notification, e.g. notifications/initialized.
            return nil
        }
        let params = message["params"] as? [String: Any] ?? [:]

        let response: [String: Any]
        switch method {
        case "initialize":
            response = result(id: id, initialize(params))
        case "ping":
            response = result(id: id, [:])
        case "tools/list":
            response = result(id: id, ["tools": Self.tools])
        case "tools/call":
            response = callTool(id: id, params: params)
        default:
            response = errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
        return encode(response)
    }

    // MARK: - Methods

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": version,
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "refs", "title": "Refs design references", "version": self.version],
            "instructions": """
                Refs is the user's personal library of UI screenshots they saved as design references. \
                Each reference records the source app or website and a short note about what the user \
                likes in it. When the user asks for a design, use list_references (filter by app, site or \
                text) to find relevant references, then get_reference to see the image. Treat the notes \
                as the user's stated taste and follow them.
                """,
        ]
    }

    private func callTool(id: Any, params: [String: Any]) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing tool name")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "list_references":
            return result(id: id, listReferences(args))
        case "get_reference":
            return result(id: id, getReference(args))
        case "list_sources":
            return result(id: id, listSources())
        default:
            return errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
    }

    // MARK: - Tools

    private func listReferences(_ args: [String: Any]) -> [String: Any] {
        let limit = min(max(intArg(args["limit"]) ?? 20, 1), 100)
        let all = store.loadAll()
        let query = ReferenceQuery(
            text: args["query"] as? String,
            app: args["app"] as? String,
            site: args["site"] as? String
        )
        let matched = query.apply(to: all)
        let shown = Array(matched.prefix(limit))

        guard !shown.isEmpty else {
            let hint = all.isEmpty
                ? "The library is empty. The user hasn't saved any references yet."
                : "No references match. Call list_sources to see which apps and sites have references."
            return textResult(hint)
        }
        var lines = ["\(matched.count) reference\(matched.count == 1 ? "" : "s") found, showing \(shown.count). Call get_reference with an id to see the image.", ""]
        for ref in shown {
            lines.append(describe(ref))
            lines.append("")
        }
        return textResult(lines.joined(separator: "\n"))
    }

    private func getReference(_ args: [String: Any]) -> [String: Any] {
        guard let id = args["id"] as? String, let ref = store.reference(id: id) else {
            return toolError("No reference with id \(String(describing: args["id"] ?? "nil")). Use list_references to find ids.")
        }
        let includeImage = args["include_image"] as? Bool ?? true
        let maxSize = min(max(intArg(args["max_size"]) ?? Self.defaultImageSize, 128), 4096)

        var content: [[String: Any]] = [["type": "text", "text": describe(ref)]]
        if includeImage {
            if let png = ImageCoding.downscaledPNG(at: store.imageURL(for: ref), maxPixelSize: maxSize) {
                content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"])
            } else {
                content.append(["type": "text", "text": "The image file could not be read."])
            }
        }
        return ["content": content, "isError": false]
    }

    private func listSources() -> [String: Any] {
        let summary = SourceSummary(refs: store.loadAll())
        guard !summary.apps.isEmpty || !summary.sites.isEmpty else {
            return textResult("The library is empty.")
        }
        var lines: [String] = []
        if !summary.sites.isEmpty {
            lines.append("Websites (filter with site):")
            lines += summary.sites.map { "- \($0.name) (\($0.count))" }
        }
        if !summary.apps.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Apps (filter with app):")
            lines += summary.apps.map { entry in
                "- \(entry.name)\(entry.bundleID.map { " [\($0)]" } ?? "") (\(entry.count))"
            }
        }
        return textResult(lines.joined(separator: "\n"))
    }

    // MARK: - Formatting

    private func describe(_ ref: Reference) -> String {
        var lines = ["id: \(ref.id)"]
        if let web = ref.web {
            lines.append("source: \(web.host ?? web.url) (in \(ref.app.name))")
            lines.append("url: \(web.url)")
        } else {
            lines.append("source: \(ref.app.name)\(ref.app.bundleID.map { " [\($0)]" } ?? "")")
        }
        if let title = ref.title { lines.append("title: \(title)") }
        let note = ref.note.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("what the user likes: \(note.isEmpty ? "(no note)" : note)")
        lines.append("captured: \(Self.dateFormatter.string(from: ref.createdAt)), \(ref.pixelWidth)×\(ref.pixelHeight) px")
        lines.append("file: \(store.imageURL(for: ref).path)")
        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - JSON-RPC helpers

    private func intArg(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func textResult(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": false]
    }

    private func toolError(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": true]
    }

    private func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    // MARK: - Tool definitions

    static let tools: [[String: Any]] = [
        [
            "name": "list_references",
            "title": "List design references",
            "description": "Search the user's saved UI design references. Returns id, source app or website, page title, the user's note on what they like, and the image file path. Text only; use get_reference to see an image.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Words to match in notes, titles, URLs and app names. All words must match."],
                    "app": ["type": "string", "description": "App name or bundle ID, e.g. \"Linear\" or \"com.figma.Desktop\"."],
                    "site": ["type": "string", "description": "Website host, e.g. \"stripe.com\". Subdomains match too."],
                    "limit": ["type": "integer", "description": "Maximum results, 1–100. Default 20.", "minimum": 1, "maximum": 100],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "get_reference",
            "title": "Get a design reference",
            "description": "Get one saved reference by id, including the screenshot as an image (downscaled to max_size pixels on the longest edge).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Reference id from list_references."],
                    "include_image": ["type": "boolean", "description": "Include the screenshot. Default true."],
                    "max_size": ["type": "integer", "description": "Longest image edge in pixels, 128–4096. Default 1024.", "minimum": 128, "maximum": 4096],
                ],
                "required": ["id"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "list_sources",
            "title": "List reference sources",
            "description": "List the websites and apps the user has saved references from, with counts.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
    ]
}
