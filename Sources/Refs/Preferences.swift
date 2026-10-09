import AppKit
import Carbon.HIToolbox
import Combine
import RefsCore

/// A global keyboard shortcut in Carbon terms, plus how to display it.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// The key's label, e.g. "2" or "F5".
    var key: String

    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static let captureAreaDefault = Shortcut(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(controlKey | shiftKey), key: "2")
    static let captureWindowDefault = Shortcut(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(controlKey | shiftKey), key: "3")

    /// Builds a shortcut from a key press. Returns nil unless ⌘, ⌃ or ⌥ is held, or the key is a function key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }

        let code = Int(event.keyCode)
        let functionKey = Self.specialKeys[code]
        let hasPrimaryModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard hasPrimaryModifier || (functionKey?.hasPrefix("F") ?? false) else { return nil }

        let label = functionKey ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !label.isEmpty else { return nil }
        self.init(keyCode: UInt32(code), carbonModifiers: modifiers, key: label)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }

    private static let specialKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]
}

enum HotKeyAction: UInt32, CaseIterable {
    case captureArea = 1
    case captureWindow = 2
    case openLibrary = 3
}

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: "showDockIcon") } }
    @Published var captureArea: Shortcut? { didSet { save(captureArea, "shortcut.captureArea") } }
    @Published var captureWindow: Shortcut? { didSet { save(captureWindow, "shortcut.captureWindow") } }
    @Published var openLibrary: Shortcut? { didSet { save(openLibrary, "shortcut.openLibrary") } }
    /// Custom library folder. Nil means the default location.
    @Published var libraryPath: String? { didSet { defaults.set(libraryPath, forKey: LibraryLocation.defaultsKey) } }

    private init() {
        defaults.register(defaults: ["showMenuBarIcon": true, "showDockIcon": false])
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        showDockIcon = defaults.bool(forKey: "showDockIcon")
        captureArea = Self.load("shortcut.captureArea", defaults: defaults, fallback: .captureAreaDefault)
        captureWindow = Self.load("shortcut.captureWindow", defaults: defaults, fallback: .captureWindowDefault)
        openLibrary = Self.load("shortcut.openLibrary", defaults: defaults, fallback: nil)
        libraryPath = defaults.string(forKey: LibraryLocation.defaultsKey)
    }

    func shortcut(for action: HotKeyAction) -> Shortcut? {
        switch action {
        case .captureArea: captureArea
        case .captureWindow: captureWindow
        case .openLibrary: openLibrary
        }
    }

    var libraryURL: URL {
        libraryPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? LibraryLocation.defaultURL
    }

    /// A shortcut that was cleared is stored as an empty Data so it doesn't fall back to the default.
    private func save(_ shortcut: Shortcut?, _ key: String) {
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: key)
    }

    private static func load(_ key: String, defaults: UserDefaults, fallback: Shortcut?) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
