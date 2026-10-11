#if DEBUG
import AppKit
import AVFoundation
import RefsCore

extension AppDelegate {
    /// Exercises the real encoder against our own colored fixture window, never the user's content.
    func checkRecording(to directory: URL) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Refs recording fixture"
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.red.cgColor
        window.contentView = view
        window.orderFrontRegardless()
        Task { @MainActor in
            let recorder = VideoRecorder()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await Task.sleep(for: .milliseconds(200))
                try await recorder.start(frame: window.frame, windowID: CGWindowID(window.windowNumber))
                try await Task.sleep(for: .milliseconds(800))
                view.layer?.backgroundColor = NSColor.blue.cgColor
                try await Task.sleep(for: .milliseconds(800))
                let url = try await recorder.stop()
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
                let first = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
                let last = try await generator.image(at: CMTime(seconds: 1.2, preferredTimescale: 600)).image
                guard let firstPNG = ImageCoding.pngData(from: first), let lastPNG = ImageCoding.pngData(from: last),
                      firstPNG != lastPNG, duration > 1.2 else { throw CocoaError(.fileReadCorruptFile) }
                try firstPNG.write(to: directory.appendingPathComponent("first.png"))
                try lastPNG.write(to: directory.appendingPathComponent("last.png"))
                let store = LibraryStore(root: directory.appendingPathComponent("Library"))
                let ref = try store.add(pngData: firstPNG, pixelWidth: first.width, pixelHeight: first.height,
                    app: SourceApp(name: "Fixture", bundleID: nil), windowTitle: "Recording check",
                    web: nil, note: "Red changes to blue", videoURL: url, duration: duration)
                guard store.loadAll() == [ref] else { throw CocoaError(.fileReadCorruptFile) }
                recorder.discardFile()
                let report = "PASS: actual window stream encoded and decoded; frames differ; duration=\(duration); saved movie + poster round trip.\n"
                try report.write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            } catch {
                recorder.discardFile()
                try? "FAIL: \(error)\n".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            }
            window.close()
            NSApp.terminate(nil)
        }
    }
}
#endif
