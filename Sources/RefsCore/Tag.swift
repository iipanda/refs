import Foundation

/// Portable names for the native macOS system-color palette.
public enum TagColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray
}

/// Shared library metadata. References store only stable tag IDs so edits need no sidecar rewrites.
public struct LibraryTag: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var color: TagColor
    public var revision: Int

    public init(id: String, name: String, color: TagColor, revision: Int = 1) {
        self.id = id
        self.name = name
        self.color = color
        self.revision = revision
    }
}
