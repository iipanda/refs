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
                Picker("Show in Dock", selection: $preferences.dockIconMode) {
                    ForEach(DockIconMode.allCases) { Text($0.title).tag($0) }
                }
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
        // Re-check system shortcut conflicts after a trip to System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginStatus()
            preferences.objectWillChange.send()
        }
    }

    private func shortcutRow(_ title: String, action: HotKeyAction, binding: Binding<Shortcut?>) -> some View {
        LabeledContent {
            ShortcutRecorder(shortcut: binding)
        } label: {
            Text(title)
            if hotKeyStatus.unavailable.contains(action) {
                Text("Used by another app. Pick a different shortcut.")
                    .foregroundStyle(.red)
            } else if let shortcut = binding.wrappedValue, let system = SystemShortcuts.conflict(with: shortcut) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS uses \(shortcut.displayString) for “\(system)”. Turn that off so Refs gets it.")
                        .foregroundStyle(.orange)
                    Button("Keyboard Shortcuts…") { SystemShortcuts.openKeyboardShortcuts() }
                        .buttonStyle(.link)
                }
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
    @StateObject private var browsers = BrowserPermissionsModel()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if screenRecording {
                        StatusPill(text: "Granted", ok: true)
                    } else {
                        HStack {
                            Button("Grant…") {
                                CGRequestScreenCaptureAccess()
                                openPrivacyPane("Privacy_ScreenCapture")
                            }
                            Button("Quit & Reopen") { relaunch() }
                        }
                    }
                } label: {
                    Text("Screen Recording")
                    Text("Required to capture. After granting it, quit and reopen Refs.")
                }
            }

            Section {
                BrowserPermissionsList(model: browsers)
            } header: {
                HStack {
                    Text("Read the current page from browsers")
                    Spacer()
                    if !browsers.pending.isEmpty {
                        Button(browsers.requesting == nil ? "Allow All" : "Allowing…") { browsers.allowAll() }
                            .disabled(browsers.requesting != nil)
                            .controlSize(.small)
                    }
                }
            } footer: {
                Text("Lets Refs record the URL and page title. macOS asks once per browser; browsers that aren't open start in the background and close again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        if browsers.requesting == nil { browsers.refresh() }
    }
}

func openPrivacyPane(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
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

    private var setupPrompt: String {
        """
        Connect this coding agent to my local Refs library via MCP.
        Server: refs
        Executable: \(helperPath)
        Transport: stdio, no arguments.

        Identify this client and its installed version. Add Refs to its user-level MCP configuration, preserving other servers and settings. For Pi Agent or OMP, use built-in MCP support when available; check the installed version first.

        Verify with get_library_info and list_references (limit: 1). Do not add, edit or remove references during setup. Report success only after the calls work, or explain any required restart or reload.
        """
    }

    private func configurationJSON(includeTransport: Bool = false) -> String {
        var server: [String: Any] = ["command": helperPath]
        if includeTransport { server["type"] = "stdio" }
        let configuration: [String: Any] = ["mcpServers": ["refs": server]]
        guard let data = try? JSONSerialization.data(withJSONObject: configuration,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private var quotedPath: String {
        // JSON and TOML basic strings share these escapes; leave slashes literal.
        guard let data = try? JSONSerialization.data(withJSONObject: helperPath,
                                                    options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    StatusPill(text: FileManager.default.isExecutableFile(atPath: helperPath) ? "Ready" : "Missing",
                               ok: FileManager.default.isExecutableFile(atPath: helperPath))
                } label: {
                    Text("MCP server")
                    Text("Give your coding agent access to images, sources and notes in your local library.")
                }
                if !inApplications {
                    Text("Move Refs to the Applications folder before connecting agents. Their configs store the path below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Connect with a prompt") {
                Text("Copy this into your coding agent. It will configure Refs and check the connection.")
                    .foregroundStyle(.secondary)
                CommandBlock(text: setupPrompt, copyLabel: "Copy prompt", font: .callout)
            }

            Section("Manual setup") {
                Text("Merge the Refs entry into your existing configuration, then restart or reload the agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Claude Code") {
                    CommandBlock(text: "claude mcp add --scope user refs -- \(shellQuoted(helperPath))")
                }
                DisclosureGroup("Codex") {
                    Text("~/.codex/config.toml").font(.caption).foregroundStyle(.secondary)
                    CommandBlock(text: "[mcp_servers.refs]\ncommand = \(quotedPath)")
                }
                DisclosureGroup("Cursor") {
                    Text("~/.cursor/mcp.json").font(.caption).foregroundStyle(.secondary)
                    CommandBlock(text: configurationJSON(includeTransport: true))
                }
                DisclosureGroup("Claude Desktop") {
                    Text("~/Library/Application Support/Claude/claude_desktop_config.json")
                        .font(.caption).foregroundStyle(.secondary)
                    CommandBlock(text: configurationJSON())
                }
                DisclosureGroup("Pi Agent") {
                    Text("For Pi with built-in MCP. Run this in your terminal, then /reload in an open Pi session.")
                        .font(.caption).foregroundStyle(.secondary)
                    CommandBlock(text: "pi mcp add refs -- \(shellQuoted(helperPath))\npi mcp list")
                    Text("Pi stores user servers in ~/.pi/agent/mcp.json. If pi mcp is unavailable, update Pi or use your installed MCP extension's setup flow.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Pi MCP documentation", destination: URL(string: "https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md")!)
                        .font(.caption)
                }
                DisclosureGroup("OMP · Oh My Pi") {
                    Text("~/.omp/agent/mcp.json, or your active profile's agent/mcp.json")
                        .font(.caption).foregroundStyle(.secondary)
                    CommandBlock(text: configurationJSON(includeTransport: true))
                    Text("In OMP, run /mcp reload, then /mcp test refs to check the connection.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("OMP MCP documentation", destination: URL(string: "https://github.com/can1357/oh-my-pi/blob/main/docs/mcp-config.md")!)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct CommandBlock: View {
    let text: String
    var copyLabel = "Copy"
    var font: Font = .system(.caption, design: .monospaced)
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : copyLabel) {
                copy(text)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
        }
    }
}
