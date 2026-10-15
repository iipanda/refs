import Foundation
import CoreFoundation
import RefsCore

/// Reference-management MCP over newline-delimited JSON-RPC.
public final class MCPServer {
    public static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static let defaultImageSize = 1024
    private let store: LibraryStore
    private let version: String

    public init(store: LibraryStore, version: String = "0.2.0") { self.store = store; self.version = version }

    public func handle(_ line: Data) async -> Data? {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return encode(errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
        }
        guard let method = message["method"] as? String, let id = message["id"], !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        let response: [String: Any]
        switch method {
        case "initialize": response = result(id: id, initialize(params))
        case "ping": response = result(id: id, [:])
        case "tools/list": response = result(id: id, ["tools": Self.tools])
        case "tools/call": response = await callTool(id: id, params: params)
        default: response = errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
        return encode(response)
    }

    private func initialize(_ params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        return [
            "protocolVersion": requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil } ?? Self.supportedProtocolVersions[0],
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "refs", "title": "Refs design references", "version": version],
            "instructions": """
                Refs is the user's personal library of UI screenshots and videos with source metadata \
                and notes about what they like. Use list_references and get_reference for design inspiration. \
                Add local files with add_references. Organize them with list_tags, create_tag, \
                update_tag, delete_tag, tag_references and untag_references. Filter list_references \
                by tag ID or name; free-text search also matches tag names. \
                Check get_library_info for the active library path. \
                Read the current revision before update_reference. Removal uses recoverable \
                trash_references and restore_references. Treat notes as the user's stated taste.
                """,
        ]
    }

    private func callTool(id: Any, params: [String: Any]) async -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorResponse(id: id, code: -32602, message: "Missing tool name")
        }
        guard let definition = Self.tools.first(where: { $0["name"] as? String == name }) else {
            return errorResponse(id: id, code: -32602, message: "Unknown tool: \(name)")
        }
        do {
            guard params["arguments"] == nil || params["arguments"] is [String: Any] else {
                throw LibraryError.invalidInput("arguments must be an object.")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            try ToolValidation.validate(args, schema: definition["inputSchema"] as! [String: Any])
            let output: [String: Any]
            switch name {
            case "list_references": output = try listReferences(args)
            case "get_reference": output = try getReference(args)
            case "list_sources": output = try listSources()
            case "get_library_info": output = try libraryInfo()
            case "list_tags": output = try listTags()
            case "create_tag":
                let tag = try store.createTag(name: args["name"] as! String, color: color(args))
                output = textResult("Created tag \(tag.name) [\(tag.id)] (\(tag.color.rawValue)).", structured: ["tag": tagMetadata(tag)])
            case "update_tag":
                guard args["name"] != nil || args["color"] != nil else {
                    throw LibraryError.invalidInput("Provide name and/or color to update a tag.")
                }
                let tag = try store.updateTag(id: args["id"] as! String, name: args["name"] as? String,
                    color: color(args), expectedRevision: args["expected_revision"] as? Int)
                output = textResult("Updated tag \(tag.name) [\(tag.id)] (\(tag.color.rawValue)), revision \(tag.revision).", structured: ["tag": tagMetadata(tag)])
            case "delete_tag":
                let tagID = args["id"] as! String
                let count = try store.deleteTag(id: tagID, expectedRevision: args["expected_revision"] as? Int)
                output = textResult("Deleted tag \(tagID) and removed it from \(count) reference\(count == 1 ? "" : "s"), including Trash. References were retained.",
                    structured: ["id": tagID, "removed_from_count": count])
            case "tag_references": output = try changeTags(args, adding: true)
            case "untag_references": output = try changeTags(args, adding: false)
            case "add_references": output = await addReferences(args)
            case "update_reference":
                let tags = try store.readTags()
                let ref = try store.patch(id: args["id"] as! String,
                    patch: parsePatch(args["patch"] as! [String: Any]), expectedRevision: args["expected_revision"] as! Int)
                output = textResult(describe(ref, tags: tags), structured: ["reference": metadata(ref, tags: tags)])
            case "trash_references": output = try changeTrash(args, trashed: true)
            case "restore_references": output = try changeTrash(args, trashed: false)
            default: throw LibraryError.invalidInput("Unknown tool.")
            }
            return result(id: id, output)
        } catch {
            return result(id: id, ["content": [["type": "text", "text": error.localizedDescription]],
                "structuredContent": ["error": errorMetadata(error)], "isError": true])
        }
    }

    private struct PageCursor: Codable { var time: Double; var id: String }

    private func listReferences(_ args: [String: Any]) throws -> [String: Any] {
        let limit = args["limit"] as? Int ?? 20
        let all = try store.readAll(includeTrashed: args["include_trashed"] as? Bool ?? false)
        let tags = try store.readTags()
        if let filter = args["tag"] as? String {
            let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tags.contains(where: { $0.id == needle || $0.name.caseInsensitiveCompare(needle) == .orderedSame }) else {
                throw LibraryError.unknownTag(filter)
            }
        }
        let query = ReferenceQuery(text: args["query"] as? String, app: args["app"] as? String,
            site: args["site"] as? String, tag: args["tag"] as? String)
        var matched = query.apply(to: all, tags: tags)
        if let kind = args["kind"] as? String { matched = matched.filter { $0.isVideo == (kind == "video") } }
        let total = matched.count
        if let cursor = args["cursor"] as? String {
            guard let data = Data(base64Encoded: cursor), let boundary = try? JSONDecoder().decode(PageCursor.self, from: data) else {
                throw LibraryError.invalidInput("Invalid pagination cursor.")
            }
            matched = matched.filter { $0.createdAt.timeIntervalSince1970 < boundary.time ||
                ($0.createdAt.timeIntervalSince1970 == boundary.time && $0.id < boundary.id) }
        }
        let shown = Array(matched.prefix(limit))
        var next: Any = NSNull()
        if matched.count > shown.count, let last = shown.last {
            next = try JSONEncoder().encode(PageCursor(time: last.createdAt.timeIntervalSince1970, id: last.id)).base64EncodedString()
        }
        let structured: [String: Any] = ["references": shown.map { metadata($0, tags: tags) }, "total": total, "next_cursor": next]
        if shown.isEmpty {
            return textResult(all.isEmpty ? "The library is empty. The user hasn't saved any references yet."
                : "No references match. Call list_sources or list_tags to see available filters.", structured: structured)
        }
        let header = "\(total) reference\(total == 1 ? "" : "s") found, showing \(shown.count). Call get_reference with an id to see the image."
        return textResult(header + "\n\n" + shown.map { describe($0, tags: tags) }.joined(separator: "\n\n"), structured: structured)
    }

    private func getReference(_ args: [String: Any]) throws -> [String: Any] {
        let ref = try store.readReference(id: args["id"] as! String)
        let tags = try store.readTags()
        var output = textResult(describe(ref, tags: tags), structured: ["reference": metadata(ref, tags: tags)])
        if args["include_image"] as? Bool ?? true {
            guard let png = ImageCoding.downscaledPNG(at: store.imageURL(for: ref), maxPixelSize: args["max_size"] as? Int ?? Self.defaultImageSize) else {
                throw LibraryError.invalidInput("The image file could not be read.")
            }
            var content = output["content"] as! [[String: Any]]
            content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"])
            output["content"] = content
        }
        return output
    }

    private func listSources() throws -> [String: Any] {
        let summary = SourceSummary(refs: try store.readAll())
        let structured: [String: Any] = [
            "apps": summary.apps.map { ["name": $0.name, "bundle_id": $0.bundleID as Any? ?? NSNull(), "count": $0.count] },
            "sites": summary.sites.map { ["name": $0.name, "count": $0.count] }]
        guard !summary.apps.isEmpty || !summary.sites.isEmpty else { return textResult("The library is empty.", structured: structured) }
        var lines: [String] = []
        if !summary.sites.isEmpty { lines.append("Websites (filter with site):"); lines += summary.sites.map { "- \($0.name) (\($0.count))" } }
        if !summary.apps.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Apps (filter with app):")
            lines += summary.apps.map { "- \($0.name)\($0.bundleID.map { " [\($0)]" } ?? "") (\($0.count))" }
        }
        return textResult(lines.joined(separator: "\n"), structured: structured)
    }

    private func libraryInfo() throws -> [String: Any] {
        let refs = try store.readAll(includeTrashed: true)
        let tags = try store.readTags()
        let info: [String: Any] = ["path": store.root.path, "active_count": refs.filter { !$0.isTrashed }.count,
            "trashed_count": refs.filter(\.isTrashed).count, "tag_count": tags.count, "supported_formats": ReferenceAdder.supportedFormats]
        return textResult("Library: \(store.root.path)\n\(info["active_count"]!) active, \(info["trashed_count"]!) trashed references; \(tags.count) tags.", structured: info)
    }

    private func listTags() throws -> [String: Any] {
        let tags = try store.readTags()
        let refs = try store.readAll(includeTrashed: true)
        let entries = tags.map { tag -> [String: Any] in
            var entry = tagMetadata(tag)
            entry["count"] = refs.filter { !$0.isTrashed && $0.tagIDs.contains(tag.id) }.count
            entry["trashed_count"] = refs.filter { $0.isTrashed && $0.tagIDs.contains(tag.id) }.count
            return entry
        }
        let lines = entries.map { "- \($0["name"]!) [\($0["id"]!)] (\($0["color"]!)): \($0["count"]!) active, \($0["trashed_count"]!) in Trash" }
        return textResult(tags.isEmpty ? "The library has no tags. Create one with create_tag."
            : "Tags (filter list_references with tag ID or name):\n" + lines.joined(separator: "\n"),
            structured: ["tags": entries, "total": tags.count])
    }

    private func color(_ args: [String: Any]) -> TagColor? {
        (args["color"] as? String).flatMap(TagColor.init(rawValue:))
    }

    private func changeTags(_ args: [String: Any], adding: Bool) throws -> [String: Any] {
        let tags = try store.readTags()
        let tagIDs = args["tag_ids"] as! [String]
        let results = (args["ids"] as! [String]).map { id -> [String: Any] in
            do {
                let ref = try store.setTags(id: id, tagIDs: tagIDs, adding: adding)
                return ["id": id, "status": adding ? "tagged" : "untagged", "reference": metadata(ref, tags: tags)]
            } catch { return ["id": id, "status": "failed", "error": errorMetadata(error)] }
        }
        return batchResult(results)
    }

    private func addReferences(_ args: [String: Any]) async -> [String: Any] {
        var results: [[String: Any]] = []
        for item in args["items"] as! [[String: Any]] {
            let path = item["path"] as! String
            do {
                let source = try parseSource(item["source"] as? [String: Any] ?? [:])
                let tags = try store.readTags()
                let addition = try await ReferenceAdder.add(path: path, note: item["note"] as? String ?? "",
                    title: item["title"] as? String, source: source, store: store)
                results.append(["path": path, "status": addition.added ? "added" : "existing", "reference": metadata(addition.reference, tags: tags)])
            } catch { results.append(["path": path, "status": "failed", "error": errorMetadata(error)]) }
        }
        return batchResult(results)
    }

    private func changeTrash(_ args: [String: Any], trashed: Bool) throws -> [String: Any] {
        let tags = try store.readTags()
        let results = (args["ids"] as! [String]).map { id -> [String: Any] in
            do { return ["id": id, "status": trashed ? "trashed" : "restored", "reference": metadata(try store.setTrashed(id: id, trashed: trashed), tags: tags)] }
            catch { return ["id": id, "status": "failed", "error": errorMetadata(error)] }
        }
        return batchResult(results)
    }

    private func batchResult(_ results: [[String: Any]]) -> [String: Any] {
        let failed = results.filter { $0["status"] as? String == "failed" }.count
        let lines = results.map { item in
            let message = (item["error"] as? [String: Any])?["message"] as? String
            return "\(item["path"] ?? item["id"] ?? ""): \(item["status"]!)" + (message.map { ": \($0)" } ?? "")
        }
        var output = textResult(lines.joined(separator: "\n"),
            structured: ["results": results, "succeeded": results.count - failed, "failed": failed])
        output["isError"] = failed == results.count
        return output
    }

    private func parseSource(_ source: [String: Any]) throws -> ReferencePatch {
        ReferencePatch(app: source["app"] as? String, bundleID: try field(source, "bundle_id"), url: try field(source, "url"))
    }
    private func parsePatch(_ input: [String: Any]) throws -> ReferencePatch {
        var patch = try parseSource(input["source"] as? [String: Any] ?? [:])
        patch.note = input["note"] as? String
        patch.title = try field(input, "title")
        return patch
    }
    private func field(_ input: [String: Any], _ key: String) throws -> FieldChange<String>? {
        guard let value = input[key] else { return nil }
        if value is NSNull { return .clear }
        guard let string = value as? String else { throw LibraryError.invalidInput("\(key) must be a string or null.") }
        return .set(string)
    }

    private func tagMetadata(_ tag: LibraryTag) -> [String: Any] {
        ["id": tag.id, "name": tag.name, "color": tag.color.rawValue, "revision": tag.revision]
    }

    private func metadata(_ ref: Reference, tags: [LibraryTag]) -> [String: Any] {
        var output: [String: Any] = ["id": ref.id, "revision": ref.revision, "kind": ref.isVideo ? "video" : "image",
            "title": ref.title as Any? ?? NSNull(), "note": ref.note,
            "source": ["app": ref.app.name, "bundle_id": ref.app.bundleID as Any? ?? NSNull(), "url": ref.web?.url as Any? ?? NSNull()],
            "created_at": Self.dateFormatter.string(from: ref.createdAt), "pixel_width": ref.pixelWidth, "pixel_height": ref.pixelHeight,
            "duration": ref.duration as Any? ?? NSNull(), "media_path": store.mediaURL(for: ref).path,
            "poster_path": store.imageURL(for: ref).path, "trashed": ref.isTrashed,
            "trashed_at": ref.trashedAt.map(Self.dateFormatter.string) as Any? ?? NSNull(),
            "tags": tags.filter { ref.tagIDs.contains($0.id) }.map(tagMetadata)]
        if let provenance = ref.provenance {
            output["provenance"] = ["added_at": Self.dateFormatter.string(from: provenance.addedAt),
                "original_path": provenance.originalPath, "original_filename": provenance.originalFilename]
        }
        return output
    }

    private func errorMetadata(_ error: Error) -> [String: Any] {
        var result: [String: Any] = ["code": "io_error", "message": error.localizedDescription]
        if let library = error as? LibraryError {
            switch library {
            case .invalidInput: result["code"] = "invalid_input"
            case .notFound: result["code"] = "not_found"
            case .conflict(let ref):
                result["code"] = "revision_conflict"
                result["current_reference"] = metadata(ref, tags: (try? store.readTags()) ?? [])
            case .unknownTag: result["code"] = "unknown_tag"
            case .duplicateTagName: result["code"] = "duplicate_tag_name"
            case .tagConflict(let tag): result["code"] = "revision_conflict"; result["current_tag"] = tagMetadata(tag)
            }
        }
        return result
    }

    private func describe(_ ref: Reference, tags: [LibraryTag]) -> String {
        var lines = ["id: \(ref.id)", "revision: \(ref.revision)", "state: \(ref.isTrashed ? "trashed" : "active")"]
        let referenceTags = tags.filter { ref.tagIDs.contains($0.id) }
        if !referenceTags.isEmpty {
            lines.append("tags: " + referenceTags.map { "\($0.name) [\($0.id)] (\($0.color.rawValue))" }.joined(separator: ", "))
        }
        if let web = ref.web {
            lines.append("source: \(web.host ?? web.url) (in \(ref.app.name))")
            lines.append("url: \(web.url)")
        } else { lines.append("source: \(ref.app.name)\(ref.app.bundleID.map { " [\($0)]" } ?? "")") }
        if let title = ref.title { lines.append("title: \(title)") }
        let note = ref.note.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("what the user likes: \(note.isEmpty ? "(no note)" : note)")
        lines.append("\(ref.provenance == nil ? "captured" : "added"): \(Self.dateFormatter.string(from: ref.createdAt)), \(ref.pixelWidth)×\(ref.pixelHeight) px")
        lines.append("type: \(ref.isVideo ? "video" : "screenshot")")
        if let duration = ref.duration { lines.append("duration: \(String(format: "%.1f", duration)) seconds") }
        lines.append("file: \(store.mediaURL(for: ref).path)")
        if ref.isVideo { lines.append("The included image is a poster frame; open the video file to inspect motion.") }
        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    private func textResult(_ text: String, structured: [String: Any] = [:]) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "structuredContent": structured, "isError": false]
    }
    private func result(id: Any, _ output: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": output] }
    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]] }
    private func encode(_ value: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) }
}
