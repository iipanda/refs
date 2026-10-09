import AppKit
import Combine
import RefsCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let preferences = Preferences.shared
    private let hotKeyStatus = HotKeyStatus()
    private lazy var library = LibraryModel(root: preferences.libraryURL)

    private var statusItem: NSStatusItem?
    private var libraryWindow: NSWindow?
    /// Whether the Library window is open (it may be minimised), which decides the Dock icon.
    private var libraryOpen = false
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let browserPermissions = BrowserPermissionsModel()
    private var session: CaptureSession?
    private var savePanel: SavePanelController?
    /// The app that was frontmost before a capture, so focus can go back to it afterwards.
    private var previousApp: NSRunningApplication?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockPolicy()
        applyStatusItem()
        registerHotKeys()
        browserPermissions.refresh()

        preferences.$showMenuBarIcon.dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyStatusItem() }.store(in: &cancellables)
        preferences.$dockIconMode.dropFirst().receive(on: RunLoop.main)
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

        if !preferences.onboardingCompleted {
            showOnboarding()
        } else if !preferences.showMenuBarIcon && preferences.dockIconMode != .always {
            // Opening the app with both icons hidden would otherwise show nothing at all.
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
        if !CGPreflightScreenCaptureAccess() || !browserPermissions.allDecided {
            menu.addItem(item("Set Up Permissions…", #selector(openOnboardingAction), nil))
        }
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

    /// Selects text while editing, otherwise every visible card in the Library.
    @objc private func selectAllAction() {
        let window = NSApp.keyWindow
        if window === libraryWindow, !(window?.firstResponder is NSText) {
            library.selectAllVisible()
        } else {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }
    @objc private func openOnboardingAction() { showOnboarding() }

    @objc private func openRecent(_ sender: NSMenuItem) {
        library.selectedID = sender.representedObject as? String
        showLibrary()
    }

    // MARK: - Main menu

    /// Shown while Refs is the active app, e.g. with the Library open. The Edit menu also makes
    /// copy, paste and undo work in text fields.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Refs")
        appMenu.addItem(withTitle: "About Refs", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettingsAction), nil, key: ","))
        appMenu.addItem(item("Set Up Permissions…", #selector(openOnboardingAction), nil))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Refs", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Refs", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Capture Area", #selector(captureAreaAction), preferences.captureArea))
        fileMenu.addItem(item("Capture Window", #selector(captureWindowAction), preferences.captureWindow))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(item("Select All", #selector(selectAllAction), nil, key: "a"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Library", #selector(openLibraryAction), preferences.openLibrary))
        NSApp.windowsMenu = windowMenu

        for menu in [appMenu, fileMenu, editMenu, windowMenu] {
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        return main
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
        // The File menu shows the capture shortcuts.
        NSApp.mainMenu = makeMainMenu()
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .captureArea: startCapture(.area)
        case .captureWindow: startCapture(.window)
        case .openLibrary: showLibrary()
        }
    }

    private func applyDockPolicy() {
        let showIcon = switch preferences.dockIconMode {
        case .always: true
        case .whileLibraryOpen: libraryOpen
        case .never: false
        }
        let policy: NSApplication.ActivationPolicy = showIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === libraryWindow else { return }
        libraryOpen = false
        applyDockPolicy()
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
            showOnboarding()
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

    /// Capturing never activates Refs, so the app being captured normally stays in front. If something
    /// did activate us meanwhile (an error alert, a permission prompt), hand focus back to that app.
    private func restoreFocus() {
        defer { previousApp = nil }
        guard NSApp.isActive, let previousApp else { return }
        previousApp.activate()
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
            window.contentViewController = NSHostingController(rootView: LibraryView(
                model: library, preferences: preferences, openSettings: { [weak self] in self?.showSettings() }))
            window.delegate = self
            if !window.setFrameUsingName("RefsLibrary") {
                window.setContentSize(NSSize(width: 1120, height: 700))
                window.center()
            }
            libraryWindow = window
        }
        libraryOpen = true
        applyDockPolicy()
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: OnboardingView(
                browsers: browserPermissions, preferences: preferences,
                onDone: { [weak self] in
                    self?.preferences.onboardingCompleted = true
                    self?.onboardingWindow?.close()
                }))
            window.center()
            onboardingWindow = window
        }
        browserPermissions.refresh()
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
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
        let selectFirst = ProcessInfo.processInfo.environment["REFS_SNAPSHOT_SELECT"] != "0"
        library.selectedID = selectFirst ? library.refs.first?.id : nil
        showLibrary()
        showSettings()
        showOnboarding()
        if let ref = library.refs.first,
           let image = ImageCoding.thumbnail(at: library.imageURL(for: ref), maxPixelSize: 4096) {
            let capture = CaptureResult(
                image: image, scale: 2, app: ref.app, windowTitle: ref.windowTitle, web: ref.web,
                browserAccess: BrowserSupport.browser(bundleID: "com.google.Chrome").map { .needsPermission($0) },
                frame: NSRect(x: 100, y: 200, width: 600, height: 300), sourceWindow: nil,
                sourceWindowIsFrontmostOfApp: false)
            let panel = SavePanelController(capture: capture) { _ in }
            savePanel = panel
            panel.show()
        }
        // The split view's materials don't render offscreen, so the grid is also drawn on its own.
        let gridWindows = [520, 760, 1000].map { width -> (NSWindow, Int) in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 760),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: ReferenceGrid(model: library, refs: library.refs)
                .frame(width: CGFloat(width), height: 760)
                .background(Color(nsColor: .windowBackgroundColor)))
            window.orderFront(nil)
            return (window, width)
        }
        let bulk = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                            styleMask: [.titled], backing: .buffered, defer: false)
        bulk.contentView = NSHostingView(rootView: BulkInspectorView(model: library, refs: Array(library.refs.prefix(3)))
            .frame(width: 320, height: 520)
            .background(Color(nsColor: .windowBackgroundColor)))
        bulk.orderFront(nil)
        // A window whose width changes after layout, like when the details panel opens or closes.
        let resized = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                               styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        resized.contentView = NSHostingView(rootView: ReferenceGrid(model: library, refs: library.refs)
            .background(Color(nsColor: .windowBackgroundColor)))
        resized.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                resized.animator().setFrame(NSRect(x: 0, y: 0, width: 700, height: 760), display: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            for (window, width) in gridWindows { write(window, "grid-\(width).png") }
            write(resized, "grid-resized-700.png")
            write(bulk, "bulk-inspector.png")
            write(libraryWindow, "library.png")
            write(settingsWindow, "settings.png")
            write(onboardingWindow, "onboarding.png")
            write(NSApp.windows.first { $0 is NSPanel && $0.isVisible }, "save-panel.png")
            NSApp.terminate(nil)
        }
    }
    #endif
}
