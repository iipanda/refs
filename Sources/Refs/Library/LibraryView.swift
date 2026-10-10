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
    var openSettings: () -> Void = {}
    @State private var sidebar: SidebarItem? = .all
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            sidebarList
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            grid
                // Attached to the grid, not the split view, so they stay in the grid's part of the
                // toolbar and move aside when the details panel opens instead of covering it.
                .searchable(text: $search, placement: .toolbar, prompt: "Search notes, sites, apps")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: openSettings) {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .help("Settings (⌘,)")
                    }
                }
                // The details panel only exists while something is selected.
                .inspector(isPresented: inspectorPresented) {
                    Group {
                        if let ref = model.reference(id: model.selectedID) {
                            InspectorView(model: model, ref: ref)
                                .id(ref.id)
                        } else if model.selection.count > 1 {
                            BulkInspectorView(model: model, refs: model.selectedRefs)
                        }
                    }
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
        }
        .frame(minWidth: 700, minHeight: 520)
        .onChange(of: visibleRefs.map(\.id), initial: true) { _, ids in
            model.visibleIDs = ids
            // Switching sections or searching drops selected cards that are no longer shown.
            model.selection.retain(ids)
        }
        .confirmationDialog(deletionTitle, isPresented: deletionPresented) {
            Button("Delete", role: .destructive) {
                model.delete(ids: Set(model.pendingDeletion.map(\.id)))
                model.pendingDeletion = []
            }
        } message: {
            Text(model.pendingDeletion.count == 1
                 ? "The screenshot and its note are removed from the library."
                 : "The screenshots and their notes are removed from the library.")
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { !model.selection.isEmpty },
            set: { if !$0 { model.selection.clear() } }
        )
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { !model.pendingDeletion.isEmpty },
            set: { if !$0 { model.pendingDeletion = [] } }
        )
    }

    private var deletionTitle: String {
        let count = model.pendingDeletion.count
        return count == 1 ? "Delete this reference?" : "Delete \(count) references?"
    }

    /// Click selects one card (or clears it if it was the only one), ⌘-click toggles, ⇧-click selects a
    /// range. The second click of a double-click is ignored so opening an image doesn't change the selection.
    private func handleClick(_ ref: Reference) {
        guard currentClickCount() <= 1 else { return }
        let flags = NSEvent.modifierFlags
        let modifier: Selection.Modifier = flags.contains(.command) ? .toggle : flags.contains(.shift) ? .extend : .none
        model.selection.click(ref.id, modifier: modifier, order: model.visibleIDs)
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
                ReferenceGrid(model: model, refs: refs, onClick: handleClick, contextMenu: contextMenu)
                .onExitCommand { model.selection.clear() }
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
        // Right-clicking a card that's part of a multi-selection acts on the whole selection.
        let targets = model.selection.contains(ref.id) && model.selection.count > 1 ? model.selectedRefs : [ref]
        let suffix = targets.count > 1 ? " \(targets.count) References" : " Reference"
        Button(targets.count > 1 ? "Open \(targets.count) Images" : "Open") {
            targets.forEach { NSWorkspace.shared.open(model.imageURL(for: $0)) }
        }
        Button("Copy" + suffix) { copy(model.referenceText(for: targets)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(model.imageURL(for:))) }
        Divider()
        Button("Delete" + (targets.count > 1 ? " \(targets.count) References…" : "…"), role: .destructive) {
            model.requestDeletion(of: targets)
        }
    }
}

/// The scrollable grid of reference cards.
///
/// Selection follows Finder: click, ⌘-click and ⇧-click on cards, drag on empty space for a selection
/// rectangle, and right-click selects the card under the pointer unless it's already selected.
struct ReferenceGrid: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]
    var onClick: (Reference) -> Void = { _ in }
    var contextMenu: (Reference) -> AnyView = { _ in AnyView(EmptyView()) }
    @FocusState private var focused: Bool
    @StateObject private var geometry = GridGeometry()
    /// The selection rectangle being dragged, in grid coordinates.
    @State private var marquee: CGRect?
    /// What was selected when the drag began; kept when ⌘ or ⇧ is held.
    @State private var marqueeBase: Set<String> = []

    static let padding: CGFloat = 16
    static let spacing: CGFloat = 16
    static let minimumCardWidth: CGFloat = 180
    static let windowIdentifier = NSUserInterfaceItemIdentifier("RefsLibrary")
    /// The viewport's coordinate space. Card frames, the drag rectangle and right-clicks all use it,
    /// because in a split view `.global` is per column rather than per window.
    static let space = "ReferenceGrid"

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
                                      selected: model.selection.contains(ref.id),
                                      favicon: { model.favicons[$0] })
                            .frame(width: layout.cardWidth)
                            .background {
                                GeometryReader { card in
                                    Color.clear.preference(key: CardFramesKey.self,
                                                           value: [ref.id: card.frame(in: .named(Self.space))])
                                }
                            }
                            .onTapGesture(count: 2) {
                                model.selection.select(ref.id)
                                NSWorkspace.shared.open(model.imageURL(for: ref))
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                focused = true
                                onClick(ref)
                            })
                            .contextMenu { contextMenu(ref) }
                    }
                }
                .padding(Self.padding)
                // Fill the viewport so clicks and drags below the last row land on the background.
                .frame(width: viewport.size.width, alignment: .topLeading)
                .frame(minHeight: viewport.size.height, alignment: .top)
                .background {
                    // Behind the cards, so it only receives clicks and drags on empty space.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            focused = true
                            model.selection.clear()
                        }
                        .gesture(marqueeGesture)
                        .contextMenu {
                            Button("Select All") { model.selectAllVisible() }
                            if !model.selection.isEmpty {
                                Button("Deselect All") { model.selection.clear() }
                            }
                        }
                }
            }
            .overlay { marqueeOverlay }
            .background(GridAnchor(geometry: geometry))
            .coordinateSpace(name: Self.space)
        }
        .onPreferenceChange(CardFramesKey.self) { geometry.cardFrames = $0 }
        .onAppear {
            geometry.installRightClickSelection(model: model)
            model.gridGeometry = geometry
        }
        .onDisappear { geometry.removeRightClickSelection() }
        // Focusable so ⌫ deletes the selection; ⌘A comes through Edit › Select All.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard !model.selection.isEmpty else { return .ignored }
            model.requestDeletion(of: model.selectedRefs)
            return .handled
        }
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { drag in
                if marquee == nil {
                    focused = true
                    let flags = NSEvent.modifierFlags
                    marqueeBase = flags.contains(.command) || flags.contains(.shift) ? model.selection.ids : []
                }
                let rect = CGRect(x: min(drag.startLocation.x, drag.location.x),
                                  y: min(drag.startLocation.y, drag.location.y),
                                  width: abs(drag.location.x - drag.startLocation.x),
                                  height: abs(drag.location.y - drag.startLocation.y))
                marquee = rect
                let hits = geometry.cardFrames.filter { $0.value.intersects(rect) }.keys
                model.selection.set(marqueeBase.union(hits), order: model.visibleIDs)
            }
            .onEnded { _ in
                marquee = nil
                marqueeBase = []
            }
    }

    /// The translucent rectangle while dragging. The overlay shares the viewport's coordinate space.
    private var marqueeOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let rect = marquee {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Where each visible card is, in the grid's coordinate space.
private struct CardFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Card positions and the right-click monitor. A class, so the event monitor always sees current frames.
final class GridGeometry: ObservableObject {
    var cardFrames: [String: CGRect] = [:]
    /// A flipped view laid exactly under the viewport, for converting window points into grid space.
    weak var anchor: NSView?
    private var monitor: Any?

    /// A window point (bottom-left origin) in grid coordinates (top-left origin).
    func gridPoint(fromWindow point: NSPoint) -> CGPoint? {
        anchor.map { $0.convert(point, from: nil) }
    }

    /// The reverse, for tests that synthesize mouse events.
    func windowPoint(fromGrid point: CGPoint) -> NSPoint? {
        anchor.map { $0.convert(point, to: nil) }
    }

    /// Like Finder: right-clicking (or ⌃-clicking) a card that isn't selected selects just that card
    /// before its menu opens; right-clicking a selected card keeps the whole selection.
    func installRightClickSelection(model: LibraryModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  event.window?.identifier == ReferenceGrid.windowIdentifier,
                  let anchor, event.window === anchor.window,
                  let point = gridPoint(fromWindow: event.locationInWindow),
                  anchor.bounds.contains(point)
            else { return event }
            selectForContextMenu(at: point, model: model)
            return event
        }
    }

    /// Selects the card under `point` (grid coordinates) unless it's already part of the selection.
    func selectForContextMenu(at point: CGPoint, model: LibraryModel) {
        if let id = cardFrames.first(where: { $0.value.contains(point) })?.key, !model.selection.contains(id) {
            model.selection.select(id)
        }
    }

    func removeRightClickSelection() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { removeRightClickSelection() }
}

/// An invisible flipped NSView behind the grid viewport, so AppKit can convert window points into
/// the same top-left coordinate space SwiftUI uses for the grid.
private struct GridAnchor: NSViewRepresentable {
    let geometry: GridGeometry

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()
        geometry.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        geometry.anchor = view
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
                    Button("Delete", role: .destructive) { model.requestDeletion(of: [ref]) }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
        .task(id: ref.id) {
            image = await Thumbnails.load(model.imageURL(for: ref), maxPixelSize: 1200)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            content()
        }
    }
}

/// Shown in place of the details when several references are selected.
struct BulkInspectorView: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                ForEach(Array(refs.prefix(3).enumerated().reversed()), id: \.element.id) { index, ref in
                    StackedThumbnail(url: model.imageURL(for: ref))
                        .rotationEffect(.degrees(Double(index) * -4))
                        .offset(x: CGFloat(index) * -10, y: CGFloat(index) * -6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(refs.count) references selected")
                    .font(.headline)
                Text(sources)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button("Copy \(refs.count) References") { copy(model.referenceText(for: refs)) }
                    .help("Copy ids, sources, notes and file paths, for pasting into an agent prompt")
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(refs.map(model.imageURL(for:)))
                }
                Button("Deselect All") { model.selection.clear() }
            }
            .controlSize(.small)

            Spacer()

            Button("Delete \(refs.count) References…", role: .destructive) { model.requestDeletion(of: refs) }
                .controlSize(.small)
        }
        .padding(16)
    }

    /// e.g. "stripe.com, Linear and 2 more".
    private var sources: String {
        var seen = Set<String>()
        let names = refs.map(\.sourceLabel).filter { seen.insert($0).inserted }
        guard names.count > 3 else { return ListFormatter.localizedString(byJoining: names) }
        return names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more"
    }
}

private struct StackedThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 200, height: 130)
            .overlay(alignment: .topLeading) {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .task(id: url) { image = await Thumbnails.load(url, maxPixelSize: 520) }
    }
}

/// The click count of the event being handled. `NSEvent.clickCount` throws for non-mouse events,
/// and by the time a SwiftUI gesture ends the current event isn't always a mouse event.
func currentClickCount() -> Int {
    guard let event = NSApp.currentEvent else { return 1 }
    switch event.type {
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
        return event.clickCount
    default:
        return 1
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
