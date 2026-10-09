import AppKit
import Combine
import RefsCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences.shared
    private let hotKeyStatus = HotKeyStatus()
    private lazy var library = LibraryModel(root: preferences.libraryURL)

    private var statusItem: NSStatusItem?
    private var libraryWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var session: CaptureSession?
    private var savePanel: SavePanelController?
    /// The app that was frontmost before a capture, so focus can go back to it afterwards.
    private var previousApp: NSRunningApplication?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockPolicy()
        applyStatusItem()
        registerHotKeys()

        preferences.$showMenuBarIcon.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyStatusItem() }.store(in: &cancellables)
        preferences.$showDockIcon.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyDockPolicy() }.store(in: &cancellables)
        preferences.$libraryPath.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                library.changeRoot(preferences.libraryURL)
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .refsShortcutsChanged).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.registerHotKeys() }.store(in: &cancellables)

        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["REFS_SNAPSHOT_DIR"] {
            snapshotWindows(to: URL(fileURLWithPath: dir))
            return
        }
        #endif

        // Opening the app with both icons hidden would otherwise show nothing at all.
        if !preferences.showMenuBarIcon && !preferences.showDockIcon {
            showSettings()
        }
    }

    /// Opening Refs again from Finder or Spotlight while it's running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if preferences.showMenuBarIcon {
            showLibrary()
        } else {
            showSettings()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu bar

    private func applyStatusItem() {
        if preferences.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Refs")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Capture Area", #selector(captureAreaAction), preferences.captureArea))
        menu.addItem(item("Capture Window", #selector(captureWindowAction), preferences.captureWindow))

        let recent = library.refs.prefix(3)
        if !recent.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for ref in recent {
                let title = ref.note.isEmpty ? ref.sourceLabel : "\(ref.sourceLabel) – \(ref.note)"
                let entry = NSMenuItem(title: String(title.prefix(48)) + (title.count > 48 ? "…" : ""),
                                       action: #selector(openRecent(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = ref.id
                if let thumb = Thumbnails.loadSync(library.imageURL(for: ref), maxPixelSize: 96) {
                    entry.image = fitted(thumb, in: NSSize(width: 40, height: 26))
                }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Library…", #selector(openLibraryAction), preferences.openLibrary))
        menu.addItem(item("Settings…", #selector(openSettingsAction), nil, key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Refs", #selector(NSApplication.terminate(_:)), nil, key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, _ shortcut: Shortcut?, key: String = "",
                      target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let shortcut, shortcut.key.count == 1 {
            item.keyEquivalent = shortcut.key.lowercased()
            item.keyEquivalentModifierMask = shortcut.eventModifiers
        }
        return item
    }

    private func fitted(_ image: NSImage, in box: NSSize) -> NSImage {
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSImage(size: box, flipped: false) { _ in
            let rect = NSRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
                              width: size.width, height: size.height)
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
            image.draw(in: rect)
            return true
        }
    }

    @objc private func captureAreaAction() { startCapture(.area) }
    @objc private func captureWindowAction() { startCapture(.window) }
    @objc private func openLibraryAction() { showLibrary() }
    @objc private func openSettingsAction() { showSettings() }

    @objc private func openRecent(_ sender: NSMenuItem) {
        library.selectedID = sender.representedObject as? String
        showLibrary()
    }

    // MARK: - Hotkeys and Dock

    private func registerHotKeys() {
        var unavailable: Set<HotKeyAction> = []
        for action in HotKeyAction.allCases {
            let ok = HotKeyCenter.shared.register(id: action.rawValue, shortcut: preferences.shortcut(for: action)) { [weak self] in
                self?.perform(action)
            }
            if !ok { unavailable.insert(action) }
        }
        hotKeyStatus.unavailable = unavailable
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .captureArea: startCapture(.area)
        case .captureWindow: startCapture(.window)
        case .openLibrary: showLibrary()
        }
    }

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(preferences.showDockIcon ? .regular : .accessory)
        if preferences.showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Capture

    private func startCapture(_ mode: CaptureSession.Mode) {
        if let session {
            // A second press while selecting switches mode, like pressing Space.
            if session.mode != mode { session.toggleMode() }
            return
        }
        guard savePanel == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            requestScreenRecording()
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        if previousApp?.bundleIdentifier == Bundle.main.bundleIdentifier { previousApp = nil }
        let session = CaptureSession(mode: mode) { [weak self] result in
            self?.session = nil
            self?.handle(result)
        }
        self.session = session
        session.start()
    }

    private func handle(_ result: Result<CaptureResult, Error>?) {
        switch result {
        case nil:
            restoreFocus()
        case .failure(let error):
            restoreFocus()
            showError("Couldn't capture", error.localizedDescription)
        case .success(let capture):
            let panel = SavePanelController(capture: capture) { [weak self] draft in
                guard let self else { return }
                savePanel = nil
                if let draft {
                    do {
                        _ = try library.add(draft)
                    } catch {
                        showError("Couldn't save the reference", error.localizedDescription)
                    }
                }
                restoreFocus()
            }
            savePanel = panel
            panel.show()
        }
    }

    /// Hands focus back to the app the user was in, unless one of our windows is in use.
    private func restoreFocus() {
        defer { previousApp = nil }
        let ourWindowsVisible = [libraryWindow, settingsWindow].contains { $0?.isVisible == true }
        guard !ourWindowsVisible else { return }
        previousApp?.activate()
    }

    private func requestScreenRecording() {
        // Shows the system prompt the first time; afterwards it only opens System Settings.
        CGRequestScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Refs needs Screen Recording permission"
        alert.informativeText = "Turn on Refs in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Refs."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }

    private func showError(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Windows

    func showLibrary() {
        library.reload()
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Refs"
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("RefsLibrary")
            window.contentViewController = NSHostingController(rootView: LibraryView(model: library, preferences: preferences))
            if !window.setFrameUsingName("RefsLibrary") {
                window.setContentSize(NSSize(width: 1120, height: 700))
                window.center()
            }
            libraryWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Refs Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(preferences: preferences, hotKeyStatus: hotKeyStatus))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// Renders the main windows to PNGs for visual checks without Screen Recording permission.
    private func snapshotWindows(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ window: NSWindow?, _ name: String) {
            guard let view = window?.contentView?.superview ?? window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        library.selectedID = library.refs.first?.id
        showLibrary()
        showSettings()
        if let ref = library.refs.first,
           let image = ImageCoding.thumbnail(at: library.imageURL(for: ref), maxPixelSize: 4096) {
            let capture = CaptureResult(
                image: image, scale: 2, app: ref.app, windowTitle: ref.windowTitle, web: ref.web,
                browserNeedingPermission: BrowserSupport.known[2],
                frame: NSRect(x: 100, y: 200, width: 600, height: 300), sourceWindow: nil,
                sourceWindowIsFrontmostOfApp: false)
            let panel = SavePanelController(capture: capture) { _ in }
            savePanel = panel
            panel.show()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            write(libraryWindow, "library.png")
            write(settingsWindow, "settings.png")
            write(NSApp.windows.first { $0 is NSPanel && $0.isVisible }, "save-panel.png")
            NSApp.terminate(nil)
        }
    }
    #endif
}
