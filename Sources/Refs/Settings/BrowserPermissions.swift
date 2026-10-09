import AppKit
import SwiftUI

/// Automation permission state for every installed browser, with a one-click "allow all".
///
/// macOS asks for Automation consent once per target app and only while that app is running, so
/// "allow all" walks the browsers in turn: it starts any that aren't open in the background, shows
/// the system prompt, and quits the ones it started.
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

    var pending: [Row] {
        rows.filter { $0.permission == .notDetermined || $0.permission == .notRunning }
    }

    var allDecided: Bool { loaded && pending.isEmpty }

    func refresh() {
        Task.detached(priority: .userInitiated) {
            let (supported, unsupported) = BrowserSupport.installedBrowsers()
            let rows = supported.map { Row(browser: $0, permission: BrowserSupport.permission(for: $0.bundleID, ask: false)) }
            await MainActor.run {
                self.rows = rows
                self.unsupported = unsupported
                self.loaded = true
            }
        }
    }

    func allowAll() {
        let browsers = pending.map(\.browser)
        guard requesting == nil, !browsers.isEmpty else { return }
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
        let result = await Task.detached(priority: .userInitiated) { () -> BrowserSupport.Permission in
            // The browser may need a moment after launch before it accepts Apple Events.
            for _ in 0..<40 {
                let status = BrowserSupport.permission(for: browser.bundleID, ask: true)
                if status != .notRunning { return status }
                try? await Task.sleep(for: .milliseconds(250))
            }
            return .notRunning
        }.value
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
                StatusPill(text: "Unknown", ok: false)
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
