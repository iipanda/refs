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
        } content: {
            grid
                .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        } detail: {
            if let ref = model.reference(id: model.selectedID) {
                InspectorView(model: model, ref: ref)
                    .id(ref.id)
            } else {
                Text("Select a reference")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search notes, sites, apps")
        .frame(minWidth: 900, minHeight: 520)
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
                        Label(entry.name, systemImage: "globe")
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
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 16)], spacing: 18) {
                        ForEach(refs) { ref in
                            ReferenceCard(ref: ref, imageURL: model.imageURL(for: ref),
                                          selected: model.selectedID == ref.id)
                                .onTapGesture(count: 2) { NSWorkspace.shared.open(model.imageURL(for: ref)) }
                                .simultaneousGesture(TapGesture().onEnded { model.selectedID = ref.id })
                                .contextMenu { contextMenu(for: ref) }
                        }
                    }
                    .padding(16)
                }
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
    private func contextMenu(for ref: Reference) -> some View {
        Button("Open") { NSWorkspace.shared.open(model.imageURL(for: ref)) }
        Button("Copy Reference") { copy(model.referenceText(for: ref)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.imageURL(for: ref)]) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(id: ref.id) }
    }
}

struct ReferenceCard: View {
    let ref: Reference
    let imageURL: URL
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(.quaternary.opacity(0.6))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(height: 118)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 0.5)
            )

            HStack(spacing: 5) {
                AppIcon(bundleID: ref.app.bundleID, size: 14)
                Text(ref.sourceLabel)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Text(ref.note.isEmpty ? (ref.title ?? "No note") : ref.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
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
                            Link(web.url.replacingOccurrences(of: "https://", with: ""), destination: url)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    row("Captured") {
                        Text("\(ref.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ref.pixelWidth) × \(ref.pixelHeight)")
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
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.imageURL(for: ref)]) }
                    Spacer()
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 260)
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
