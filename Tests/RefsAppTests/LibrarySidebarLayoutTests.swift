import AppKit
import RefsCore
import SwiftUI
import Testing
@testable import Refs

@Suite(.serialized) struct LibrarySidebarLayoutTests {
    @Test @MainActor func settingsFooterRemainsClickableAcrossItsWidthWhileTagsScroll() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("refs-sidebar-layout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        for index in 1...40 {
            _ = try store.createTag(name: String(format: "Pattern %02d", index))
        }
        let model = LibraryModel(root: root)
        var settingsOpened = 0
        let hosting = NSHostingController(rootView: LibraryView(
            model: model, preferences: .shared, openSettings: { settingsOpened += 1 }))
        hosting.sizingOptions = .minSize
        // Match the real Library window, including its full-size content area.
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 700, height: 520))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        await settle(window)

        let sidebar = try #require(descendants(of: hosting.view).compactMap { $0 as? NSScrollView }
            .first { $0.bounds.width < 300 && $0.bounds.height > 200 },
            "The native sidebar scroll view must be present in the rendered Library")
        let sidebarFrame = sidebar.convert(sidebar.bounds, to: hosting.view)
        let footerY = hosting.view.isFlipped ? hosting.view.bounds.maxY - 20 : hosting.view.bounds.minY + 20
        // Click the label side, middle, and trailing whitespace of the actual footer row.
        // These window coordinates remain unchanged when the underlying tags scroll.
        let footerPoints = [sidebarFrame.minX + 32, sidebarFrame.midX, sidebarFrame.maxX - 24].map { x in
            hosting.view.convert(NSPoint(x: x, y: footerY), to: nil)
        }

        let document = try #require(sidebar.documentView)
        #expect(document.bounds.height > sidebar.contentView.bounds.height,
                "The fixture must overflow so tags actually scroll")
        for atBottom in [false, true] {
            let maximumY = max(0, document.bounds.height - sidebar.contentView.bounds.height)
            let y = (atBottom == document.isFlipped) ? maximumY : 0
            sidebar.contentView.scroll(to: NSPoint(x: 0, y: y))
            sidebar.reflectScrolledClipView(sidebar.contentView)
            await settle(window)

            for point in footerPoints {
                let previousOpenCount = settingsOpened
                try click(point, in: window)
                await settle(window)
                #expect(settingsOpened == previousOpenCount + 1,
                        "The stationary Settings footer must open Settings across its full row at either scroll extreme; click: \(point)")
            }
            try snapshot(window, name: atBottom ? "sidebar-bottom.png" : "sidebar-top.png")
        }
    }
}

@MainActor private func descendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants(of: $0) }
}

@MainActor private func click(_ point: NSPoint, in window: NSWindow) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        NSApp.sendEvent(event)
    }
}

@MainActor private func settle(_ window: NSWindow) async {
    for _ in 0..<10 {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor private func snapshot(_ window: NSWindow, name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["REFS_SIDEBAR_SNAPSHOTS"],
          let view = window.contentView?.superview,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name))
}
