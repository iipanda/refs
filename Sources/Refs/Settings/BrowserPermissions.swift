import AppKit
import SwiftUI

/// Automation permission state for every installed browser, with a one-click "allow all".
///
/// macOS asks for Automation consent once per target app and only while that app is running, so
/// "allow all" walks the browsers in turn: it starts any that aren't open in the background, shows
/// the system prompt, and quits the ones it started.
@MainActor
final class BrowserPermissionsModel: ObservableObject {
    struct Row: Identifiable {
        var browser: BrowserSupport.Browser
        var permission: BrowserSupport.Permission
        var id: String { browser.bundleID }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var unsupported: [BrowserSupport.UnsupportedBrowser] = []
    /// The browser whose prompt is currently showing, during a request.
    @Published private(set) var requesting: String?
    @Published private(set) var loaded = false
    private var observers: [NSObjectProtocol] = []
    private let loadBrowsers: () -> (supported: [BrowserSupport.Browser], unsupported: [BrowserSupport.UnsupportedBrowser])
    private let lookupPermission: (String) async -> BrowserSupport.Permission
    private var refreshTask: Task<Void, Never>?
    private var needsRefresh = false

    init(
        observeChanges: Bool = true,
        loadBrowsers: @escaping () -> (supported: [BrowserSupport.Browser], unsupported: [BrowserSupport.UnsupportedBrowser]) = BrowserSupport.installedBrowsers,
        lookupPermission: @escaping (String) async -> BrowserSupport.Permission = { await BrowserSupport.knownPermission(for: $0) }
    ) {
        self.loadBrowsers = loadBrowsers
        self.lookupPermission = lookupPermission
        guard observeChanges else { return }
        // Keep the list current without reopening it: a browser opening or quitting changes what
        // macOS can report, and answers can arrive from the save panel or System Settings.
        let workspace = NSWorkspace.shared.notificationCenter
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            // All observers below explicitly deliver on the main operation queue.
            MainActor.assumeIsolated { self?.refreshIfIdle() }
        }
        observers = [
            workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: refresh),
            workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: refresh),
            NotificationCenter.default.addObserver(forName: BrowserSupport.permissionsChanged, object: nil, queue: .main, using: refresh),
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: refresh),
        ]
    }

    deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
    }

    /// Skips refreshes while a request is running, so its own launches don't reset the list mid-way.
    private func refreshIfIdle() {
        guard requesting == nil else { return }
        refresh()
    }

    var pending: [Row] {
        rows.filter { $0.permission == .notDetermined || $0.permission == .notRunning }
    }

    var allDecided: Bool {
        loaded && rows.allSatisfy { $0.permission == .granted || $0.permission == .denied }
    }

    func refresh() {
        guard requesting == nil, refreshTask == nil else {
            needsRefresh = true
            return
        }
        needsRefresh = false
        let loadBrowsers = self.loadBrowsers
        refreshTask = Task { @MainActor in
            let (supported, unsupported) = await Task.detached(priority: .userInitiated) { loadBrowsers() }.value
            var rows: [Row] = []
            for browser in supported {
                guard !Task.isCancelled else { break }
                rows.append(Row(browser: browser, permission: await self.lookupPermission(browser.bundleID)))
            }
            if !Task.isCancelled, self.requesting == nil {
                self.rows = rows
                self.unsupported = unsupported
                self.loaded = true
            }
            self.refreshTask = nil
            if self.needsRefresh, self.requesting == nil { self.refresh() }
        }
    }

    func allowAll() {
        let browsers = pending.map(\.browser)
        guard requesting == nil, !browsers.isEmpty else { return }
        requesting = browsers[0].bundleID
        refreshTask?.cancel()
        Task { @MainActor in
            for browser in browsers {
                await request(browser)
            }
            requesting = nil
            refresh()
        }
    }

    func allow(_ browser: BrowserSupport.Browser) {
        guard requesting == nil else { return }
        requesting = browser.bundleID
        refreshTask?.cancel()
        Task { @MainActor in
            await request(browser)
            requesting = nil
            refresh()
        }
    }

    @MainActor
    private func request(_ browser: BrowserSupport.Browser) async {
        requesting = browser.bundleID
        var launched: NSRunningApplication?
        if NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty {
            launched = await launchInBackground(browser)
            guard launched != nil else { return }
        }
        // The browser may need a moment after launch before it accepts Apple Events.
        var result: BrowserSupport.Permission = .notRunning
        for _ in 0..<40 {
            result = await BrowserSupport.permission(for: browser.bundleID, ask: true)
            if result != .notRunning { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let index = rows.firstIndex(where: { $0.id == browser.bundleID }) {
            rows[index].permission = result
        }
        launched?.terminate()
    }

    @MainActor
    private func launchInBackground(_ browser: BrowserSupport.Browser) async -> NSRunningApplication? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        return try? await NSWorkspace.shared.openApplication(at: browser.appURL, configuration: configuration)
    }
}

/// The list of browsers with their status, shared by onboarding and Settings.
struct BrowserPermissionsList: View {
    @ObservedObject var model: BrowserPermissionsModel

    var body: some View {
        if !model.loaded {
            ProgressView().controlSize(.small)
        } else if model.rows.isEmpty {
            Text("No browsers that share their current page were found.")
                .foregroundStyle(.secondary)
        }
        ForEach(model.rows) { row in
            LabeledContent {
                status(row)
            } label: {
                Label { Text(row.browser.name) } icon: { AppIcon(bundleID: row.browser.bundleID) }
            }
        }
        ForEach(model.unsupported) { browser in
            LabeledContent {
                Text("Window title only")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } label: {
                Label { Text(browser.name) } icon: { AppIcon(bundleID: browser.bundleID) }
            }
            .help("\(browser.name) doesn't let other apps read its current tab, so Refs records the window title instead.")
        }
    }

    @ViewBuilder
    private func status(_ row: BrowserPermissionsModel.Row) -> some View {
        if model.requesting == row.id {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for you…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            switch row.permission {
            case .granted:
                StatusPill(text: "Allowed", ok: true)
            case .denied:
                Button("Turn On in Settings…") { openPrivacyPane("Privacy_Automation") }
            case .notDetermined, .notRunning:
                Button("Allow…") { model.allow(row.browser) }
                    .disabled(model.requesting != nil)
            case .unknown:
                HStack(spacing: 6) {
                    StatusPill(text: "Unavailable", ok: false)
                    Button("Retry") { model.refresh() }
                }
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    let ok: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(ok ? Color.green : Color.orange)
            .background((ok ? Color.green : Color.orange).opacity(0.15), in: Capsule())
    }
}
