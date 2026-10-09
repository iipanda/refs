import AppKit
import Carbon.HIToolbox
import RefsCore

/// The active tab of one browser window, as reported over Apple Events.
struct BrowserTab: Equatable {
    var windowName: String?
    var url: String
    var title: String?
}

/// Reads the current page from scriptable browsers.
///
/// Browsers are detected from their scripting definition rather than a fixed list: anything with
/// Chrome's `active tab` (Chrome, Arc, Helium, Brave, Edge and other Chromium forks) or Safari's
/// `current tab` works. Browsers without tab scripting, like Firefox and Zen, fall back to the
/// window title.
enum BrowserSupport {
    enum Dialect { case safari, chromium }

    struct Browser: Identifiable, Hashable {
        var bundleID: String
        var name: String
        var dialect: Dialect
        var appURL: URL
        var id: String { bundleID }
    }

    /// An installed app that opens web links but can't report its current tab.
    struct UnsupportedBrowser: Identifiable, Hashable {
        var bundleID: String
        var name: String
        var id: String { bundleID }
    }

    // MARK: - Detection

    private static let lock = NSLock()
    private static var cache: [String: Browser?] = [:]

    /// The scriptable browser with this bundle ID, if it is one. Results are cached.
    static func browser(bundleID: String?) -> Browser? {
        guard let bundleID else { return nil }
        lock.lock()
        if let cached = cache[bundleID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let browser = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { probe(appURL: $0, bundleID: bundleID) }
        lock.lock()
        cache[bundleID] = browser
        lock.unlock()
        return browser
    }

    /// Installed apps that handle https links, split into those Refs can read and those it can't.
    static func installedBrowsers() -> (supported: [Browser], unsupported: [UnsupportedBrowser]) {
        guard let sample = URL(string: "https://example.com") else { return ([], []) }
        var seen = Set<String>()
        var supported: [Browser] = []
        var unsupported: [UnsupportedBrowser] = []
        for url in NSWorkspace.shared.urlsForApplications(toOpen: sample) {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier,
                  bundleID != LibraryLocation.bundleID,
                  isInstalledLocation(url), seen.insert(bundleID).inserted,
                  // Link routers like Finicky run in the background and never show pages themselves.
                  !isBackgroundOnly(bundle)
            else { continue }
            if let browser = browser(bundleID: bundleID) {
                supported.append(browser)
            } else {
                unsupported.append(UnsupportedBrowser(bundleID: bundleID, name: displayName(of: url)))
            }
        }
        return (supported.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                unsupported.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    private static func probe(appURL: URL, bundleID: String) -> Browser? {
        guard let info = Bundle(url: appURL)?.infoDictionary else { return nil }
        let scriptable = (info["NSAppleScriptEnabled"] as? Bool) ?? ((info["NSAppleScriptEnabled"] as? String)?.lowercased() == "yes")
        guard scriptable, let sdefName = info["OSAScriptingDefinition"] as? String else { return nil }
        let sdefURL = appURL.appendingPathComponent("Contents/Resources").appendingPathComponent(sdefName)
        guard let sdef = try? String(contentsOf: sdefURL, encoding: .utf8) else { return nil }

        let dialect: Dialect
        if sdef.contains("name=\"active tab\"") {
            dialect = .chromium
        } else if sdef.contains("name=\"current tab\"") {
            dialect = .safari
        } else {
            return nil
        }
        return Browser(bundleID: bundleID, name: displayName(of: appURL), dialect: dialect, appURL: appURL)
    }

    /// Folders where people install apps. Other registered copies are usually automation browsers
    /// bundled by developer tools (Windsurf, Playwright, Puppeteer) or apps nested inside other apps.
    private static let applicationFolders: [String] = [
        "/Applications/",
        "/System/Applications/",
        // Safari ships in a cryptex on macOS 13 and later.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications/",
        "/System/Cryptexes/App/System/Applications/",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/",
    ]

    private static func isInstalledLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard !path.contains(".app/Contents/") else { return false }
        return applicationFolders.contains { path.hasPrefix($0) }
    }

    private static func isBackgroundOnly(_ bundle: Bundle) -> Bool {
        let info = bundle.infoDictionary ?? [:]
        func flag(_ key: String) -> Bool {
            (info[key] as? Bool) ?? ["1", "yes", "true"].contains((info[key] as? String)?.lowercased() ?? "")
        }
        return flag("LSUIElement") || flag("LSBackgroundOnly")
    }

    private static func displayName(of appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    // MARK: - Automation permission

    enum Permission: Equatable {
        case granted, denied, notDetermined, notRunning, unknown(OSStatus)
    }

    /// Checks (and optionally asks for) permission to send Apple Events to a browser.
    /// Asking blocks until the user answers, so call it off the main thread.
    ///
    /// macOS can only answer while the browser is running; otherwise this returns `.notRunning`.
    /// Use `knownPermission(for:)` to show a status for closed browsers.
    static func permission(for bundleID: String, ask: Bool) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        let permission: Permission
        switch Int(status) {
        case Int(noErr): permission = .granted
        case errAEEventNotPermitted: permission = .denied
        case errAEEventWouldRequireUserConsent: permission = .notDetermined
        case procNotFound: permission = .notRunning
        default: permission = .unknown(status)
        }
        remember(permission, for: bundleID)
        return permission
    }

    /// The live status when the browser is running, otherwise the last answer seen for it.
    static func knownPermission(for bundleID: String) -> Permission {
        let live = permission(for: bundleID, ask: false)
        guard live == .notRunning else { return live }
        switch UserDefaults.standard.dictionary(forKey: rememberedKey)?[bundleID] as? String {
        case "granted": return .granted
        case "denied": return .denied
        default: return .notRunning
        }
    }

    static let permissionsChanged = Notification.Name("RefsBrowserPermissionsChanged")
    private static let rememberedKey = "browserPermissions"

    /// Keeps the last definite answer per browser, since macOS won't report it while the browser is closed.
    private static func remember(_ permission: Permission, for bundleID: String) {
        let value: String?
        switch permission {
        case .granted: value = "granted"
        case .denied: value = "denied"
        case .notDetermined: value = nil // e.g. reset with tccutil
        case .notRunning, .unknown: return
        }
        let defaults = UserDefaults.standard
        var remembered = defaults.dictionary(forKey: rememberedKey) as? [String: String] ?? [:]
        guard remembered[bundleID] != value else { return }
        remembered[bundleID] = value
        defaults.set(remembered, forKey: rememberedKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: permissionsChanged, object: bundleID)
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
