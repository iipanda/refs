import Foundation

/// A folder of `<id>.png` images, each with a `<id>.json` sidecar.
///
/// The menu-bar app is the only writer. Every write goes to a temporary file that is renamed into
/// place, so the MCP helper can read the folder at any time without seeing half-written files.
public final class LibraryStore: @unchecked Sendable {
    public let root: URL
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    public func ensureExists() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// All references, newest first. Sidecars that fail to decode, or whose image is missing, are skipped.
    public func loadAll() -> [Reference] {
        guard let files = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = Self.decoder
        let refs = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Reference? in
                guard let data = try? Data(contentsOf: url),
                      let ref = try? decoder.decode(Reference.self, from: data),
                      fileManager.fileExists(atPath: imageURL(for: ref).path)
                else { return nil }
                return ref
            }
        return refs.sorted { $0.createdAt > $1.createdAt }
    }

    public func reference(id: String) -> Reference? {
        guard Self.isValidID(id),
              let data = try? Data(contentsOf: sidecarURL(id: id))
        else { return nil }
        return try? Self.decoder.decode(Reference.self, from: data)
    }

    /// Saves a new reference. `pngData` is written first so a sidecar never points at a missing image.
    @discardableResult
    public func add(
        pngData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        app: SourceApp,
        windowTitle: String?,
        web: WebSource?,
        note: String,
        createdAt: Date = Date()
    ) throws -> Reference {
        try ensureExists()
        // ISO 8601 sidecars keep whole seconds, so round now to keep the returned value equal to what's on disk.
        let createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        let id = Self.makeID(date: createdAt)
        let ref = Reference(
            id: id,
            createdAt: createdAt,
            imageFile: "\(id).png",
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            app: app,
            windowTitle: windowTitle,
            web: web,
            note: note
        )
        try pngData.write(to: imageURL(for: ref), options: .atomic)
        try writeSidecar(ref)
        return ref
    }

    public func update(_ ref: Reference) throws {
        try writeSidecar(ref)
    }

    public func delete(id: String) throws {
        guard Self.isValidID(id) else { return }
        let ref = reference(id: id)
        try? fileManager.removeItem(at: sidecarURL(id: id))
        if let ref {
            try? fileManager.removeItem(at: imageURL(for: ref))
        }
    }

    public func imageURL(for ref: Reference) -> URL {
        root.appendingPathComponent(ref.imageFile, isDirectory: false)
    }

    // MARK: - Private

    private func sidecarURL(id: String) -> URL {
        root.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private func writeSidecar(_ ref: Reference) throws {
        let data = try Self.encoder.encode(ref)
        try data.write(to: sidecarURL(id: ref.id), options: .atomic)
    }

    /// IDs sort chronologically and contain no path separators, e.g. `20261009-104312-a1b2`.
    static func makeID(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(4).lowercased()
        return "\(formatter.string(from: date))-\(suffix)"
    }

    /// Guards against path traversal when an ID comes from an agent.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } && id.unicodeScalars.allSatisfy(\.isASCII)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
