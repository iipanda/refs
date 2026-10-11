import CoreGraphics
import Foundation
import Testing
@testable import RefsCore

func makeTempLibrary() -> LibraryStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("refs-tests-\(UUID().uuidString)", isDirectory: true)
    return LibraryStore(root: url)
}

func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.4, green: 0.3, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Suite struct LibraryStoreTests {
    @Test func addThenLoadRoundTripsAllFields() throws {
        let store = makeTempLibrary()
        let png = try #require(ImageCoding.pngData(from: solidImage(width: 40, height: 20), scale: 2))
        let saved = try store.add(
            pngData: png, pixelWidth: 40, pixelHeight: 20,
            app: SourceApp(name: "Safari", bundleID: "com.apple.Safari"),
            windowTitle: "Checkout | Stripe",
            web: WebSource(url: "https://www.stripe.com/payments/checkout", title: "Checkout | Stripe"),
            note: "Pinned price summary"
        )

        let loaded = store.loadAll()
        #expect(loaded == [saved])
        #expect(loaded[0].web?.host == "stripe.com")
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: saved).path))

        // The sidecar uses "description" as the key for the user's note.
        let json = try String(contentsOf: store.root.appendingPathComponent("\(saved.id).json"), encoding: .utf8)
        #expect(json.contains("\"description\" : \"Pinned price summary\""))
    }

    @Test func loadAllIsNewestFirstAndSkipsBrokenEntries() throws {
        let store = makeTempLibrary()
        let png = try #require(ImageCoding.pngData(from: solidImage(width: 4, height: 4)))
        let app = SourceApp(name: "Linear", bundleID: "com.linear")
        let older = try store.add(pngData: png, pixelWidth: 4, pixelHeight: 4, app: app, windowTitle: nil, web: nil,
                                  note: "old", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = try store.add(pngData: png, pixelWidth: 4, pixelHeight: 4, app: app, windowTitle: nil, web: nil,
                                  note: "new", createdAt: Date(timeIntervalSince1970: 2_000))

        try Data("not json".utf8).write(to: store.root.appendingPathComponent("garbage.json"))
        let orphan = try store.add(pngData: png, pixelWidth: 4, pixelHeight: 4, app: app, windowTitle: nil, web: nil, note: "orphan")
        try FileManager.default.removeItem(at: store.imageURL(for: orphan))

        #expect(store.loadAll().map(\.id) == [newer.id, older.id])
    }

    @Test func updateAndDelete() throws {
        let store = makeTempLibrary()
        let png = try #require(ImageCoding.pngData(from: solidImage(width: 4, height: 4)))
        var ref = try store.add(pngData: png, pixelWidth: 4, pixelHeight: 4,
                                app: SourceApp(name: "Figma", bundleID: nil), windowTitle: nil, web: nil, note: "")
        ref.note = "Properties panel grouping"
        try store.update(ref)
        #expect(store.reference(id: ref.id)?.note == "Properties panel grouping")

        try store.delete(id: ref.id)
        #expect(store.loadAll().isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: ref).path))
        #expect(store.reference(id: ref.id)?.isTrashed == true)
    }

    @Test func rejectsPathTraversalIDs() {
        let store = makeTempLibrary()
        #expect(store.reference(id: "../../etc/passwd") == nil)
        #expect(!LibraryStore.isValidID("a/b"))
        #expect(!LibraryStore.isValidID(""))
        #expect(LibraryStore.isValidID("20261009-104312-a1b2"))
    }

    @Test func videoRoundTripAndDeletionRetainPosterAndMovie() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let movie = Data([1, 2, 3, 4]) // Storage treats an already finalized movie as opaque bytes.
        try movie.write(to: source)
        let png = try #require(ImageCoding.pngData(from: solidImage(width: 40, height: 20)))
        let saved = try store.add(pngData: png, pixelWidth: 40, pixelHeight: 20,
            app: SourceApp(name: "Safari", bundleID: nil), windowTitle: "Animation", web: nil,
            note: "Spring motion", videoURL: source, duration: 2.5)
        #expect(saved.isVideo)
        #expect(saved.duration == 2.5)
        #expect(store.loadAll() == [saved])
        #expect(try Data(contentsOf: store.mediaURL(for: saved)) == movie)
        #expect(ImageCoding.thumbnail(at: store.imageURL(for: saved), maxPixelSize: 128) != nil)
        try store.delete(id: saved.id)
        #expect(FileManager.default.fileExists(atPath: store.imageURL(for: saved).path))
        #expect(FileManager.default.fileExists(atPath: store.mediaURL(for: saved).path))
        #expect(store.reference(id: saved.id)?.isTrashed == true)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func missingMovieIsSkippedAndFailedImportLeavesNoFiles() throws {
        let store = makeTempLibrary()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let png = try #require(ImageCoding.pngData(from: solidImage(width: 4, height: 4)))
        let missing = store.root.appendingPathComponent("missing.mp4")
        #expect(throws: (any Error).self) {
            try store.add(pngData: png, pixelWidth: 4, pixelHeight: 4,
                app: SourceApp(name: "Test", bundleID: nil), windowTitle: nil, web: nil,
                note: "", videoURL: missing)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.root.path).filter { $0 != ".library.lock" }.isEmpty)
        let screenshot = try store.add(pngData: png, pixelWidth: 4, pixelHeight: 4,
            app: SourceApp(name: "Test", bundleID: nil), windowTitle: nil, web: nil, note: "")
        var video = screenshot
        video.videoFile = "missing.mp4"
        try store.update(video)
        #expect(store.loadAll().isEmpty)
    }

    @Test func oldScreenshotSidecarsDecodeWithoutVideoFields() throws {
        let ref = Reference(id: "old", createdAt: Date(), imageFile: "old.png", pixelWidth: 1,
            pixelHeight: 1, app: SourceApp(name: "Test", bundleID: nil))
        let data = try LibraryStore.encoder.encode(ref)
        let decoded = try LibraryStore.decoder.decode(Reference.self, from: data)
        #expect(!decoded.isVideo)
        #expect(decoded.videoFile == nil)
        #expect(decoded.duration == nil)
    }

    @Test func idsAreChronological() {
        let a = LibraryStore.makeID(date: Date(timeIntervalSince1970: 1_000))
        let b = LibraryStore.makeID(date: Date(timeIntervalSince1970: 2_000))
        #expect(a < b)
        #expect(LibraryStore.isValidID(a))
    }
}

@Suite struct ImageCodingTests {
    @Test func thumbnailDownscalesLongestEdgeAndNeverUpscales() throws {
        let store = makeTempLibrary()
        try store.ensureExists()
        let url = store.root.appendingPathComponent("big.png")
        try #require(ImageCoding.pngData(from: solidImage(width: 3000, height: 1000))).write(to: url)

        let small = try #require(ImageCoding.thumbnail(at: url, maxPixelSize: 1024))
        #expect(small.width == 1024)
        #expect(small.height == 341 || small.height == 342)

        let same = try #require(ImageCoding.thumbnail(at: url, maxPixelSize: 5000))
        #expect(same.width == 3000)
    }
}
