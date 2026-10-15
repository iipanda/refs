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
        try readSidecars().filter { ref in
            fileManager.fileExists(atPath: imageURL(for: ref).path) &&
            (!ref.isVideo || fileManager.fileExists(atPath: mediaURL(for: ref).path)) &&
            (includeTrashed || !ref.isTrashed)
        }
    }

    /// Includes temporarily missing media so catalog deletion also cleans those references.
    private func readSidecars() throws -> [Reference] {
        let files: [URL]
        do { files = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        var refs: [Reference] = []
        for url in files where url.pathExtension == "json" && url.lastPathComponent != "tags.json" {
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            guard let ref = try? Self.decoder.decode(Reference.self, from: data),
                  Self.safeFiles(ref), ref.id == url.deletingPathExtension().lastPathComponent else { continue }
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
            try validateTagIDs(ref.tagIDs)
            var updated = ref
            updated.tagIDs = Self.uniqueIDs(ref.tagIDs)
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

    /// A missing catalog is an unchanged, tagless library. Invalid catalogs are reported, never replaced.
    public func readTags() throws -> [LibraryTag] {
        let data: Data
        do { data = try Data(contentsOf: tagsURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        let tags = try Self.decoder.decode([LibraryTag].self, from: data)
        var ids: Set<String> = []
        var names: [String] = []
        for tag in tags {
            guard Self.isValidID(tag.id), ids.insert(tag.id).inserted, tag.revision > 0,
                  !tag.name.isEmpty, tag.name == tag.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  !names.contains(where: { $0.caseInsensitiveCompare(tag.name) == .orderedSame }) else {
                throw LibraryError.invalidInput("Invalid tag catalog.")
            }
            names.append(tag.name)
        }
        return tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Counts memberships even when media is temporarily missing, matching tag deletion's impact.
    public func tagReferenceCount(id: String, includeTrashed: Bool = true) throws -> Int {
        guard try readTags().contains(where: { $0.id == id }) else { throw LibraryError.unknownTag(id) }
        return try readSidecars().filter { $0.tagIDs.contains(id) && (includeTrashed || !$0.isTrashed) }.count
    }

    @discardableResult
    public func createTag(name: String, color: TagColor? = nil) throws -> LibraryTag {
        try withWriteLock {
            var tags = try readTags()
            let name = try validatedTagName(name, in: tags)
            let color = color ?? TagColor.allCases.min { lhs, rhs in
                tags.filter { $0.color == lhs }.count < tags.filter { $0.color == rhs }.count
            } ?? .red
            let tag = LibraryTag(id: UUID().uuidString.lowercased(), name: name, color: color)
            tags.append(tag)
            try writeTags(tags)
            return tag
        }
    }

    @discardableResult
    public func updateTag(id: String, name: String? = nil, color: TagColor? = nil,
                          expectedRevision: Int? = nil) throws -> LibraryTag {
        try withWriteLock {
            var tags = try readTags()
            guard let index = tags.firstIndex(where: { $0.id == id }) else { throw LibraryError.unknownTag(id) }
            let original = tags[index]
            if let expectedRevision, original.revision != expectedRevision { throw LibraryError.tagConflict(original) }
            if let name { tags[index].name = try validatedTagName(name, in: tags, excluding: id) }
            if let color { tags[index].color = color }
            if tags[index] != original {
                tags[index].revision += 1
                try writeTags(tags)
            }
            return tags[index]
        }
    }

    /// Removes memberships before publishing catalog removal. Interrupted deletion leaves a valid tag,
    /// rather than dangling IDs; any completed sidecar edit still has its own revision.
    @discardableResult
    public func deleteTag(id: String, expectedRevision: Int? = nil) throws -> Int {
        try withWriteLock {
            var tags = try readTags()
            guard let index = tags.firstIndex(where: { $0.id == id }) else { throw LibraryError.unknownTag(id) }
            if let expectedRevision, tags[index].revision != expectedRevision { throw LibraryError.tagConflict(tags[index]) }
            var affected = 0
            for var ref in try readSidecars() where ref.tagIDs.contains(id) {
                ref.tagIDs.removeAll { $0 == id }
                ref.revision += 1
                try writeSidecar(ref)
                affected += 1
            }
            tags.remove(at: index)
            try writeTags(tags)
            return affected
        }
    }

    /// A delta against the latest sidecar keeps independent app and MCP additions from losing tags.
    @discardableResult
    public func setTags(id: String, tagIDs: [String], adding: Bool,
                        expectedRevision: Int? = nil) throws -> Reference {
        try withWriteLock {
            var ref = try readReference(id: id)
            if let expectedRevision, ref.revision != expectedRevision { throw LibraryError.conflict(ref) }
            try validateTagIDs(tagIDs)
            let requested = Set(tagIDs)
            let updated = adding ? Self.uniqueIDs(ref.tagIDs + tagIDs) : ref.tagIDs.filter { !requested.contains($0) }
            if updated != ref.tagIDs {
                ref.tagIDs = updated
                ref.revision += 1
                try writeSidecar(ref)
            }
            return ref
        }
    }

    private var tagsURL: URL { root.appendingPathComponent("tags.json") }

    private func writeTags(_ tags: [LibraryTag]) throws {
        try Self.encoder.encode(tags).write(to: tagsURL, options: .atomic)
    }

    private func validatedTagName(_ input: String, in tags: [LibraryTag], excluding id: String? = nil) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryError.invalidInput("Tag name must not be empty.") }
        guard !tags.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw LibraryError.duplicateTagName(name)
        }
        return name
    }

    private func validateTagIDs(_ ids: [String]) throws {
        let known = Set(try readTags().map(\.id))
        if let unknown = ids.first(where: { !known.contains($0) }) { throw LibraryError.unknownTag(unknown) }
    }

    private static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
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
