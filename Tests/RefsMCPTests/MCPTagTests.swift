import CoreGraphics
import Foundation
import Testing
import RefsCore
@testable import RefsMCP

private func makeTagStore() throws -> (LibraryStore, Reference, Reference) {
    let store = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("refs-mcp-tags-\(UUID())"))
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let png = ImageCoding.pngData(from: context.makeImage()!)!
    let first = try store.add(pngData: png, pixelWidth: 1, pixelHeight: 1,
        app: SourceApp(name: "First App", bundleID: nil), windowTitle: nil, web: nil, note: "First note")
    let second = try store.add(pngData: png, pixelWidth: 1, pixelHeight: 1,
        app: SourceApp(name: "Second App", bundleID: nil), windowTitle: nil, web: nil, note: "Second note")
    return (store, first, second)
}

private func tagCall(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) async throws -> [String: Any] {
    let input = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": ["name": name, "arguments": arguments]])
    let data = try #require(await server.handle(input))
    let response = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(response["result"] as? [String: Any])
}

private func tagPayload(_ result: [String: Any]) throws -> [String: Any] {
    try #require(result["structuredContent"] as? [String: Any])
}

private func tagText(_ result: [String: Any]) -> String {
    (result["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
}

@Suite struct MCPTagTests {
    @Test func createRenameRecolorAndDefaultColorsReturnStructuredReadableResults() async throws {
        let (store, _, _) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let server = MCPServer(store: store)
        let created = try await tagCall(server, "create_tag", ["name": "  Navigation  ", "color": "purple"])
        #expect(created["isError"] as? Bool == false)
        let tag = try #require(try tagPayload(created)["tag"] as? [String: Any])
        let id = try #require(tag["id"] as? String)
        #expect(tag["name"] as? String == "Navigation" && tag["color"] as? String == "purple")
        #expect(tag["revision"] as? Int == 1 && tagText(created).contains("Navigation"))
        let automatic = try tagPayload(try await tagCall(server, "create_tag", ["name": "Motion"]))
        let autoTag = try #require(automatic["tag"] as? [String: Any])
        #expect(TagColor(rawValue: autoTag["color"] as? String ?? "") != nil)
        #expect(autoTag["color"] as? String != "purple")
        let updated = try await tagCall(server, "update_tag", ["id": id, "name": "  Menus  ", "color": "teal", "expected_revision": 1])
        let edited = try #require(try tagPayload(updated)["tag"] as? [String: Any])
        #expect(edited["id"] as? String == id && edited["name"] as? String == "Menus")
        #expect(edited["color"] as? String == "teal" && edited["revision"] as? Int == 2)
        #expect(tagText(updated).contains("Menus") && tagText(updated).contains("teal"))
        #expect(try tagPayload(try await tagCall(server, "get_library_info"))["tag_count"] as? Int == 2)
    }

    @Test func bulkTaggingSupportsPartialFailuresAndPreservesUnrelatedMetadata() async throws {
        let (store, first, second) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Navigation", color: .blue)
        let other = try store.createTag(name: "Other", color: .pink)
        _ = try store.setTags(id: first.id, tagIDs: [other.id], adding: true)
        let server = MCPServer(store: store)
        let result = try await tagCall(server, "tag_references", ["ids": [first.id, "missing", second.id], "tag_ids": [tag.id]])
        let payload = try tagPayload(result)
        #expect(result["isError"] as? Bool == false)
        #expect(payload["succeeded"] as? Int == 2 && payload["failed"] as? Int == 1)
        let items = try #require(payload["results"] as? [[String: Any]])
        #expect(items.compactMap { $0["status"] as? String } == ["tagged", "failed", "tagged"])
        #expect((items[1]["error"] as? [String: Any])?["code"] as? String == "not_found")
        #expect(tagText(result).contains("No reference with id missing."))
        #expect(((items[0]["reference"] as? [String: Any])?["tags"] as? [[String: Any]])?.count == 2)
        let firstNow = try store.readReference(id: first.id)
        #expect(Set(firstNow.tagIDs) == [tag.id, other.id] && firstNow.note == first.note)
        let retry = try await tagCall(server, "tag_references", ["ids": [first.id], "tag_ids": [tag.id, tag.id]])
        #expect(retry["isError"] as? Bool == false)
        #expect(try store.readReference(id: first.id).revision == firstNow.revision)
        let removal = try await tagCall(server, "untag_references", ["ids": [first.id, second.id, "missing"], "tag_ids": [tag.id]])
        #expect(try tagPayload(removal)["failed"] as? Int == 1)
        #expect(try store.readReference(id: first.id).tagIDs == [other.id])
        #expect(try store.readReference(id: second.id).tagIDs.isEmpty)
        #expect(tagText(removal).contains("untagged"))
    }

    @Test func filtersAndSearchResolveTagsAndReferenceResultsIncludeThem() async throws {
        let (store, first, second) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Navigation", color: .indigo)
        _ = try store.setTags(id: first.id, tagIDs: [tag.id], adding: true)
        let server = MCPServer(store: store)
        for args in [["tag": tag.id], ["tag": "  NAVIGATION  "], ["query": "navigATion"], ["tag": tag.id, "app": "First App"]] {
            let listed = try await tagCall(server, "list_references", args)
            let payload = try tagPayload(listed)
            #expect(payload["total"] as? Int == 1)
            let refs = try #require(payload["references"] as? [[String: Any]])
            #expect(refs.first?["id"] as? String == first.id)
            let tags = try #require(refs.first?["tags"] as? [[String: Any]])
            #expect(tags.first?["id"] as? String == tag.id && tags.first?["name"] as? String == tag.name)
            #expect(tags.first?["color"] as? String == "indigo")
            #expect(tagText(listed).contains("Navigation"))
        }
        let noMatch = try await tagCall(server, "list_references", ["tag": tag.id, "app": "Second App"])
        #expect(try tagPayload(noMatch)["total"] as? Int == 0)
        let gotten = try tagPayload(try await tagCall(server, "get_reference", ["id": first.id, "include_image": false]))
        #expect(((gotten["reference"] as? [String: Any])?["tags"] as? [[String: Any]])?.count == 1)
        let untagged = try tagPayload(try await tagCall(server, "get_reference", ["id": second.id, "include_image": false]))
        #expect(((untagged["reference"] as? [String: Any])?["tags"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func trashKeepsTagsCountsSeparateAndDeletingRetainsReferences() async throws {
        let (store, first, second) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Navigation", color: .green)
        let server = MCPServer(store: store)
        _ = try await tagCall(server, "tag_references", ["ids": [first.id, second.id], "tag_ids": [tag.id]])
        _ = try await tagCall(server, "trash_references", ["ids": [second.id]])
        let listing = try await tagCall(server, "list_tags")
        let tags = try #require(try tagPayload(listing)["tags"] as? [[String: Any]])
        #expect(tags.first?["count"] as? Int == 1 && tags.first?["trashed_count"] as? Int == 1)
        #expect(tagText(listing).contains("1 active, 1 in Trash"))
        let trashed = try store.readReference(id: second.id)
        #expect(trashed.tagIDs == [tag.id] && trashed.isTrashed)
        let filtered = try await tagCall(server, "list_references", ["tag": tag.id, "include_trashed": true])
        #expect(try tagPayload(filtered)["total"] as? Int == 2)
        let deleted = try await tagCall(server, "delete_tag", ["id": tag.id, "expected_revision": 1])
        #expect(deleted["isError"] as? Bool == false && tagText(deleted).contains("References were retained"))
        #expect(try tagPayload(deleted)["removed_from_count"] as? Int == 2)
        #expect(try store.readTags().isEmpty)
        #expect(try store.readAll(includeTrashed: true).count == 2)
        #expect(try store.readReference(id: first.id).tagIDs.isEmpty)
        #expect(try store.readReference(id: second.id).tagIDs.isEmpty)
        #expect(try store.readReference(id: second.id).isTrashed)
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: first).path))
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: second).path))
    }

    @Test func tagEditsHonorRevisionsAndReferenceConflictsIncludeCurrentTags() async throws {
        let (store, first, _) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Navigation", color: .red)
        let server = MCPServer(store: store)
        _ = try await tagCall(server, "tag_references", ["ids": [first.id], "tag_ids": [tag.id]])
        let conflict = try await tagCall(server, "update_reference", ["id": first.id, "expected_revision": first.revision, "patch": ["note": "Stale"]])
        let referenceError = try #require(try tagPayload(conflict)["error"] as? [String: Any])
        let currentRef = try #require(referenceError["current_reference"] as? [String: Any])
        #expect(referenceError["code"] as? String == "revision_conflict")
        #expect((currentRef["tags"] as? [[String: Any]])?.first?["id"] as? String == tag.id)
        let currentRevision = try #require(currentRef["revision"] as? Int)
        let update = try await tagCall(server, "update_reference", ["id": first.id, "expected_revision": currentRevision, "patch": ["note": "Fresh"]])
        #expect(update["isError"] as? Bool == false)
        #expect(try store.readReference(id: first.id).tagIDs == [tag.id])
        _ = try await tagCall(server, "update_tag", ["id": tag.id, "name": "Menus", "expected_revision": 1])
        for (tool, args) in [
            ("update_tag", ["id": tag.id, "color": "orange", "expected_revision": 1] as [String: Any]),
            ("delete_tag", ["id": tag.id, "expected_revision": 1] as [String: Any]),
        ] {
            let failed = try await tagCall(server, tool, args)
            let error = try #require(try tagPayload(failed)["error"] as? [String: Any])
            #expect(failed["isError"] as? Bool == true && error["code"] as? String == "revision_conflict")
            let currentTag = try #require(error["current_tag"] as? [String: Any])
            #expect(currentTag["name"] as? String == "Menus" && currentTag["revision"] as? Int == 2)
        }
        #expect(try store.readTags().first?.name == "Menus")
    }

    @Test func invalidInputsAreClearAndDoNotWrite() async throws {
        let (store, first, second) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tag = try store.createTag(name: "Navigation", color: .red)
        let other = try store.createTag(name: "Motion", color: .yellow)
        let server = MCPServer(store: store)
        for (tool, args, code) in [
            ("create_tag", ["name": "  nAvIgAtIoN  "], "duplicate_tag_name"),
            ("update_tag", ["id": other.id, "name": "navigation"], "duplicate_tag_name"),
            ("create_tag", ["name": "   "], "invalid_input"),
            ("update_tag", ["id": tag.id], "invalid_input"),
            ("update_tag", ["id": "missing", "name": "Unknown"], "unknown_tag"),
            ("delete_tag", ["id": "missing"], "unknown_tag"),
            ("list_references", ["tag": "Missing"], "unknown_tag"),
            ("create_tag", ["name": "Invalid", "color": "cyan"], "invalid_input"),
        ] {
            let failed = try await tagCall(server, tool, args)
            let error = try #require(try tagPayload(failed)["error"] as? [String: Any])
            #expect(failed["isError"] as? Bool == true && error["code"] as? String == code)
            if args["color"] == "cyan" {
                #expect(tagText(failed).contains("Expected one of: red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray"))
            }
        }
        for args: [String: Any] in [
            ["ids": [], "tag_ids": [tag.id]], ["ids": [first.id], "tag_ids": []],
            ["ids": [first.id], "tag_ids": [NSNull()]], ["ids": [first.id], "tag_ids": [tag.id], "extra": true],
        ] {
            #expect(try await tagCall(server, "tag_references", args)["isError"] as? Bool == true)
        }
        let unknown = try await tagCall(server, "tag_references", ["ids": [first.id, second.id], "tag_ids": [tag.id, "missing"]])
        #expect(unknown["isError"] as? Bool == true)
        #expect(try tagPayload(unknown)["failed"] as? Int == 2)
        #expect(try store.readReference(id: first.id) == first)
        #expect(try store.readReference(id: second.id) == second)
        #expect(try store.readTags() == [other, tag])
    }

    @Test func taglessLibrariesRemainReadableAndCatalogFailuresAreExplicit() async throws {
        let (store, first, _) = try makeTagStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let sidecar = store.root.appendingPathComponent("\(first.id).json")
        var legacy = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as? [String: Any])
        legacy.removeValue(forKey: "tagIDs")
        try JSONSerialization.data(withJSONObject: legacy).write(to: sidecar)
        let server = MCPServer(store: store)
        #expect(try tagPayload(try await tagCall(server, "list_references"))["total"] as? Int == 2)
        #expect(try tagPayload(try await tagCall(server, "list_tags"))["total"] as? Int == 0)
        #expect(try tagPayload(try await tagCall(server, "get_library_info"))["tag_count"] as? Int == 0)
        let gotten = try tagPayload(try await tagCall(server, "get_reference", ["id": first.id, "include_image": false]))
        #expect(((gotten["reference"] as? [String: Any])?["tags"] as? [[String: Any]])?.isEmpty == true)
        try Data("invalid catalog".utf8).write(to: store.root.appendingPathComponent("tags.json"))
        for tool in ["list_tags", "list_references", "get_library_info"] {
            #expect(try await tagCall(server, tool)["isError"] as? Bool == true)
        }
        #expect(try await tagCall(server, "get_reference", ["id": first.id, "include_image": false])["isError"] as? Bool == true)
    }
}
