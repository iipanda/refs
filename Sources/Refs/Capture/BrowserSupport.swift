import AppKit
import Carbon.HIToolbox

/// The active tab of one browser window, as reported over Apple Events.
struct BrowserTab: Equatable {
    var windowName: String?
    var url: String
    var title: String?
}

/// Reads the current page from scriptable browsers. Firefox-based browsers don't expose tabs to
/// AppleScript, so they fall back to the window title.
enum BrowserSupport {
    enum Dialect { case safari, chromium }

    struct Browser: Identifiable {
        var bundleID: String
        var name: String
        var dialect: Dialect
        var id: String { bundleID }
    }

    static let known: [Browser] = [
        Browser(bundleID: "com.apple.Safari", name: "Safari", dialect: .safari),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview", dialect: .safari),
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome", dialect: .chromium),
        Browser(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta", dialect: .chromium),
        Browser(bundleID: "com.google.Chrome.canary", name: "Google Chrome Canary", dialect: .chromium),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc", dialect: .chromium),
        Browser(bundleID: "company.thebrowser.dia", name: "Dia", dialect: .chromium),
        Browser(bundleID: "com.brave.Browser", name: "Brave", dialect: .chromium),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", dialect: .chromium),
        Browser(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", dialect: .chromium),
        Browser(bundleID: "com.operasoftware.Opera", name: "Opera", dialect: .chromium),
    ]

    static func browser(bundleID: String?) -> Browser? {
        guard let bundleID else { return nil }
        return known.first { $0.bundleID == bundleID }
    }

    static var installed: [Browser] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    // MARK: - Automation permission

    enum Permission: Equatable {
        case granted, denied, notDetermined, notRunning, unknown(OSStatus)
    }

    /// Checks (and optionally asks for) permission to send Apple Events to a browser.
    /// Asking blocks until the user answers, so call it off the main thread.
    static func permission(for bundleID: String, ask: Bool) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        switch Int(status) {
        case Int(noErr): return .granted
        case errAEEventNotPermitted: return .denied
        case errAEEventWouldRequireUserConsent: return .notDetermined
        case procNotFound: return .notRunning
        default: return .unknown(status)
        }
    }

    // MARK: - Reading tabs

    private static let queue = DispatchQueue(label: "refs.applescript")

    /// The active tab of every window of a running browser, front to back.
    /// Never call this without permission: it would show a consent prompt.
    static func tabs(for browser: Browser) async -> [BrowserTab] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: runTabsScript(browser))
            }
        }
    }

    private static func runTabsScript(_ browser: Browser) -> [BrowserTab] {
        let tabProperties = browser.dialect == .safari
            ? "URL of current tab of w, name of current tab of w"
            : "URL of active tab of w, title of active tab of w"
        let source = """
            with timeout of 1 second
                tell application id "\(browser.bundleID)"
                    set out to {}
                    repeat with w in windows
                        try
                            set end of out to {name of w, \(tabProperties)}
                        end try
                    end repeat
                    return out
                end tell
            end timeout
            """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let result = script.executeAndReturnError(&error) as NSAppleEventDescriptor?,
              error == nil
        else { return [] }

        var tabs: [BrowserTab] = []
        let count = result.numberOfItems
        guard count > 0 else { return [] }
        for index in 1...count {
            guard let row = result.atIndex(index), row.numberOfItems >= 3,
                  let url = row.atIndex(2)?.stringValue, !url.isEmpty
            else { continue }
            tabs.append(BrowserTab(windowName: row.atIndex(1)?.stringValue, url: url, title: row.atIndex(3)?.stringValue))
        }
        return tabs
    }

    /// Picks the tab shown in `window`: match by window title, otherwise assume the app's front window.
    static func tab(for window: WindowInfo, among tabs: [BrowserTab], isFrontmostOfApp: Bool) -> BrowserTab? {
        if let title = window.title, let match = tabs.first(where: { $0.windowName == title }) {
            return match
        }
        return isFrontmostOfApp ? tabs.first : nil
    }
}
