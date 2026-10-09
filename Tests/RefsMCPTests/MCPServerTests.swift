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

private func send(_ server: MCPServer, _ message: [String: Any]) throws -> [String: Any]? {
    let data = try JSONSerialization.data(withJSONObject: message)
    guard let response = server.handle(data) else { return nil }
    return try JSONSerialization.jsonObject(with: response) as? [String: Any]
}

private func call(_ server: MCPServer, _ tool: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
    let response = try #require(try send(server, [
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
    @Test func initializeNegotiatesVersionAndAdvertisesTools() throws {
        let (store, _, _) = try makeStore()
        let server = MCPServer(store: store)

        let known = try #require(try send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                   "params": ["protocolVersion": "2025-06-18", "capabilities": [:]]]))
        let result = try #require(known["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect(known["id"] as? Int == 1)

        let unknown = try #require(try send(server, ["jsonrpc": "2.0", "id": "a", "method": "initialize",
                                                     "params": ["protocolVersion": "1999-01-01"]]))
        #expect((unknown["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.supportedProtocolVersions[0])
        #expect(unknown["id"] as? String == "a")
    }

    @Test func notificationsGetNoResponseAndUnknownMethodsError() throws {
        let (store, _, _) = try makeStore()
        let server = MCPServer(store: store)
        #expect(try send(server, ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)

        let response = try #require(try send(server, ["jsonrpc": "2.0", "id": 3, "method": "resources/list"]))
        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32601)

        let parse = try #require(server.handle(Data("{nope".utf8)))
        let parsed = try #require(try JSONSerialization.jsonObject(with: parse) as? [String: Any])
        #expect((parsed["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test func toolsListHasThreeReadOnlyTools() throws {
        let (store, _, _) = try makeStore()
        let response = try #require(try send(MCPServer(store: store), ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
        let tools = try #require((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["list_references", "get_reference", "list_sources"])
        for tool in tools {
            #expect((tool["inputSchema"] as? [String: Any])?["type"] as? String == "object")
        }
    }

    @Test func listReferencesFiltersAndDescribes() throws {
        let (store, web, native) = try makeStore()
        let server = MCPServer(store: store)

        let all = text(try call(server, "list_references"))
        #expect(all.contains("2 references found"))
        #expect(all.range(of: web.id)!.lowerBound < all.range(of: native.id)!.lowerBound)

        let site = text(try call(server, "list_references", ["site": "stripe.com"]))
        #expect(site.contains("id: \(web.id)"))
        #expect(site.contains("url: https://stripe.com/payments/checkout"))
        #expect(site.contains("what the user likes: Pinned price summary"))
        #expect(!site.contains(native.id))

        let app = text(try call(server, "list_references", ["app": "linear", "limit": 5]))
        #expect(app.contains("id: \(native.id)") && !app.contains(web.id))

        let none = text(try call(server, "list_references", ["query": "nothing-matches"]))
        #expect(none.contains("No references match"))
    }

    @Test func getReferenceReturnsDownscaledImage() throws {
        let (store, web, _) = try makeStore()
        let server = MCPServer(store: store)

        let result = try call(server, "get_reference", ["id": web.id])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        let image = try #require(content.first { $0["type"] as? String == "image" })
        #expect(image["mimeType"] as? String == "image/png")
        let data = try #require(Data(base64Encoded: image["data"] as? String ?? ""))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1024)

        let textOnly = try call(server, "get_reference", ["id": web.id, "include_image": false])
        #expect((textOnly["content"] as? [[String: Any]])?.count == 1)
    }

    @Test func getReferenceErrorsAreToolErrors() throws {
        let (store, _, _) = try makeStore()
        let server = MCPServer(store: store)
        #expect(try call(server, "get_reference", ["id": "../../secret"])["isError"] as? Bool == true)
        #expect(try call(server, "get_reference", [:])["isError"] as? Bool == true)

        let unknown = try #require(try send(server, ["jsonrpc": "2.0", "id": 9, "method": "tools/call",
                                                     "params": ["name": "delete_everything"]]))
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32602)
    }

    @Test func listSourcesSeparatesSitesAndApps() throws {
        let (store, _, _) = try makeStore()
        let output = text(try call(MCPServer(store: store), "list_sources"))
        #expect(output.contains("Websites (filter with site):\n- stripe.com (1)"))
        #expect(output.contains("Apps (filter with app):\n- Linear [com.linear] (1)"))
    }

    @Test func emptyLibraryIsExplained() throws {
        let empty = LibraryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("refs-empty-\(UUID())"))
        let server = MCPServer(store: empty)
        #expect(text(try call(server, "list_references")).contains("library is empty"))
        #expect(text(try call(server, "list_sources")).contains("library is empty"))
    }
}
