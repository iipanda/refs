import Foundation

/// Finder-style multi-selection over an ordered list of IDs.
///
/// A plain click selects one item (or clears it if it was the only one selected), ⌘-click toggles
/// one item, and ⇧-click selects the range from the last clicked item (the anchor).
public struct Selection: Equatable, Sendable {
    public enum Modifier: Sendable {
        case none, toggle, extend
    }

    public private(set) var ids: Set<String> = []
    /// The item ranges extend from.
    public private(set) var anchor: String?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public var count: Int { ids.count }

    /// The selected ID when exactly one item is selected.
    public var single: String? {
        ids.count == 1 ? ids.first : nil
    }

    public func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    /// Applies a click on `id`. `order` is the visible order, used for ranges.
    public mutating func click(_ id: String, modifier: Modifier, order: [String]) {
        switch modifier {
        case .none:
            if ids == [id] {
                clear()
            } else {
                ids = [id]
                anchor = id
            }
        case .toggle:
            if ids.contains(id) {
                ids.remove(id)
            } else {
                ids.insert(id)
            }
            anchor = id
        case .extend:
            guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
                ids = [id]
                self.anchor = id
                return
            }
            ids = Set(order[min(from, to)...max(from, to)])
        }
    }

    public mutating func select(_ id: String) {
        ids = [id]
        anchor = id
    }

    /// Replaces the selection, e.g. with the cards under a drag rectangle. The anchor becomes the
    /// first selected item in visible order, so a following ⇧-click ranges from there.
    public mutating func set(_ newIDs: Set<String>, order: [String]) {
        ids = newIDs
        anchor = order.first(where: newIDs.contains)
    }

    public mutating func selectAll(_ order: [String]) {
        ids = Set(order)
        anchor = order.first
    }

    public mutating func clear() {
        ids = []
        anchor = nil
    }

    /// Drops selected items that are no longer visible, e.g. after filtering or deleting.
    public mutating func retain(_ visible: some Sequence<String>) {
        let visible = Set(visible)
        ids.formIntersection(visible)
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
    }

    /// The selected IDs in visible order.
    public func ordered(by order: [String]) -> [String] {
        order.filter(ids.contains)
    }
}
