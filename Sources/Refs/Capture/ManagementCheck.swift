#if DEBUG
import AppKit
import Foundation
import RefsCore

extension AppDelegate {
    /// Isolated integration check: a helper process writes while the real LibraryModel watches.
    func checkManagement(model: LibraryModel, window: NSWindow?, directory: URL) {
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/refs-mcp")
                let image = CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                image.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
                image.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
                let original = directory.appendingPathComponent("fixture.png")
                let png = ImageCoding.pngData(from: image.makeImage()!)!
                try png.write(to: original)
                func rpc(_ name: String, _ args: [String: Any] = [:], method: String = "tools/call") throws -> [String: Any] {
                    let process = Process()
                    process.executableURL = helper
                    var environment = ProcessInfo.processInfo.environment
                    environment["REFS_LIBRARY"] = model.store.root.path
                    process.environment = environment
                    let input = Pipe(), output = Pipe()
                    process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
                    try process.run()
                    let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method, "params": ["name": name, "arguments": args]]
                    var data = try JSONSerialization.data(withJSONObject: request); data.append(10)
                    try input.fileHandleForWriting.write(contentsOf: data); try input.fileHandleForWriting.close()
                    let response = try output.fileHandleForReading.readToEnd()!
                    process.waitUntilExit()
                    guard process.terminationStatus == 0,
                          let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                          let result = json["result"] as? [String: Any], result["isError"] as? Bool != true else {
                        throw LibraryError.invalidInput("Fixture MCP request failed: \(name)")
                    }
                    return result
                }
                func check(_ condition: Bool, _ message: String) throws {
                    if !condition { throw LibraryError.invalidInput(message) }
                }
                let tools = try rpc("", method: "tools/list")["tools"] as! [[String: Any]]
                try check(tools.count == 8, "Expected eight tools")
                let add = try rpc("add_references", ["items": [["path": original.path, "note": "Initial fixture note"]]])
                let results = (add["structuredContent"] as! [String: Any])["results"] as! [[String: Any]]
                let reference = results[0]["reference"] as! [String: Any]
                let id = reference["id"] as! String
                try await Task.sleep(for: .milliseconds(450))
                try check(model.refs.contains { $0.id == id }, "Added reference did not appear through the watcher")
                model.selectedID = id
                _ = try rpc("update_reference", ["id": id, "expected_revision": 1, "patch": ["note": "Updated through MCP"]])
                try await Task.sleep(for: .milliseconds(450))
                try check(model.reference(id: id)?.note == "Updated through MCP", "Edit did not appear")
                do {
                    _ = try model.updateNote(id: id, note: "Stale app note", expectedRevision: 1)
                    throw LibraryError.invalidInput("Stale app edit was accepted")
                } catch LibraryError.conflict {}
                if let window, let content = try? await ScreenCapturer.shareableContent(),
                   let (image, _) = try? await ScreenCapturer.captureWindow(id: CGWindowID(window.windowNumber), content: content) {
                    try ImageCoding.pngData(from: image)?.write(to: directory.appendingPathComponent("library-native.png"))
                }
                _ = try rpc("trash_references", ["ids": [id]])
                try await Task.sleep(for: .milliseconds(450))
                try check(!model.refs.contains { $0.id == id } && model.trashRefs.contains { $0.id == id }, "Trash did not refresh")
                model.restore(ids: [id])
                try check(model.refs.contains { $0.id == id }, "App restore did not work")
                _ = try rpc("restore_references", ["ids": [id]])
                try check(try Data(contentsOf: original) == png, "Original file changed")
                let info = try rpc("get_library_info")["structuredContent"] as! [String: Any]
                try check(info["active_count"] as? Int == 1 && info["trashed_count"] as? Int == 0, "Unexpected counts")
                try "PASS: 8 tools; helper addition/edit visible in app; stale app edit rejected; MCP trash/app restore; original unchanged.\n"
                    .write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            } catch {
                try? "FAIL: \(error)\n".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
