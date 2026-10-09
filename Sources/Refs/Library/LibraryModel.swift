import AppKit
import RefsCore

/// The app's in-memory view of the library folder.
final class LibraryModel: ObservableObject {
    @Published private(set) var refs: [Reference] = []
    @Published var selection = Selection()
    /// IDs of the cards currently shown, in grid order. Set by the Library view; used for ⇧-click
    /// ranges and Select All.
    var visibleIDs: [String] = []
    /// References waiting for the user to confirm deletion.
    @Published var pendingDeletion: [Reference] = []

    /// The selected reference ID when exactly one is selected.
    var selectedID: String? {
        get { selection.single }
        set {
            if let newValue { selection.select(newValue) } else { selection.clear() }
        }
    }

    var selectedRefs: [Reference] {
        selection.ordered(by: visibleIDs).compactMap { reference(id: $0) }
    }
    /// Website icons by host, loaded from the library's icon cache.
    @Published private(set) var favicons: [String: NSImage] = [:]
    private(set) var store: LibraryStore
    private var faviconCache: FaviconCache
    private var faviconsInFlight = Set<String>()

    init(root: URL) {
        store = LibraryStore(root: root)
        faviconCache = FaviconCache(libraryRoot: root)
        reload()
    }

    func changeRoot(_ root: URL) {
        store = LibraryStore(root: root)
        faviconCache = FaviconCache(libraryRoot: root)
        favicons = [:]
        selection.clear()
        reload()
    }

    func reload() {
        refs = store.loadAll()
        loadFavicons()
    }

    /// Shows cached icons right away and fetches missing ones in the background, one request per site.
    private func loadFavicons() {
        var pages: [String: String] = [:]
        for ref in refs {
            if let web = ref.web, let host = web.host, pages[host] == nil { pages[host] = web.url }
        }
        let cache = faviconCache
        for (host, page) in pages where favicons[host] == nil && !faviconsInFlight.contains(host) {
            if let url = cache.cachedIcon(host: host), let image = NSImage(contentsOf: url) {
                favicons[host] = image
                continue
            }
            guard cache.needsFetch(host: host) else { continue }
            faviconsInFlight.insert(host)
            Task { @MainActor [weak self] in
                let url = await cache.fetch(host: host, pageURL: page)
                guard let self, cache === self.faviconCache else { return }
                faviconsInFlight.remove(host)
                if let url, let image = NSImage(contentsOf: url) {
                    favicons[host] = image
                }
            }
        }
    }

    func reference(id: String?) -> Reference? {
        guard let id else { return nil }
        return refs.first { $0.id == id }
    }

    func add(_ draft: SaveDraft) throws -> Reference {
        let capture = draft.capture
        guard let png = ImageCoding.pngData(from: capture.image, scale: capture.scale) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let web = draft.web
        let ref = try store.add(
            pngData: png,
            pixelWidth: capture.image.width,
            pixelHeight: capture.image.height,
            app: draft.app,
            windowTitle: web == nil ? draft.windowTitle : capture.windowTitle,
            web: web,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        refs.insert(ref, at: 0)
        loadFavicons()
        return ref
    }

    func updateNote(id: String, note: String) {
        guard let index = refs.firstIndex(where: { $0.id == id }), refs[index].note != note else { return }
        refs[index].note = note
        try? store.update(refs[index])
    }

    func delete(id: String) {
        delete(ids: [id])
    }

    func delete(ids: Set<String>) {
        for id in ids { try? store.delete(id: id) }
        refs.removeAll { ids.contains($0.id) }
        selection.retain(refs.map(\.id))
    }

    /// Asks the Library view to confirm deleting these references.
    func requestDeletion(of refs: [Reference]) {
        guard !refs.isEmpty else { return }
        pendingDeletion = refs
    }

    func selectAllVisible() {
        selection.selectAll(visibleIDs)
    }

    func imageURL(for ref: Reference) -> URL {
        store.imageURL(for: ref)
    }

    /// Text for pasting into an agent prompt. Agents with the MCP server can fetch it by id;
    /// others can open the file path.
    func referenceText(for ref: Reference) -> String {
        var parts = ["Design reference \(ref.id) from Refs"]
        if let web = ref.web {
            parts.append("source: \(web.url)")
        } else {
            parts.append("source: \(ref.app.name)")
        }
        if let title = ref.title { parts.append("title: \(title)") }
        if !ref.note.isEmpty { parts.append("what I like: \(ref.note)") }
        parts.append("image: \(imageURL(for: ref).path)")
        return parts.joined(separator: "\n")
    }

    func referenceText(for refs: [Reference]) -> String {
        refs.map(referenceText(for:)).joined(separator: "\n\n")
    }
}

/// Small thumbnails for the grid and menu, decoded off the main thread and cached.
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func cached(_ url: URL, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: key(url, maxPixelSize))
    }

    static func load(_ url: URL, maxPixelSize: Int) async -> NSImage? {
        if let cached = cached(url, maxPixelSize: maxPixelSize) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let cg = ImageCoding.thumbnail(at: url, maxPixelSize: maxPixelSize) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        }.value
        if let image { cache.setObject(image, forKey: key(url, maxPixelSize)) }
        return image
    }

    static func loadSync(_ url: URL, maxPixelSize: Int) -> NSImage? {
        if let cached = cached(url, maxPixelSize: maxPixelSize) { return cached }
        guard let cg = ImageCoding.thumbnail(at: url, maxPixelSize: maxPixelSize) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: key(url, maxPixelSize))
        return image
    }

    private static func key(_ url: URL, _ size: Int) -> NSString {
        "\(url.path)#\(size)" as NSString
    }
}
