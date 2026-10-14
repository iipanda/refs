import AppKit
import RefsCore
import ScreenCaptureKit

/// What a finished capture hands to the save panel.
struct CaptureResult {
    var videoURL: URL? = nil
    var videoDuration: Double? = nil
    var recordingWindowID: CGWindowID? = nil
    var image: CGImage
    var scale: CGFloat
    var app: SourceApp
    var windowTitle: String?
    var web: WebSource?
    /// Why the URL is missing, when the source is a browser.
    var browserAccess: BrowserAccess?
    /// Where the capture was, in Cocoa global coordinates, for placing the save panel.
    var frame: NSRect
    /// The source window, so the URL can be read after permission is granted.
    var sourceWindow: WindowInfo?
    var sourceWindowIsFrontmostOfApp: Bool

    /// Optional browser metadata must not prevent a completed image from reaching the save panel.
    /// This is shared by capture completion and synthetic tests; the task uses bounded lookups.
    func resolvingBrowserMetadata(
        tabs tabTask: Task<[BrowserTab], Never>?,
        accessLookup: (SourceApp) async -> BrowserAccess? = BrowserAccess.check
    ) async -> CaptureResult {
        let tabs = await tabTask?.value ?? []
        var result = self
        if let sourceWindow,
           let tab = BrowserSupport.tab(for: sourceWindow, among: tabs, isFrontmostOfApp: sourceWindowIsFrontmostOfApp) {
            result.web = WebSource(url: tab.url, title: tab.title)
        }
        result.browserAccess = result.web == nil ? await accessLookup(app) : nil
        return result
    }
}

/// Why a browser capture has no URL.
enum BrowserAccess: Equatable {
    /// Refs hasn't asked this browser yet.
    case needsPermission(BrowserSupport.Browser)
    /// The user said no; it can only be changed in System Settings.
    case denied(BrowserSupport.Browser)
    /// The browser doesn't expose its tabs (Firefox, Zen).
    case unsupported(String)

    static func check(app: SourceApp) async -> BrowserAccess? {
        if let browser = BrowserSupport.browser(bundleID: app.bundleID) {
            switch await BrowserSupport.permission(for: browser.bundleID, ask: false) {
            case .notDetermined: return .needsPermission(browser)
            case .denied: return .denied(browser)
            default: return nil
            }
        }
        if let bundleID = app.bundleID, !BrowserSupport.isExcluded(bundleID),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let sample = URL(string: "https://example.com"),
           NSWorkspace.shared.urlsForApplications(toOpen: sample).contains(appURL) {
            return .unsupported(app.name)
        }
        return nil
    }
}

/// One capture from hotkey to result: shows the selection overlay on every screen, tracks the
/// area or window being picked, and captures it.
final class CaptureSession {
    enum Mode { case area, window }

    private(set) var mode: Mode
    let recording: Bool
    private var recordingWindowID: CGWindowID?
    private let windows: [WindowInfo]
    private var overlays: [OverlayWindow] = []
    private let completion: (Result<CaptureResult, Error>?) -> Void

    private var dragStart: NSPoint?
    /// Current area selection in Cocoa global coordinates.
    private(set) var selection: NSRect?
    /// Window under the pointer (window mode, or area mode before dragging).
    private(set) var hovered: WindowInfo?

    private let contentTask: Task<SCShareableContent?, Never>
    private var tabTasks: [pid_t: Task<[BrowserTab], Never>] = [:]
    private var tabs: [pid_t: [BrowserTab]] = [:]
    private var finished = false

    init(mode: Mode, recording: Bool = false, completion: @escaping (Result<CaptureResult, Error>?) -> Void) {
        self.recording = recording
        self.mode = mode
        self.completion = completion
        windows = WindowList.snapshot()
        // Start the slower lookups now so they're ready by the time the user releases the mouse.
        contentTask = Task { try? await ScreenCapturer.shareableContent() }
        prefetchBrowserTabs()
    }

    func start() {
        for screen in NSScreen.screens {
            let overlay = OverlayWindow(screen: screen, session: self)
            overlays.append(overlay)
            overlay.orderFrontRegardless()
        }
        // The overlay takes keyboard focus without activating Refs. Activating would bring the Library
        // and other Refs windows in front of the app being captured.
        let mouse = NSEvent.mouseLocation
        let keyOverlay = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        keyOverlay?.makeKey()
        keyOverlay?.makeFirstResponder(keyOverlay?.contentView)
        updateHover(at: mouse)
        refreshCursor()
    }

    // MARK: - Input from the overlay

    func mouseDown(at point: NSPoint) {
        dragStart = point
        selection = nil
    }

    func mouseDragged(to point: NSPoint) {
        guard mode == .area, let start = dragStart else { return }
        selection = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y))
        redraw()
    }

    func mouseUp(at point: NSPoint) {
        defer { dragStart = nil }
        if mode == .area, let selection, selection.width >= 4, selection.height >= 4 {
            finish(area: selection)
            return
        }
        // A click without a drag captures the window under the pointer, in either mode.
        updateHover(at: point)
        if let hovered {
            finish(window: hovered)
        } else {
            cancel()
        }
    }

    func mouseMoved(to point: NSPoint) {
        updateHover(at: point)
    }

    func toggleMode() {
        mode = mode == .area ? .window : .area
        selection = nil
        dragStart = nil
        updateHover(at: NSEvent.mouseLocation)
        refreshCursor()
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        contentTask.cancel()
        tabTasks.values.forEach { $0.cancel() }
        tearDown()
        completion(nil)
    }

    // MARK: - HUD

    /// The label shown in the overlay's top bar: what will be recorded as the source.
    var sourceDescription: String {
        let window: WindowInfo?
        if let selection {
            window = WindowList.sourceWindow(for: ScreenGeometry.cgRect(fromCocoa: selection), in: windows)
        } else {
            window = hovered
        }
        guard let window else {
            return mode == .area ? "Drag to select an area" : "Move over a window"
        }
        var parts = [window.appName]
        if let tab = tab(for: window) {
            parts.append(WebSource(url: tab.url, title: nil).host ?? tab.url)
            if let title = tab.title, !title.isEmpty { parts.append(title) }
        } else if let title = window.title {
            parts.append(title)
        }
        return parts.joined(separator: "  ·  ")
    }

    var selectionPixelSize: NSSize? {
        guard let selection else { return nil }
        let scale = NSScreen.screens.first { $0.frame.contains(NSPoint(x: selection.midX, y: selection.midY)) }?
            .backingScaleFactor ?? 2
        return NSSize(width: (selection.width * scale).rounded(), height: (selection.height * scale).rounded())
    }

    var hoveredCocoaFrame: NSRect? {
        hovered.map { ScreenGeometry.cocoaRect(fromCG: $0.bounds) }
    }

    // MARK: - Private

    private func updateHover(at point: NSPoint) {
        guard dragStart == nil || mode == .window else { return }
        let window = WindowList.window(at: ScreenGeometry.cgPoint(fromCocoa: point), in: windows)
        if window != hovered {
            hovered = window
            redraw()
        }
    }

    private func redraw() {
        overlays.forEach { $0.contentView?.needsDisplay = true }
    }

    private func refreshCursor() {
        (mode == .area ? NSCursor.crosshair : NSCursor.pointingHand).set()
    }

    private func tab(for window: WindowInfo) -> BrowserTab? {
        guard let tabs = tabs[window.pid] else { return nil }
        return BrowserSupport.tab(for: window, among: tabs,
                                  isFrontmostOfApp: WindowList.isFrontmostOfApp(window, in: windows))
    }

    private func prefetchBrowserTabs() {
        var seen = Set<pid_t>()
        for window in windows where seen.insert(window.pid).inserted {
            guard let browser = BrowserSupport.browser(bundleID: window.bundleID) else { continue }
            let pid = window.pid
            let task = Task { () -> [BrowserTab] in
                guard await BrowserSupport.permission(for: browser.bundleID, ask: false) == .granted else { return [] }
                return await BrowserSupport.tabs(for: browser)
            }
            tabTasks[pid] = task
            Task { @MainActor [weak self] in
                let result = await task.value
                self?.tabs[pid] = result
                self?.redraw()
            }
        }
    }

    private func finish(area: NSRect) {
        let cgRect = ScreenGeometry.cgRect(fromCocoa: area)
        let source = WindowList.sourceWindow(for: cgRect, in: windows)
        complete(frame: area, source: source) { content in
            try await ScreenCapturer.captureArea(cgRect, content: content)
        }
    }

    private func finish(window: WindowInfo) {
        recordingWindowID = window.id
        complete(frame: ScreenGeometry.cocoaRect(fromCG: window.bounds), source: window) { content in
            try await ScreenCapturer.captureWindow(id: window.id, content: content)
        }
    }

    private func complete(
        frame: NSRect,
        source: WindowInfo?,
        capture: @escaping (SCShareableContent) async throws -> (CGImage, CGFloat)
    ) {
        guard !finished else { return }
        finished = true
        tearDown()
        let isFrontmost = source.map { WindowList.isFrontmostOfApp($0, in: windows) } ?? false
        let tabTask = source.flatMap { tabTasks[$0.pid] }

        Task { @MainActor in
            do {
                // Let the overlay leave the screen. It's excluded from capture anyway, but this avoids
                // catching its fade-out on slower machines.
                try? await Task.sleep(for: .milliseconds(30))
                var content = await contentTask.value
                if content == nil { content = try await ScreenCapturer.shareableContent() }
                guard let content else { throw CaptureError.noDisplay }
                let (image, scale) = try await capture(content)
                let app = SourceApp(name: source?.appName ?? "Unknown", bundleID: source?.bundleID)
                let captured = CaptureResult(
                    recordingWindowID: recordingWindowID, image: image, scale: scale, app: app, windowTitle: source?.title, web: nil,
                    browserAccess: nil, frame: frame,
                    sourceWindow: source, sourceWindowIsFrontmostOfApp: isFrontmost
                )
                completion(.success(await captured.resolvingBrowserMetadata(tabs: tabTask)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func tearDown() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        NSCursor.arrow.set()
    }
}
