import Foundation

/// One saved design reference: a screenshot plus where it came from and what the user liked about it.
public struct Reference: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var createdAt: Date
    /// Image file name, relative to the library folder.
    public var imageFile: String
    /// Optional movie; imageFile is its poster when present. Missing on older screenshot sidecars.
    public var videoFile: String?
    public var duration: Double?
    public var customTitle: String?
    public var fingerprint: String?
    public var provenance: ReferenceProvenance?
    public var trashedAt: Date?
    private var savedRevision: Int?
    public var revision: Int {
        get { savedRevision ?? 1 }
        set { savedRevision = newValue }
    }
    public var isTrashed: Bool { trashedAt != nil }
    public var isVideo: Bool { videoFile != nil }
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var app: SourceApp
    /// Title of the captured window, when known.
    public var windowTitle: String?
    /// Set when the capture came from a browser tab.
    public var web: WebSource?
    /// The user's one-line "what I like about it". Stored as `description` in JSON.
    public var note: String

    public init(
        id: String,
        createdAt: Date,
        imageFile: String,
        pixelWidth: Int,
        pixelHeight: Int,
        app: SourceApp,
        windowTitle: String? = nil,
        web: WebSource? = nil,
        note: String = "",
        videoFile: String? = nil,
        duration: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageFile = imageFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.app = app
        self.windowTitle = windowTitle
        self.web = web
        self.note = note
        self.videoFile = videoFile
        self.duration = duration
    }

    enum CodingKeys: String, CodingKey {
        case videoFile, duration, customTitle, fingerprint, provenance, trashedAt
        case savedRevision = "revision"
        case id, createdAt, imageFile, pixelWidth, pixelHeight, app, windowTitle, web
        case note = "description"
    }

    /// Short human label for the source: the website host for browser captures, otherwise the app name.
    public var sourceLabel: String {
        web?.host ?? app.name
    }

    /// Best available title: page title, then window title.
    public var title: String? {
        let candidates = [customTitle, web?.title, windowTitle]
        return candidates.compactMap { $0 }.first { !$0.isEmpty }
    }
}

public struct SourceApp: Codable, Hashable, Sendable {
    public var name: String
    public var bundleID: String?

    public init(name: String, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct WebSource: Codable, Hashable, Sendable {
    public var url: String
    public var title: String?

    public init(url: String, title: String?) {
        self.url = url
        self.title = title
    }

    /// Host without a leading `www.`, e.g. `stripe.com`.
    public var host: String? {
        WebSource.normalizedHost(url)
    }

    /// Accepts a full URL, a bare host, or a host with a path, and returns the lowercased host without `www.`.
    public static func normalizedHost(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: withScheme)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public struct ReferenceProvenance: Codable, Hashable, Sendable {
    public var addedAt: Date
    public var originalPath: String
    public var originalFilename: String
    public init(addedAt: Date, originalPath: String, originalFilename: String) {
        self.addedAt = addedAt
        self.originalPath = originalPath
        self.originalFilename = originalFilename
    }
}
