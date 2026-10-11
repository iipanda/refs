import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Validates and prepares external media, then commits through the shared library writer.
public enum ReferenceAdder {
    public static let supportedFormats = ["png", "jpg", "jpeg", "heic", "webp", "mp4", "mov"]

    public static func add(path: String, note: String = "", title: String? = nil,
                           source: ReferencePatch = ReferencePatch(), store: LibraryStore) async throws -> ReferenceAddition {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw LibraryError.invalidInput("path must be an absolute local file path.") }
        let original = URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath()
        let values = try original.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw LibraryError.invalidInput("path must name a regular file.") }
        let ext = original.pathExtension.lowercased()
        guard supportedFormats.contains(ext) else { throw LibraryError.invalidInput("Unsupported format: \(ext).") }

        // Snapshot inputs before decoding/hashing; an external edit cannot change committed bytes afterward.
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("refs-add-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let file = stage.appendingPathComponent("input.\(ext)")
        try FileManager.default.copyItem(at: original, to: file)
        let video = ["mp4", "mov"].contains(ext)
        let image: CGImage
        let duration: Double?
        if video {
            let asset = AVURLAsset(url: file)
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0, !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
                throw LibraryError.invalidInput("The video has no decodable video track.")
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            image = try await generator.image(at: .zero).image
            duration = seconds
        } else {
            guard let decoder = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let type = CGImageSourceGetType(decoder) as String?,
                  [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.webP.identifier].contains(type),
                  let decoded = ImageCoding.thumbnail(at: file, maxPixelSize: 65536) else {
                throw LibraryError.invalidInput("The image could not be decoded as PNG, JPEG, HEIC, or WebP.")
            }
            image = decoded
            duration = nil
        }
        guard let png = ImageCoding.pngData(from: image) else { throw LibraryError.invalidInput("The poster could not be encoded.") }
        var metadata = Reference(id: "prepared", createdAt: Date(), imageFile: "prepared.png",
            pixelWidth: image.width, pixelHeight: image.height, app: SourceApp(name: "Imported", bundleID: nil), note: note)
        try source.apply(to: &metadata)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        return try store.commitMedia(pngData: png, pixelWidth: image.width, pixelHeight: image.height,
            app: metadata.app, windowTitle: nil, web: metadata.web, note: note, createdAt: now,
            videoURL: video ? file : nil, duration: duration,
            customTitle: title ?? original.deletingPathExtension().lastPathComponent,
            provenance: ReferenceProvenance(addedAt: now, originalPath: original.path, originalFilename: original.lastPathComponent),
            fingerprint: video ? LibraryStore.fingerprint(at: file) : LibraryStore.fingerprint(data: png), deduplicate: true)
    }
}
