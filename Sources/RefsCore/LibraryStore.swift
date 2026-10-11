import Foundation
import CryptoKit
import Darwin

/// Atomic sidecars and a cross-process lock shared by the app and every MCP helper.
public final class LibraryStore: @unchecked Sendable {
    public let root: URL
    private let fileManager = FileManager.default
    public init(root: URL) { self.root = root }

    public func ensureExists() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Compatibility convenience; interactive callers use readAll to report access failures.
    public func loadAll() -> [Reference] { (try? readAll()) ?? [] }

    public func readAll(includeTrashed: Bool = false) throws -> [Reference] {
        let files: [URL]
        do { files = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        var refs: [Reference] = []
        for url in files where url.pathExtension == "json" {
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            guard let ref = try? Self.decoder.decode(Reference.self, from: data),
                  Self.safeFiles(ref), ref.id == url.deletingPathExtension().lastPathComponent,
                  fileManager.fileExists(atPath: imageURL(for: ref).path),
                  !ref.isVideo || fileManager.fileExists(atPath: mediaURL(for: ref).path),
                  includeTrashed || !ref.isTrashed else { continue }
            refs.append(ref)
        }
        return refs.sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id > $1.id }
    }

    public func reference(id: String) -> Reference? { try? readReference(id: id) }

    public func readReference(id: String) throws -> Reference {
        guard Self.isValidID(id) else { throw LibraryError.invalidInput("Invalid reference id.") }
        let data: Data
        do { data = try Data(contentsOf: sidecarURL(id: id)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { throw LibraryError.notFound(id) }
        let ref = try Self.decoder.decode(Reference.self, from: data)
        guard ref.id == id, Self.safeFiles(ref) else { throw LibraryError.invalidInput("Invalid reference sidecar.") }
        return ref
    }

    @discardableResult
    public func add(pngData: Data, pixelWidth: Int, pixelHeight: Int, app: SourceApp,
                    windowTitle: String?, web: WebSource?, note: String, createdAt: Date = Date(),
                    videoURL: URL? = nil, duration: Double? = nil) throws -> Reference {
        try commitMedia(pngData: pngData, pixelWidth: pixelWidth, pixelHeight: pixelHeight, app: app,
            windowTitle: windowTitle, web: web, note: note, createdAt: createdAt,
            videoURL: videoURL, duration: duration).reference
    }

    @discardableResult
    public func commitMedia(pngData: Data, pixelWidth: Int, pixelHeight: Int, app: SourceApp,
                    windowTitle: String?, web: WebSource?, note: String, createdAt: Date = Date(),
                    videoURL: URL? = nil, duration: Double? = nil,
                    customTitle: String? = nil, provenance: ReferenceProvenance? = nil,
                    fingerprint: String? = nil, deduplicate: Bool = false) throws -> ReferenceAddition {
        try withWriteLock {
            if deduplicate, let fingerprint {
                for ref in try readAll(includeTrashed: true) where ref.isVideo == (videoURL != nil) {
                    let existingHash = try ref.fingerprint ?? Self.fingerprint(at: mediaURL(for: ref))
                    if existingHash == fingerprint { return ReferenceAddition(reference: ref, added: false) }
                }
            }
            let date = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
            let id = Self.makeID(date: date)
            let ext = videoURL?.pathExtension.lowercased() ?? "mp4"
            guard videoURL == nil || ["mp4", "mov"].contains(ext) else {
                throw LibraryError.invalidInput("Unsupported video container.")
            }
            var ref = Reference(id: id, createdAt: date, imageFile: "\(id).png", pixelWidth: pixelWidth,
                pixelHeight: pixelHeight, app: app, windowTitle: windowTitle, web: web, note: note,
                videoFile: videoURL == nil ? nil : "\(id).\(ext)", duration: duration)
            ref.customTitle = customTitle
            ref.provenance = provenance
            ref.fingerprint = try fingerprint ?? (videoURL.map { try Self.fingerprint(at: $0) } ?? Self.fingerprint(data: pngData))
            ref.revision = 1
            do {
                try pngData.write(to: imageURL(for: ref), options: .atomic)
                if let videoURL { try fileManager.copyItem(at: videoURL, to: mediaURL(for: ref)) }
                try writeSidecar(ref) // Publishing the sidecar commits the prepared media.
            } catch {
                try? fileManager.removeItem(at: imageURL(for: ref))
                if ref.isVideo { try? fileManager.removeItem(at: mediaURL(for: ref)) }
                throw error
            }
            return ReferenceAddition(reference: ref, added: true)
        }
    }

    /// Legacy whole-record writes are revision-checked too.
    public func update(_ ref: Reference) throws {
        try withWriteLock {
            let current = try readReference(id: ref.id)
            guard current.revision == ref.revision else { throw LibraryError.conflict(current) }
            guard Self.safeFiles(ref) else { throw LibraryError.invalidInput("Invalid media filenames.") }
            var updated = ref
            updated.revision += 1
            try writeSidecar(updated)
        }
    }

    @discardableResult
    public func patch(id: String, patch: ReferencePatch, expectedRevision: Int) throws -> Reference {
        try withWriteLock {
            var ref = try readReference(id: id)
            guard ref.revision == expectedRevision else { throw LibraryError.conflict(ref) }
            let original = ref
            try patch.apply(to: &ref)
            if ref != original { ref.revision += 1; try writeSidecar(ref) }
            return ref
        }
    }

    @discardableResult
    public func setTrashed(id: String, trashed: Bool) throws -> Reference {
        try withWriteLock {
            var ref = try readReference(id: id)
            if ref.isTrashed != trashed {
                ref.trashedAt = trashed ? Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) : nil
                ref.revision += 1
                try writeSidecar(ref)
            }
            return ref
        }
    }

    /// Existing app Delete actions now retain files for restoration.
    public func delete(id: String) throws { _ = try setTrashed(id: id, trashed: true) }
    public func imageURL(for ref: Reference) -> URL { root.appendingPathComponent(ref.imageFile) }
    public func mediaURL(for ref: Reference) -> URL { root.appendingPathComponent(ref.videoFile ?? ref.imageFile) }

    private func withWriteLock<T>(_ body: () throws -> T) throws -> T {
        try ensureExists()
        let fd = open(root.appendingPathComponent(".library.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    private static func safeFiles(_ ref: Reference) -> Bool {
        isValidID(ref.id) && [ref.imageFile, ref.videoFile].compactMap { $0 }.allSatisfy {
            !$0.isEmpty && URL(fileURLWithPath: $0).lastPathComponent == $0 && !$0.contains("/") && !$0.contains("\\")
        }
    }
    private func sidecarURL(id: String) -> URL { root.appendingPathComponent("\(id).json") }
    private func writeSidecar(_ ref: Reference) throws { try Self.encoder.encode(ref).write(to: sidecarURL(id: ref.id), options: .atomic) }

    public static func fingerprint(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func fingerprint(data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func makeID(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: date))-\(UUID().uuidString.lowercased())"
    }
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && id.unicodeScalars.allSatisfy(\.isASCII)
    }
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601; return encoder
    }()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }()
}

public struct ReferenceAddition: Sendable {
    public var reference: Reference
    public var added: Bool
}
