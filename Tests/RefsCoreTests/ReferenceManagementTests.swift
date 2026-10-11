import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import CoreVideo
@testable import RefsCore

@Suite struct ReferenceManagementTests {
    @Test func additionPreservesOriginalAndRetriesDoNotOverwriteMetadata() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.ensureExists()
        let original = store.root.appendingPathComponent("original.png")
        let bytes = try #require(ImageCoding.pngData(from: solidImage(width: 37, height: 19)))
        try bytes.write(to: original)
        let first = try await ReferenceAdder.add(path: original.path, note: "Original taste", store: store)
        #expect(first.added)
        #expect(first.reference.pixelWidth == 37)
        #expect(first.reference.title == "original")
        #expect(first.reference.app.name == "Imported")
        #expect(first.reference.provenance?.originalPath == original.path)
        #expect(try Data(contentsOf: original) == bytes)
        let retry = try await ReferenceAdder.add(path: original.path, note: "Do not overwrite", store: store)
        #expect(!retry.added)
        #expect(retry.reference == first.reference)
        _ = try store.setTrashed(id: first.reference.id, trashed: true)
        let trashedRetry = try await ReferenceAdder.add(path: original.path, store: store)
        #expect(!trashedRetry.added && trashedRetry.reference.isTrashed)
    }

    @Test func metadataPatchesClearOnlyRequestedFieldsAndRejectStaleRevisions() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let ref = try store.add(pngData: ImageCoding.pngData(from: solidImage(width: 4, height: 4))!,
            pixelWidth: 4, pixelHeight: 4, app: SourceApp(name: "Safari", bundleID: "safari"),
            windowTitle: "Old title", web: WebSource(url: "https://example.com", title: "Old page"), note: "Keep")
        let edited = try store.patch(id: ref.id, patch: ReferencePatch(title: .set("New title")), expectedRevision: 1)
        #expect(edited.revision == 2 && edited.note == "Keep")
        do {
            _ = try store.patch(id: ref.id, patch: ReferencePatch(note: "Stale"), expectedRevision: 1)
            Issue.record("Stale update succeeded")
        } catch LibraryError.conflict(let current) { #expect(current == edited) }
        let cleared = try store.patch(id: ref.id, patch: ReferencePatch(note: "", title: .clear, bundleID: .clear, url: .clear), expectedRevision: 2)
        #expect(cleared.title == nil && cleared.web == nil && cleared.app.bundleID == nil && cleared.note.isEmpty)
        #expect(cleared.app.name == "Safari")
        #expect(throws: (any Error).self) {
            try store.patch(id: ref.id, patch: ReferencePatch(url: .set("file:///secret")), expectedRevision: 3)
        }
        #expect(try store.readReference(id: ref.id) == cleared)
    }

    @Test func competingWritersHaveOneWinnerAndTrashRestoreAreRepeatable() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let ref = try store.add(pngData: ImageCoding.pngData(from: solidImage(width: 4, height: 4))!,
            pixelWidth: 4, pixelHeight: 4, app: SourceApp(name: "Test", bundleID: nil), windowTitle: nil, web: nil, note: "")
        let wins = await withTaskGroup(of: Bool.self) { group in
            for n in 0..<12 {
                group.addTask {
                    let writer = LibraryStore(root: store.root)
                    do { _ = try writer.patch(id: ref.id, patch: ReferencePatch(note: "writer \(n)"), expectedRevision: 1); return true }
                    catch { return false }
                }
            }
            var count = 0
            for await win in group where win { count += 1 }
            return count
        }
        #expect(wins == 1)
        #expect(try store.readReference(id: ref.id).revision == 2)
        let trashed = try store.setTrashed(id: ref.id, trashed: true)
        #expect(try store.setTrashed(id: ref.id, trashed: true) == trashed)
        #expect(try store.readAll().isEmpty)
        #expect(try store.readAll(includeTrashed: true).count == 1)
        let restored = try store.setTrashed(id: ref.id, trashed: false)
        #expect(restored.id == ref.id && restored.revision == 4)
        #expect(try store.setTrashed(id: ref.id, trashed: false) == restored)
    }

    @Test func simultaneousDuplicateAddsCommitOnce() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.ensureExists()
        let original = store.root.appendingPathComponent("sample.png")
        try ImageCoding.pngData(from: solidImage(width: 33, height: 11))!.write(to: original)
        let additions = try await withThrowingTaskGroup(of: ReferenceAddition.self) { group in
            for _ in 0..<6 { group.addTask { try await ReferenceAdder.add(path: original.path, store: LibraryStore(root: store.root)) } }
            var result: [ReferenceAddition] = []
            for try await addition in group { result.append(addition) }
            return result
        }
        #expect(additions.filter(\.added).count == 1)
        #expect(Set(additions.map(\.reference.id)).count == 1)
    }

    @Test func malformedAndUnsupportedFilesDoNotCommitReferences() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.ensureExists()
        for ext in ["png", "mp4", "txt"] {
            let file = store.root.appendingPathComponent("broken.\(ext)")
            try Data("not media".utf8).write(to: file)
            do { _ = try await ReferenceAdder.add(path: file.path, store: store); Issue.record("Invalid file was added") }
            catch {}
        }
        #expect(try store.readAll(includeTrashed: true).isEmpty)
        #expect(throws: (any Error).self) { try LibraryStore(root: store.root.appendingPathComponent("broken.txt")).readAll() }
    }

    @Test func jpegAndHEICAreNormalizedWithoutChangingTheSource() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.ensureExists()
        for (ext, type) in [("jpg", UTType.jpeg), ("heic", UTType.heic)] {
            let url = store.root.appendingPathComponent("source.\(ext)")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, solidImage(width: 48, height: 24), nil)
            #expect(CGImageDestinationFinalize(destination))
            let bytes = try Data(contentsOf: url)
            let ref = try await ReferenceAdder.add(path: url.path, store: store).reference
            #expect(ref.pixelWidth == 48 && ref.pixelHeight == 24)
            #expect(store.imageURL(for: ref).pathExtension == "png")
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test func realMOVRemainsPlayableAndKeepsItsContainer() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.ensureExists()
        let url = store.root.appendingPathComponent("motion.mov")
        try await makeMovie(at: url)
        let bytes = try Data(contentsOf: url)
        let ref = try await ReferenceAdder.add(path: url.path, store: store).reference
        #expect(ref.isVideo && (ref.duration ?? 0) > 0)
        #expect(store.mediaURL(for: ref).pathExtension == "mov")
        #expect(try Data(contentsOf: store.mediaURL(for: ref)) == bytes)
        #expect(ImageCoding.thumbnail(at: store.imageURL(for: ref), maxPixelSize: 100) != nil)
        let decoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: store.mediaURL(for: ref))).image(at: .zero).image
        #expect(decoded.width == 32)
    }

    @Test func realWebPDecodesAndNormalizes() async throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.ensureExists()
        // Eight-pixel lossless fixture produced by cwebp; no encoder dependency at test time.
        let bytes = try #require(Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvB8ABAAfQmaaXpP+BiOh/AAA="))
        let path = store.root.appendingPathComponent("sample.webp")
        try bytes.write(to: path)
        let ref = try await ReferenceAdder.add(path: path.path, store: store).reference
        #expect(ref.pixelWidth == 8 && ref.pixelHeight == 8 && !ref.isVideo)
        #expect(try Data(contentsOf: path) == bytes)
    }

    @Test func legacySidecarsDefaultToRevisionOneAndActive() throws {
        let json = """
        {"id":"old","createdAt":"2026-10-10T00:00:00Z","imageFile":"old.png","pixelWidth":1,"pixelHeight":1,"app":{"name":"Test"},"description":"Original note"}
        """
        let ref = try LibraryStore.decoder.decode(Reference.self, from: Data(json.utf8))
        #expect(ref.revision == 1 && !ref.isTrashed && ref.note == "Original note")
    }
}

/// A real encoded fixture; callers verify it through the production importer.
func makeMovie(at url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error! }
    writer.startSession(atSourceTime: .zero)
    for n in 0..<3 {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let pixel = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), n == 0 ? 80 : 220, CVPixelBufferGetBytesPerRow(pixel) * 32)
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for _ in 0..<500 {
            if input.isReadyForMoreMediaData { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(n), timescale: 2)))
    }
    writer.endSession(atSourceTime: CMTime(value: 3, timescale: 2))
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error! }
}
