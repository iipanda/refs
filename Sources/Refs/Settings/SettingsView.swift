import AppKit
import RefsCore
import ServiceManagement
import SwiftUI

extension Notification.Name {
    /// Posted when shortcut recording ends, so hotkeys get re-registered.
    static let refsShortcutsChanged = Notification.Name("RefsShortcutsChanged")
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var hotKeyStatus: HotKeyStatus

    var body: some View {
        TabView {
            GeneralTab(preferences: preferences, hotKeyStatus: hotKeyStatus)
                .tabItem { Label("General", systemImage: "gearshape") }
            PermissionsTab()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AgentsTab()
                .tabItem { Label("Agents", systemImage: "terminal") }
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Which shortcuts macOS refused to register, usually because another app owns them.
final class HotKeyStatus: ObservableObject {
    @Published var unavailable: Set<HotKeyAction> = []
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var hotKeyStatus: HotKeyStatus
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Shortcuts") {
                shortcutRow("Capture area", action: .captureArea, binding: $preferences.captureArea)
                shortcutRow("Capture window", action: .captureWindow, binding: $preferences.captureWindow)
                shortcutRow("Open library", action: .openLibrary, binding: $preferences.openLibrary)
            }

            Section {
                Toggle("Show in menu bar", isOn: $preferences.showMenuBarIcon)
                Toggle("Show in Dock", isOn: $preferences.showDockIcon)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !preferences.showMenuBarIcon {
                        Text("Refs keeps running and your shortcuts still work. Open Refs again from Finder or Spotlight to get back to Settings.")
                    }
                    if loginNeedsApproval {
                        HStack {
                            Text("Allow Refs in Login Items to finish.")
                            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                                .buttonStyle(.link)
                        }
                    }
                    if let loginError {
                        Text(loginError).foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Library") {
                    HStack {
                        Text(abbreviated(preferences.libraryURL.path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseLibrary)
                    }
                }
            } footer: {
                Text("Existing references aren't moved when you change the folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLoginStatus)
    }

    private func shortcutRow(_ title: String, action: HotKeyAction, binding: Binding<Shortcut?>) -> some View {
        LabeledContent {
            ShortcutRecorder(shortcut: binding)
        } label: {
            Text(title)
            if hotKeyStatus.unavailable.contains(action) {
                Text("Used by another app. Pick a different shortcut.")
                    .foregroundStyle(.red)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = preferences.libraryURL
        if panel.runModal() == .OK, let url = panel.url {
            preferences.libraryPath = url.path == LibraryLocation.defaultURL.path ? nil : url.path
        }
    }
}

func abbreviated(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

// MARK: - Shortcut recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                Text(recording ? "Type shortcut…" : (shortcut?.displayString ?? "Record Shortcut"))
                    .frame(minWidth: 110)
                    .foregroundStyle(recording || shortcut == nil ? .secondary : .primary)
            }
            if shortcut != nil, !recording {
                Button {
                    shortcut = nil
                    NotificationCenter.default.post(name: .refsShortcutsChanged, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        // Release the current hotkeys so pressing an existing combination records it instead of firing it.
        HotKeyCenter.shared.suspendAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc cancels
                stop()
            } else if let new = Shortcut(event: event) {
                shortcut = new
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .refsShortcutsChanged, object: nil)
    }
}

// MARK: - Permissions

private struct PermissionsTab: View {
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var browsers: [(BrowserSupport.Browser, BrowserSupport.Permission)] = []
    @State private var asking: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if screenRecording {
                        StatusPill(text: "Granted", ok: true)
                    } else {
                        Button("Grant…") {
                            CGRequestScreenCaptureAccess()
                            openPrivacyPane("Privacy_ScreenCapture")
                        }
                    }
                } label: {
                    Text("Screen Recording")
                    Text("Required to capture. After granting it, quit and reopen Refs.")
                }
            }

            Section {
                if browsers.isEmpty {
                    Text("No supported browsers found.").foregroundStyle(.secondary)
                }
                ForEach(browsers, id: \.0.bundleID) { browser, permission in
                    LabeledContent {
                        browserStatus(browser, permission)
                    } label: {
                        Label { Text(browser.name) } icon: { AppIcon(bundleID: browser.bundleID) }
                    }
                }
            } header: {
                Text("Read the current page from browsers")
            } footer: {
                Text("Lets Refs record the URL and page title. macOS asks once per browser. Firefox and Zen don't support this, so captures from them record the window title only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    @ViewBuilder
    private func browserStatus(_ browser: BrowserSupport.Browser, _ permission: BrowserSupport.Permission) -> some View {
        switch permission {
        case .granted:
            StatusPill(text: "Allowed", ok: true)
        case .denied:
            Button("Open Settings…") { openPrivacyPane("Privacy_Automation") }
        case .notDetermined:
            Button(asking == browser.bundleID ? "Waiting…" : "Allow…") { ask(browser) }
                .disabled(asking != nil)
        case .notRunning:
            Text("Open \(browser.name) to check").foregroundStyle(.secondary).font(.callout)
        case .unknown:
            StatusPill(text: "Unknown", ok: false)
        }
    }

    private func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        let installed = BrowserSupport.installed
        Task.detached {
            let statuses = installed.map { ($0, BrowserSupport.permission(for: $0.bundleID, ask: false)) }
            await MainActor.run { browsers = statuses }
        }
    }

    private func ask(_ browser: BrowserSupport.Browser) {
        asking = browser.bundleID
        Task.detached {
            _ = BrowserSupport.permission(for: browser.bundleID, ask: true)
            await MainActor.run {
                asking = nil
                refresh()
            }
        }
    }
}

func openPrivacyPane(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
    }
}

private struct StatusPill: View {
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

// MARK: - Agents

private struct AgentsTab: View {
    private var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/refs-mcp").path
    }

    private var inApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    StatusPill(text: FileManager.default.isExecutableFile(atPath: helperPath) ? "Ready" : "Missing",
                               ok: FileManager.default.isExecutableFile(atPath: helperPath))
                } label: {
                    Text("MCP server")
                    Text("Agents can list, search and view your references. Read-only.")
                }
                if !inApplications {
                    Text("Move Refs to the Applications folder before connecting agents. Their configs store the path below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Claude Code") {
                CommandBlock(text: "claude mcp add --scope user refs -- \(shellQuoted(helperPath))")
            }
            Section("Codex · ~/.codex/config.toml") {
                CommandBlock(text: "[mcp_servers.refs]\ncommand = \"\(helperPath)\"")
            }
            Section("Cursor · Claude Desktop") {
                CommandBlock(text: """
                    {
                      "mcpServers": {
                        "refs": { "command": "\(helperPath)" }
                      }
                    }
                    """)
            }
        }
        .formStyle(.grouped)
    }

    private func shellQuoted(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }
}

private struct CommandBlock: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                copy(text)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
        }
    }
}
