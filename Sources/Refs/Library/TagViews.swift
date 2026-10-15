import AppKit
import RefsCore
import SwiftUI

extension TagColor {
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }

    var displayName: String { rawValue.capitalized }

    /// Menus render SF Symbols as monochrome templates, so color swatches are drawn as real images.
    var swatch: NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            nsColor.setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = displayName
        return image
    }
}

/// How many of the targeted references carry a tag.
enum TagCoverage: Equatable {
    case none, some(Int), all

    init(_ tag: LibraryTag, in refs: [Reference]) {
        let count = refs.filter { $0.tagIDs.contains(tag.id) }.count
        self = count == 0 ? .none : count == refs.count ? .all : .some(count)
    }
}

struct TagDot: View {
    let tag: LibraryTag
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Color(nsColor: tag.color.nsColor))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .frame(width: size, height: size)
            .help(tag.name)
            .accessibilityLabel("\(tag.name), \(tag.color.displayName) tag")
    }
}

/// A compact cue on a card; the inspector shows the complete names.
struct TagDots: View {
    let tags: [LibraryTag]

    var body: some View {
        HStack(spacing: -2) {
            ForEach(Array(tags.prefix(3))) { tag in
                Circle()
                    .fill(Color(nsColor: tag.color.nsColor))
                    .frame(width: 7, height: 7)
                    // A ring in the window background separates overlapping dots.
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-1.5))
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)
            }
        }
        .fixedSize()
        .help(tags.map(\.name).joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tags: \(tags.map(\.name).joined(separator: ", "))")
    }
}

/// A row label with the tag's real color, for menus.
private struct TagMenuLabel: View {
    let tag: LibraryTag
    var detail: String?

    var body: some View {
        Label {
            Text(detail.map { "\(tag.name)  \($0)" } ?? tag.name)
        } icon: {
            Image(nsImage: tag.color.swatch)
        }
    }
}

/// Checkable tags for menus: checked when every target has the tag, with a count when only some do.
struct TagMenuItems: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]
    var onNewTag: (() -> Void)?

    var body: some View {
        ForEach(model.tags) { tag in
            let coverage = TagCoverage(tag, in: refs)
            Toggle(isOn: Binding(get: { coverage == .all },
                                 set: { model.setTag(tag, on: refs, adding: $0) })) {
                if case .some(let count) = coverage {
                    TagMenuLabel(tag: tag, detail: "\(count) of \(refs.count)")
                } else {
                    TagMenuLabel(tag: tag)
                }
            }
        }
        if let onNewTag {
            if !model.tags.isEmpty { Divider() }
            Button("New Tag…", action: onNewTag)
        }
    }
}

struct TagSelectionMenu: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]
    var onNewTag: (() -> Void)?

    var body: some View {
        Menu {
            TagMenuItems(model: model, refs: refs, onNewTag: onNewTag)
        } label: {
            Label("Tags", systemImage: "tag")
        }
        .disabled(refs.isEmpty)
    }
}

/// The palette as checkable swatches.
struct TagColorMenuItems: View {
    let selected: TagColor?
    let onSelect: (TagColor) -> Void

    var body: some View {
        ForEach(TagColor.allCases, id: \.self) { color in
            Toggle(isOn: Binding(get: { color == selected }, set: { if $0 { onSelect(color) } })) {
                Label { Text(color.displayName) } icon: { Image(nsImage: color.swatch) }
            }
        }
    }
}

// MARK: Tag field

/// Chips for the tags on the targets, plus a picker to add, toggle or create tags.
/// `toggle` adds a tag to every target, or removes it when all of them already have it.
struct TagField: View {
    let tags: [LibraryTag]
    let coverage: (LibraryTag) -> TagCoverage
    let toggle: (LibraryTag) -> Void
    let applyToAll: (LibraryTag) -> Void
    let remove: (LibraryTag) -> Void
    let create: (String) throws -> Void
    var recolor: ((LibraryTag, TagColor) -> Void)?
    var targetCount = 1
    @State private var picking = false

    private var applied: [LibraryTag] { tags.filter { coverage($0) != .none } }

    var body: some View {
        TagFlowLayout {
            ForEach(applied) { tag in
                TagChip(tag: tag, coverage: coverage(tag), targetCount: targetCount,
                        applyToAll: { applyToAll(tag) }, remove: { remove(tag) },
                        recolor: recolor.map { recolor in { recolor(tag, $0) } })
            }
            AddTagButton(compact: !applied.isEmpty) { picking.toggle() }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                TagPicker(tags: tags, coverage: coverage, toggle: toggle, create: create)
            }
        }
    }
}

/// A dashed capsule after the chips: "Add Tag" when empty, a plus otherwise.
private struct AddTagButton: View {
    let compact: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                if !compact { Text("Add Tag") }
            }
            .font(.caption)
            .foregroundStyle(hovering ? .primary : .secondary)
            .padding(.horizontal, compact ? 0 : 8)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(Color.primary.opacity(hovering ? 0.08 : 0.03)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add a tag")
        .accessibilityLabel("Add tag")
    }
}

private struct TagChip: View {
    let tag: LibraryTag
    let coverage: TagCoverage
    let targetCount: Int
    let applyToAll: () -> Void
    let remove: () -> Void
    var recolor: ((TagColor) -> Void)?
    @State private var hovering = false

    private var partial: Int? { if case .some(let count) = coverage { count } else { nil } }
    private var color: Color { Color(nsColor: tag.color.nsColor) }

    var body: some View {
        HStack(spacing: 5) {
            TagDot(tag: tag, size: 7).accessibilityHidden(true)
            Text(tag.name).lineLimit(1)
            if let partial {
                Text("\(partial)/\(targetCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0.45)
            .help(targetCount > 1 ? "Remove \(tag.name) from the selected references" : "Remove \(tag.name)")
            .accessibilityLabel("Remove \(tag.name)")
        }
        .font(.caption)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(minHeight: 22)
        .background(Capsule().fill(color.opacity(partial == nil ? 0.16 : 0.06)))
        .overlay(Capsule().strokeBorder(color.opacity(partial == nil ? 0.35 : 0.6),
                                        style: StrokeStyle(lineWidth: partial == nil ? 0.5 : 1, dash: partial == nil ? [] : [3, 2])))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        // A partial tag fills in for the rest of the selection when clicked.
        .onTapGesture { if partial != nil { applyToAll() } }
        .help(partial.map { "\(tag.name) is on \($0) of \(targetCount) selected references. Click to add it to all." } ?? tag.name)
        .contextMenu {
            if partial != nil { Button("Add to All Selected", action: applyToAll) }
            Button(targetCount > 1 ? "Remove from Selected" : "Remove Tag", action: remove)
            if let recolor {
                Menu("Color") { TagColorMenuItems(selected: tag.color, onSelect: recolor) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(partial.map { "\(tag.name), on \($0) of \(targetCount)" } ?? tag.name)
    }
}

// MARK: Picker

/// Find-or-create list. Typing filters; Return applies the highlighted tag or creates the typed one.
struct TagPicker: View {
    let tags: [LibraryTag]
    let coverage: (LibraryTag) -> TagCoverage
    let toggle: (LibraryTag) -> Void
    let create: (String) throws -> Void
    @State private var query: String
    /// Nothing is highlighted until the user types or uses the arrow keys, so Return can't toggle a tag by accident.
    @State private var highlighted: Int?
    @State private var error: String?
    @FocusState private var focused: Bool

    init(tags: [LibraryTag], coverage: @escaping (LibraryTag) -> TagCoverage, toggle: @escaping (LibraryTag) -> Void,
         create: @escaping (String) throws -> Void, initialQuery: String = "") {
        self.tags = tags
        self.coverage = coverage
        self.toggle = toggle
        self.create = create
        _query = State(initialValue: initialQuery)
        _highlighted = State(initialValue: initialQuery.isEmpty ? nil : 0)
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [LibraryTag] {
        trimmed.isEmpty ? tags : tags.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
    private var canCreate: Bool {
        !trimmed.isEmpty && !tags.contains { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }
    private var rowCount: Int { matches.count + (canCreate ? 1 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(tags.isEmpty ? "Name a new tag" : "Find or create a tag", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onSubmit(activate)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onChange(of: query) { highlighted = trimmed.isEmpty ? nil : 0; error = nil }
            Divider()
            if rowCount == 0 {
                Text(tags.isEmpty ? "Tags you create appear here." : "No matching tags")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, tag in
                                row(index: index, action: { toggle(tag) }) {
                                    stateIcon(coverage(tag))
                                    TagDot(tag: tag, size: 9)
                                    Text(tag.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if case .some(let count) = coverage(tag) {
                                        Text("\(count) selected").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .id(index)
                            }
                            if canCreate {
                                row(index: matches.count, action: createTyped) {
                                    Image(systemName: "plus").frame(width: 12).foregroundStyle(.secondary)
                                    Text("Create “\(trimmed)”").lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .id(matches.count)
                            }
                        }
                        .padding(5)
                    }
                    .frame(maxHeight: 260)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: highlighted) { if let highlighted { proxy.scrollTo(highlighted) } }
                }
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 250)
        .onAppear { focused = true }
    }

    private func row<Content: View>(index: Int, action: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(index == highlighted ? Color.accentColor.opacity(0.18) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = index } }
    }

    private func stateIcon(_ coverage: TagCoverage) -> some View {
        Image(systemName: coverage == .all ? "checkmark" : "minus")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 12)
            .foregroundStyle(Color.accentColor)
            .opacity(coverage == .none ? 0 : 1)
            .accessibilityLabel(coverage == .all ? "Applied" : coverage == .none ? "" : "Applied to some")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard rowCount > 0 else { return .ignored }
        highlighted = highlighted.map { ($0 + delta + rowCount) % rowCount } ?? (delta > 0 ? 0 : rowCount - 1)
        return .handled
    }

    private func activate() {
        guard let highlighted else { return }
        if highlighted < matches.count { toggle(matches[highlighted]) }
        else if canCreate { createTyped() }
    }

    private func createTyped() {
        do {
            try create(trimmed)
            query = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Library adapters

/// The tag field bound to library references, for the inspectors.
struct ReferenceTagField: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]

    var body: some View {
        TagField(
            tags: model.tags,
            coverage: { TagCoverage($0, in: refs) },
            toggle: { tag in model.setTag(tag, on: refs, adding: TagCoverage(tag, in: refs) != .all) },
            applyToAll: { model.setTag($0, on: refs, adding: true) },
            remove: { model.setTag($0, on: refs, adding: false) },
            create: { try model.createTag(name: $0, on: refs) },
            recolor: { model.updateTag($0, color: $1) },
            targetCount: refs.count)
    }
}

/// Keeps tags within the inspector width, including a single unusually long tag name.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(width: bounds.width, subviews: subviews)
        for (index, item) in layout.items.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                                  proposal: ProposedViewSize(item.size))
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (size: CGSize, items: [CGRect]) {
        let available = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        var items: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, available ?? ideal.width), height: nil))
            if let available, x > 0, x + size.width > available {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: available ?? usedWidth, height: y + rowHeight), items)
    }
}

/// The labeled tag field used by both inspectors.
struct TagSection: View {
    @ObservedObject var model: LibraryModel
    let refs: [Reference]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ReferenceTagField(model: model, refs: refs)
        }
    }
}
