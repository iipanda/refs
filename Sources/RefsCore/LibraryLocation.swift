import Foundation

/// Where the library lives. Shared between the app and the MCP helper.
public enum LibraryLocation {
    public static let bundleID = "com.karolchudzik.refs"
    /// UserDefaults key for a custom library folder chosen in Settings.
    public static let defaultsKey = "libraryPath"
    /// Environment override, mainly for tests and for pointing an agent at another library.
    public static let environmentKey = "REFS_LIBRARY"

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Refs", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    /// Resolves the folder from, in order: `REFS_LIBRARY`, the app's saved preference, the default.
    ///
    /// The helper reads the app's preferences domain directly, because it runs as a separate process
    /// launched by the agent.
    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[environmentKey], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let saved = CFPreferencesCopyAppValue(defaultsKey as CFString, bundleID as CFString) as? String,
           !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        return defaultURL
    }
}
