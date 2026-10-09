import AppKit
import RefsCore
import SwiftUI

enum SidebarItem: Hashable {
    case all, recent
    case app(String)
    case site(String)
}

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var preferences: Preferences
    @State private var sidebar: SidebarItem? = .all
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            grid
                // The details panel only exists while something is selected.
                .inspector(isPresented: inspectorPresented) {
                    if let ref = model.reference(id: model.selectedID) {
                        InspectorView(model: model, ref: ref)
                            .id(ref.id)
                            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                    }
                }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search notes, sites, apps")
        .frame(minWidth: 700, minHeight: 520)
        .onChange(of: sidebar) { deselectIfHidden() }
        .onChange(of: search) { deselectIfHidden() }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { model.reference(id: model.selectedID) != nil },
            set: { if !$0 { model.selectedID = nil } }
        )
    }

    private func deselectIfHidden() {
        if let id = model.selectedID, !visibleRefs.contains(where: { $0.id == id }) {
            model.selectedID = nil
        }
    }

    /// Single click selects, clicking the selected card again deselects. The second click of a
    /// double-click is ignored so opening an image doesn't also deselect it.
    private func toggleSelection(_ ref: Reference) {
        guard (NSApp.currentEvent?.clickCount ?? 1) <= 1 else { return }
        model.selectedID = model.selectedID == ref.id ? nil : ref.id
    }

    // MARK: Sidebar

    private var sidebarList: some View {
        let summary = SourceSummary(refs: model.refs)
        return List(selection: $sidebar) {
            Label("All References", systemImage: "square.grid.2x2")
                .badge(model.refs.count)
                .tag(SidebarItem.all)
            Label("Recent", systemImage: "clock")
                .badge(recentRefs.count)
                .tag(SidebarItem.recent)
            if !summary.apps.isEmpty {
                Section("Apps") {
                    ForEach(summary.apps, id: \.name) { entry in
                        Label { Text(entry.name) } icon: { AppIcon(bundleID: entry.bundleID) }
                            .badge(entry.count)
                            .tag(SidebarItem.app(entry.bundleID ?? entry.name))
                    }
                }
            }
            if !summary.sites.isEmpty {
                Section("Websites") {
                    ForEach(summary.sites, id: \.name) { entry in
                        Label { Text(entry.name) } icon: { SiteIcon(image: model.favicons[entry.name]) }
                            .badge(entry.count)
                            .tag(SidebarItem.site(entry.name))
                    }
                }
            }
        }
    }

    // MARK: Grid

    private var recentRefs: [Reference] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return model.refs.filter { $0.createdAt >= cutoff }
    }

    private var visibleRefs: [Reference] {
        var refs: [Reference]
        switch sidebar ?? .all {
        case .all: refs = model.refs
        case .recent: refs = recentRefs
        case .app(let key): refs = model.refs.filter { $0.web == nil && ($0.app.bundleID ?? $0.app.name) == key }
        case .site(let host): refs = model.refs.filter { $0.web?.host == host }
        }
        return ReferenceQuery(text: search).apply(to: refs)
    }

    private var grid: some View {
        let refs = visibleRefs
        return Group {
            if model.refs.isEmpty {
                emptyLibrary
            } else if refs.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReferenceGrid(model: model, refs: refs, onToggle: toggleSelection, contextMenu: contextMenu)
                .onExitCommand { model.selectedID = nil }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(refs.count) reference\(refs.count == 1 ? "" : "s")")
    }

    private var title: String {
        switch sidebar ?? .all {
        case .all: "All References"
        case .recent: "Recent"
        case .app(let key): model.refs.first { ($0.app.bundleID ?? $0.app.name) == key }?.app.name ?? key
        case .site(let host): host
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("No references yet")
                .font(.headline)
            if let shortcut = preferences.captureArea {
                Text("Press \(shortcut.displayString) anywhere to capture an area.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for ref: Reference) -> AnyView {
        AnyView(contextMenuItems(for: ref))
    }

    @ViewBuilder
    private func contextMenuItems(for ref: Reference) -> some View {
        Button("Open") { NSWorkspace.shared.open(model.imageURL(for: ref)) }
        Button("Copy Reference") { copy(model.referenceText(for: ref)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.imageURL(for: ref)]) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(id: ref.id) }
    }
}

/// The scrollable grid of reference cards.
struct ReferenceGrid: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]
    var onToggle: (Reference) -> Void = { _ in }
    var contextMenu: (Reference) -> AnyView = { _ in AnyView(EmptyView()) }

    static let padding: CGFloat = 16
    static let spacing: CGFloat = 16
    static let minimumCardWidth: CGFloat = 180

    /// Columns and card width for a given viewport width. Cards get an exact width so nothing inside
    /// them (a wide screenshot, a long title) can make a card wider than its column.
    static func layout(for width: CGFloat) -> (columns: Int, cardWidth: CGFloat) {
        let available = max(width - padding * 2, minimumCardWidth)
        let columns = max(1, Int((available + spacing) / (minimumCardWidth + spacing)))
        let cardWidth = ((available - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        return (columns, cardWidth)
    }

    var body: some View {
        GeometryReader { viewport in
            let layout = Self.layout(for: viewport.size.width)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: Self.spacing),
                                         count: layout.columns),
                          alignment: .leading, spacing: 18) {
                    ForEach(refs) { ref in
                        ReferenceCard(ref: ref, imageURL: model.imageURL(for: ref),
                                      selected: model.selectedID == ref.id,
                                      favicon: { model.favicons[$0] })
                            .frame(width: layout.cardWidth)
                            .onTapGesture(count: 2) {
                                model.selectedID = ref.id
                                NSWorkspace.shared.open(model.imageURL(for: ref))
                            }
                            .simultaneousGesture(TapGesture().onEnded { onToggle(ref) })
                            .contextMenu { contextMenu(ref) }
                    }
                }
                .padding(Self.padding)
                // Fill the viewport so clicks below the last row land on the background.
                .frame(width: viewport.size.width, alignment: .topLeading)
                .frame(minHeight: viewport.size.height, alignment: .top)
                .background {
                    // Behind the cards, so it only receives clicks on empty space.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedID = nil }
                }
            }
        }
    }
}

struct ReferenceCard: View {
    let ref: Reference
    let imageURL: URL
    let selected: Bool
    var favicon: (String) -> NSImage? = { _ in nil }
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The thumbnail sits in an overlay so its fill size can't widen the card past its column.
            Rectangle()
                .fill(.quaternary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 118)
                .overlay(alignment: .topLeading) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 0.5)
            )

            HStack(spacing: 5) {
                if let host = ref.web?.host {
                    SiteIcon(image: favicon(host), size: 14)
                } else {
                    AppIcon(bundleID: ref.app.bundleID, size: 14)
                }
                Text(ref.sourceLabel)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Text(ref.note.isEmpty ? (ref.title ?? "No note") : ref.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .task(id: ref.id) {
            image = await Thumbnails.load(imageURL, maxPixelSize: 520)
        }
    }
}

struct InspectorView: View {
    @ObservedObject var model: LibraryModel
    let ref: Reference
    @State private var note: String
    @State private var image: NSImage?
    @State private var confirmingDelete = false

    init(model: LibraryModel, ref: Reference) {
        self.model = model
        self.ref = ref
        _note = State(initialValue: ref.note)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.6))
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture(count: 2) { NSWorkspace.shared.open(model.imageURL(for: ref)) }
                .help("Double-click to open")

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    row("Source") {
                        HStack(spacing: 5) {
                            AppIcon(bundleID: ref.app.bundleID, size: 14)
                            Text(ref.web.map { "\(ref.app.name) · \($0.host ?? "")" } ?? ref.app.name)
                        }
                    }
                    if let title = ref.title {
                        row("Title") { Text(title).lineLimit(2) }
                    }
                    if let web = ref.web, let url = URL(string: web.url) {
                        row("URL") {
                            Link(destination: url) {
                                Text(verbatim: web.url.replacingOccurrences(of: "https://", with: ""))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .help(web.url)
                        }
                    }
                    row("Captured") {
                        Text(verbatim: "\(ref.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ref.pixelWidth) × \(ref.pixelHeight) px")
                    }
                }
                .font(.callout)

                VStack(alignment: .leading, spacing: 5) {
                    Text("What I like")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Add a note", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: note) { _, value in
                            model.updateNote(id: ref.id, note: value.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                }

                HStack {
                    Button("Copy Reference") { copy(model.referenceText(for: ref)) }
                        .help("Copy the id, source, note and file path, for pasting into an agent prompt")
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.imageURL(for: ref)]) }
                    Spacer(minLength: 8)
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
        .task(id: ref.id) {
            image = await Thumbnails.load(model.imageURL(for: ref), maxPixelSize: 1200)
        }
        .confirmationDialog("Delete this reference?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.delete(id: ref.id) }
        } message: {
            Text("The screenshot and its note are removed from the library.")
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            content()
        }
    }
}

func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// A website's icon, or a globe while it loads or when the site has none.
struct SiteIcon: View {
    let image: NSImage?
    var size: CGFloat = 16

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "globe")
                .frame(width: size, height: size)
        }
    }
}
