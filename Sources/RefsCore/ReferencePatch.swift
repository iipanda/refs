import Foundation

public enum FieldChange<Value: Sendable>: Sendable {
    case set(Value), clear
}

/// Omitted fields stay unchanged. Optional metadata can explicitly be cleared.
public struct ReferencePatch: Sendable {
    public var note: String?
    public var title: FieldChange<String>?
    public var app: String?
    public var bundleID: FieldChange<String>?
    public var url: FieldChange<String>?

    public init(note: String? = nil, title: FieldChange<String>? = nil, app: String? = nil,
                bundleID: FieldChange<String>? = nil, url: FieldChange<String>? = nil) {
        self.note = note; self.title = title; self.app = app; self.bundleID = bundleID; self.url = url
    }

    func apply(to ref: inout Reference) throws {
        if let note { ref.note = note }
        if let title {
            switch title { case .set(let value): ref.customTitle = value; case .clear: ref.customTitle = nil; ref.windowTitle = nil; ref.web?.title = nil }
        }
        if let app {
            guard !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryError.invalidInput("Source app must not be empty.")
            }
            ref.app.name = app
        }
        if let bundleID {
            switch bundleID { case .set(let value): ref.app.bundleID = value; case .clear: ref.app.bundleID = nil }
        }
        if let url {
            switch url {
            case .set(let value):
                guard let parsed = URL(string: value), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                      parsed.host != nil else { throw LibraryError.invalidInput("Source URL must be an absolute HTTP or HTTPS URL.") }
                ref.web = WebSource(url: value, title: ref.web?.title)
            case .clear: ref.web = nil
            }
        }
    }
}

public enum LibraryError: LocalizedError {
    case invalidInput(String), notFound(String), conflict(Reference)
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .notFound(let id): return "No reference with id \(id)."
        case .conflict(let ref): return "Reference \(ref.id) changed. Current revision is \(ref.revision); read it again before updating."
        }
    }
}
