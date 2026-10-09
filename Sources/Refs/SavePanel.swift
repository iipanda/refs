import AppKit
import RefsCore
import SwiftUI

/// Editable state for one capture waiting to be saved.
final class SaveDraft: ObservableObject {
    let capture: CaptureResult
    let preview: NSImage
    @Published var appName: String
    @Published var title: String
    @Published var url: String
    @Published var note = ""
    @Published var browserAccess: BrowserAccess?
    @Published var askingPermission = false

    init(capture: CaptureResult) {
        self.capture = capture
        preview = NSImage(cgImage: capture.image,
                          size: NSSize(width: CGFloat(capture.image.width) / capture.scale,
                                       height: CGFloat(capture.image.height) / capture.scale))
        appName = capture.app.name
        title = capture.web?.title ?? capture.windowTitle ?? ""
        url = capture.web?.url ?? ""
        browserAccess = capture.browserAccess
    }

    /// Asks for Automation permission (macOS shows its prompt), then reads the tab URL.
    func allowBrowserAccess() {
        guard case .needsPermission(let browser) = browserAccess, let window = capture.sourceWindow else { return }
        askingPermission = true
        let isFrontmost = capture.sourceWindowIsFrontmostOfApp
        Task.detached(priority: .userInitiated) {
            let permission = BrowserSupport.permission(for: browser.bundleID, ask: true)
            let tabs = permission == .granted ? await BrowserSupport.tabs(for: browser) : []
            let tab = BrowserSupport.tab(for: window, among: tabs, isFrontmostOfApp: isFrontmost)
            await MainActor.run {
                self.askingPermission = false
                switch permission {
                case .granted: self.browserAccess = nil
                case .denied: self.browserAccess = .denied(browser)
                default: break
                }
                if let tab {
                    self.url = tab.url
                    if let title = tab.title, !title.isEmpty { self.title = title }
                }
            }
        }
    }

    var app: SourceApp {
        let name = appName.trimmingCharacters(in: .whitespaces)
        if name == capture.app.name { return capture.app }
        return SourceApp(name: name.isEmpty ? capture.app.name : name, bundleID: capture.app.bundleID)
    }

    var web: WebSource? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return WebSource(url: trimmed, title: title.isEmpty ? nil : title)
    }

    var windowTitle: String? {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

/// The floating panel that appears after a capture.
final class SavePanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let draft: SaveDraft
    private let onFinish: (SaveDraft?) -> Void
    private var done = false

    init(capture: CaptureResult, onFinish: @escaping (SaveDraft?) -> Void) {
        draft = SaveDraft(capture: capture)
        self.onFinish = onFinish
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
                             // Non-activating, so saving doesn't bring the Library forward or take
                             // the user out of the app they were in.
                             styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let view = SaveView(draft: draft, onSave: { [weak self] in self?.finish(save: true) },
                            onDiscard: { [weak self] in self?.finish(save: false) })
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
    }

    func show() {
        position(near: draft.capture.frame)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(save: false)
    }

    private func finish(save: Bool) {
        guard !done else { return }
        done = true
        panel.delegate = nil
        panel.orderOut(nil)
        onFinish(save ? draft : nil)
    }

    /// Beside the capture if there's room (right, then left), otherwise centred on its screen.
    private func position(near rect: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let gap: CGFloat = 16
        var origin: NSPoint
        if rect.maxX + gap + size.width <= visible.maxX {
            origin = NSPoint(x: rect.maxX + gap, y: rect.maxY - size.height)
        } else if rect.minX - gap - size.width >= visible.minX {
            origin = NSPoint(x: rect.minX - gap - size.width, y: rect.maxY - size.height)
        } else {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)
        panel.setFrameOrigin(origin)
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct SaveView: View {
    @ObservedObject var draft: SaveDraft
    let onSave: () -> Void
    let onDiscard: () -> Void
    @State private var editingSource = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: draft.preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 210)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))

            sourceRow

            if let access = draft.browserAccess {
                BrowserAccessBanner(access: access, asking: draft.askingPermission, onAllow: draft.allowBrowserAccess)
            }

            TextField("What do you like about it?", text: $draft.note, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .focused($noteFocused)
                .onSubmit(onSave)

            HStack {
                Text("Return to save · Esc to discard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Discard", action: onDiscard)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(width: 400)
        .onAppear {
            DispatchQueue.main.async { noteFocused = true }
        }
    }

    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppIcon(bundleID: draft.capture.app.bundleID, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(draft.title.isEmpty ? draft.appName : draft.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Button(editingSource ? "Done" : "Edit") { editingSource.toggle() }
                    .buttonStyle(.link)
            }
            if editingSource {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    GridRow {
                        Text("App").foregroundStyle(.secondary)
                        TextField("App", text: $draft.appName)
                    }
                    GridRow {
                        Text("Title").foregroundStyle(.secondary)
                        TextField("Page or window title", text: $draft.title)
                    }
                    GridRow {
                        Text("URL").foregroundStyle(.secondary)
                        TextField("https://…", text: $draft.url)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var subtitle: String {
        let url = draft.url.trimmingCharacters(in: .whitespaces)
        if url.isEmpty { return draft.appName }
        let display = url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        return "\(display) · \(draft.appName)"
    }
}

/// The app's icon from its bundle ID, or a generic app icon.
struct AppIcon: View {
    let bundleID: String?
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: Self.icon(for: bundleID))
            .resizable()
            .frame(width: size, height: size)
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundleID: String?) -> NSImage {
        let key = (bundleID ?? "") as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon: NSImage
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSWorkspace.shared.icon(for: .application)
        }
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// Explains why a browser capture has no URL, and how to fix it.
struct BrowserAccessBanner: View {
    let access: BrowserAccess
    let asking: Bool
    let onAllow: () -> Void

    var body: some View {
        switch access {
        case .needsPermission(let browser):
            banner(icon: "link.badge.plus", tint: .accentColor,
                   title: "Record the page URL too?",
                   detail: "Refs needs your permission to read the current tab in \(browser.name). macOS asks once.") {
                Button(asking ? "Waiting…" : "Allow…", action: onAllow)
                    .buttonStyle(.borderedProminent)
                    .disabled(asking)
            }
        case .denied(let browser):
            banner(icon: "exclamationmark.triangle.fill", tint: .orange,
                   title: "URL not recorded",
                   detail: "\(browser.name) isn't allowed to share its current page with Refs. Turn it on under Automation.") {
                Button("Open Settings…") { openPrivacyPane("Privacy_Automation") }
            }
        case .unsupported(let name):
            Label("\(name) doesn't share its current page. Add the URL with Edit if you want it.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func banner<Action: View>(icon: String, tint: Color, title: String, detail: String,
                                      @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            action()
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35)))
    }
}
