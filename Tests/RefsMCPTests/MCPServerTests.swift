import CoreGraphics
import Foundation
import ImageIO
import Testing
import RefsCore
@testable import RefsMCP

private func makeStore() throws -> (LibraryStore, Reference, Reference) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("refs-mcp-\(UUID().uuidString)")
    let store = LibraryStore(root: root)
    let context = CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
    let png = ImageCoding.pngData(from: context.makeImage()!)!
    let web = try store.add(
        pngData: png, pixelWidth: 2000, pixelHeight: 1000,
        app: SourceApp(name: "Safari", bundleID: "com.apple.Safari"), windowTitle: "Checkout | Stripe",
        web: WebSource(url: "https://stripe.com/payments/checkout", title: "Checkout | Stripe"),
        note: "Pinned price summary", createdAt: Date(timeIntervalSince1970: 2_000_000_000)
    )
    let native = try store.add(
        pngData: png, pixelWidth: 2000, pixelHeight: 1000,
        app: SourceApp(name: "Linear", bundleID: "com.linear"), windowTitle: "Issues", web: nil,
        note: "Dense issue list", createdAt: Date(timeIntervalSince1970: 1_000_000_000)
    )
    return (store, web, native)
}

private func send(_ server: MCPServer, _ message: [String: Any]) async throws -> [String: Any]? {
    let data = try JSONSerialization.data(withJSONObject: message)
    guard let response = await server.handle(data) else { return nil }
    return try JSONSerialization.jsonObject(with: response) as? [String: Any]
}

private func call(_ server: MCPServer, _ tool: String, _ args: [String: Any] = [:]) async throws -> [String: Any] {
    let response = try #require(try await send(server, [
        "jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": tool, "arguments": args],
    ]))
    return try #require(response["result"] as? [String: Any])
}

private func text(_ result: [String: Any]) -> String {
    (result["content"] as? [[String: Any]] ?? [])
        .filter { $0["type"] as? String == "text" }
        .compactMap { $0["text"] as? String }
        .joined(separator: "\n")
}

@Suite struct MCPServerTests {
    @Test func videoReturnsPosterAndIdentifiesMoviePath() async throws {
        let (store, screenshot, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let source = store.root.appendingPathComponent("fixture.mp4")
        try Data([1, 2, 3]).write(to: source)
        let ref = try store.add(pngData: Data(contentsOf: store.imageURL(for: screenshot)),
            pixelWidth: 2000, pixelHeight: 1000, app: screenshot.app, windowTitle: "Motion", web: nil,
            note: "Transition timing", videoURL: source, duration: 3.2)
        let result = try await call(MCPServer(store: store), "get_reference", ["id": ref.id])
        #expect(text(result).contains("type: video"))
        #expect(text(result).contains("duration: 3.2 seconds"))
        #expect(text(result).contains(store.mediaURL(for: ref).path))
        #expect(text(result).contains("poster frame"))
        let contents = try #require(result["content"] as? [[String: Any]])
        #expect(contents.contains { $0["type"] as? String == "image" && $0["mimeType"] as? String == "image/png" })
    }

    @Test func initializeNegotiatesVersionAndAdvertisesTools() async throws {
        let (store, _, _) = try makeStore()
        let server = MCPServer(store: store)

        let known = try #require(try await send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                   "params": ["protocolVersion": "2025-06-18", "capabilities": [:]]]))
        let result = try #require(known["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect(known["id"] as? Int == 1)

        let unknown = try #require(try await send(server, ["jsonrpc": "2.0", "id": "a", "method": "initialize",
                                                     "params": ["protocolVersion": "1999-01-01"]]))
        #expect((unknown["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.supportedProtocolVersions[0])
        #expect(unknown["id"] as? String == "a")
    }

    @Test func notificationsGetNoResponseAndUnknownMethodsError() async throws {
        let (store, _, _) = try makeStore()
        let server = MCPServer(store: store)
        #expect(try await send(server, ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)

        let response = try #require(try await send(server, ["jsonrpc": "2.0", "id": 3, "method": "resources/list"]))
        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32601)

        let parse = try #require(await server.handle(Data("{nope".utf8)))
        let parsed = try #require(try JSONSerialization.jsonObject(with: parse) as? [String: Any])
        #expect((parsed["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test func toolsListHasCorrectlyAnnotatedTools() async throws {
        let (store, _, _) = try makeStore()
        let response = try #require(try await send(MCPServer(store: store), ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
        let tools = try #require((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["list_references", "get_reference", "list_sources", "get_library_info", "list_tags", "create_tag", "update_tag", "delete_tag", "tag_references", "untag_references", "add_references", "update_reference", "trash_references", "restore_references"])
        for tool in tools {
            #expect((tool["inputSchema"] as? [String: Any])?["type"] as? String == "object")
            let read = ["list_references", "get_reference", "list_sources", "get_library_info", "list_tags"].contains(tool["name"] as? String ?? "")
            #expect((tool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == read)
        }
    }

    @Test func listReferencesFiltersAndDescribes() async throws {
        let (store, web, native) = try makeStore()
        let server = MCPServer(store: store)

        let all = text(try await call(server, "list_references"))
        #expect(all.contains("2 references found"))
        #expect(all.range(of: web.id)!.lowerBound < all.range(of: native.id)!.lowerBound)

        let site = text(try await call(server, "list_references", ["site": "stripe.com"]))
        #expect(site.contains("id: \(web.id)"))
        #expect(site.contains("url: https://stripe.com/payments/checkout"))
        #expect(site.contains("what the user likes: Pinned price summary"))
        #expect(!site.contains(native.id))

        let app = text(try await call(server, "list_references", ["app": "linear", "limit": 5]))
        #expect(app.contains("id: \(native.id)") && !app.contains(web.id))

        let none = text(try await call(server, "list_references", ["query": "nothing-matches"]))
        #expect(none.contains("No references match"))
    }

    @Test func getReferenceReturnsDownscaledImage() async throws {
        let (store, web, _) = try makeStore()
        let server = MCPServer(store: store)

        let result = try await call(server, "get_reference", ["id": web.id])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        let image = try #require(content.first { $0["type"] as? String == "image" })
        #expect(image["mimeType"] as? String == "image/png")
        let data = try #require(Data(base64Encoded: image["data"] as? String ?? ""))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1024)

        let textOnly = try await call(server, "get_reference", ["id": web.id, "include_image": false])
        #expect((textOnly["content"] as? [[String: Any]])?.count == 1)
    }

    @Test func getReferenceErrorsAreToolErrors() async throws {
        let (store, _, _) = try makeStore()
        let server = MCPServer(store: store)
        #expect(try await call(server, "get_reference", ["id": "../../secret"])["isError"] as? Bool == true)
        #expect(try await call(server, "get_reference", [:])["isError"] as? Bool == true)

        let unknown = try #require(try await send(server, ["jsonrpc": "2.0", "id": 9, "method": "tools/call",
                                                     "params": ["name": "delete_everything"]]))
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32602)
    }

    @Test func listSourcesSeparatesSitesAndApps() async throws {
        let (store, _, _) = try makeStore()
        let output = text(try await call(MCPServer(store: store), "list_sources"))
        #expect(output.contains("Websites (filter with site):\n- stripe.com (1)"))
        #expect(output.contains("Apps (filter with app):\n- Linear [com.linear] (1)"))
    }

    @Test func emptyLibraryIsExplained() async throws {
        let empty = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("refs-empty-\(UUID())"))
        let server = MCPServer(store: empty)
        #expect(text(try await call(server, "list_references")).contains("library is empty"))
        #expect(text(try await call(server, "list_sources")).contains("library is empty"))
    }
}

@Suite struct MCPManagementTests {
    @Test func batchAddEditTrashRestoreAndPartialFailures() async throws {
        let (store, screenshot, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let original = store.root.appendingPathComponent("external.png")
        try #require(ImageCoding.downscaledPNG(at: store.imageURL(for: screenshot), maxPixelSize: 50)).write(to: original)
        let originalBytes = try Data(contentsOf: original)
        let server = MCPServer(store: store)
        let added = try await call(server, "add_references", ["items": [
            ["path": original.path, "note": "Layout", "source": ["app": "Browser", "url": "https://example.com"]],
            ["path": store.root.appendingPathComponent("missing.mov").path],
        ]])
        #expect(added["isError"] as? Bool == false)
        let payload = try #require(added["structuredContent"] as? [String: Any])
        #expect(payload["succeeded"] as? Int == 1 && payload["failed"] as? Int == 1)
        let results = try #require(payload["results"] as? [[String: Any]])
        #expect(results[0]["status"] as? String == "added")
        let reference = try #require(results[0]["reference"] as? [String: Any])
        let id = try #require(reference["id"] as? String)
        let revision = try #require(reference["revision"] as? Int)
        #expect(text(try await call(server, "get_reference", ["id": id, "include_image": false])).contains("added:"))
        let retry = try await call(server, "add_references", ["items": [["path": original.path, "note": "Overwrite?"]]])
        let retryResults = try #require((retry["structuredContent"] as? [String: Any])?["results"] as? [[String: Any]])
        #expect(retryResults[0]["status"] as? String == "existing")
        #expect(store.reference(id: id)?.note == "Layout")
        let update = try await call(server, "update_reference", ["id": id, "expected_revision": revision,
            "patch": ["title": "Updated", "note": "", "source": ["url": NSNull(), "bundle_id": NSNull()]]])
        #expect(update["isError"] as? Bool == false)
        #expect(store.reference(id: id)?.title == "Updated" && store.reference(id: id)?.web == nil)
        let conflict = try await call(server, "update_reference", ["id": id, "expected_revision": revision, "patch": ["note": "Stale"]])
        let error = try #require((conflict["structuredContent"] as? [String: Any])?["error"] as? [String: Any])
        #expect(error["code"] as? String == "revision_conflict" && error["current_reference"] != nil)
        let trash = try await call(server, "trash_references", ["ids": [id, "missing"]])
        #expect((trash["structuredContent"] as? [String: Any])?["failed"] as? Int == 1)
        #expect(try store.readAll().allSatisfy { $0.id != id })
        let info = try await call(server, "get_library_info")
        #expect((info["structuredContent"] as? [String: Any])?["trashed_count"] as? Int == 1)
        let restored = try await call(server, "restore_references", ["ids": [id]])
        #expect(restored["isError"] as? Bool == false && store.reference(id: id)?.isTrashed == false)
        #expect(try Data(contentsOf: original) == originalBytes)
    }

    @Test func malformedMutationArgumentsAreRejectedBeforeAnyWrites() async throws {
        let (store, ref, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let server = MCPServer(store: store)
        for args: [String: Any] in [
            ["id": ref.id, "expected_revision": true, "patch": ["note": "Bad"]],
            ["id": ref.id, "expected_revision": 1.5, "patch": ["note": "Bad"]],
            ["id": ref.id, "expected_revision": 1, "patch": ["imageFile": "../../secret"]],
            ["id": ref.id, "expected_revision": 1, "patch": ["source": ["app": NSNull()]]],
            ["id": ref.id, "expected_revision": 1, "patch": ["note": NSNull()]],
        ] {
            #expect(try await call(server, "update_reference", args)["isError"] as? Bool == true)
        }
        #expect(try await call(server, "add_references", ["items": []])["isError"] as? Bool == true)
        #expect(try await call(server, "trash_references", ["ids": []])["isError"] as? Bool == true)
        #expect(store.reference(id: ref.id) == ref)
    }

    @Test func paginationHandlesTiesFiltersAndTrashWithoutRepeatedIDs() async throws {
        let (store, ref, _) = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        for n in 0..<3 {
            _ = try store.add(pngData: Data(contentsOf: store.imageURL(for: ref)), pixelWidth: 2000, pixelHeight: 1000,
                app: ref.app, windowTitle: nil, web: nil, note: "\(n)", createdAt: ref.createdAt)
        }
        let server = MCPServer(store: store)
        var seen: [String] = []
        var cursor: String?
        repeat {
            var args: [String: Any] = ["limit": 1, "kind": "image"]
            if let cursor { args["cursor"] = cursor }
            let result = try await call(server, "list_references", args)
            let payload = try #require(result["structuredContent"] as? [String: Any])
            let refs = try #require(payload["references"] as? [[String: Any]])
            seen += refs.compactMap { $0["id"] as? String }
            cursor = payload["next_cursor"] as? String
        } while cursor != nil
        #expect(seen.count == 5 && Set(seen).count == 5)
        _ = try store.setTrashed(id: ref.id, trashed: true)
        let hidden = try await call(server, "list_references", ["kind": "image"])
        let shown = try await call(server, "list_references", ["kind": "image", "include_trashed": true])
        #expect((hidden["structuredContent"] as? [String: Any])?["total"] as? Int == 4)
        #expect((shown["structuredContent"] as? [String: Any])?["total"] as? Int == 5)
        #expect(try await call(server, "list_references", ["cursor": "invalid"])["isError"] as? Bool == true)
    }

    @Test func libraryReadFailuresDoNotPretendTheLibraryIsEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let server = MCPServer(store: LibraryStore(root: root))
        for tool in ["list_references", "list_sources", "get_library_info"] {
            #expect(try await call(server, tool)["isError"] as? Bool == true)
        }
    }
}
