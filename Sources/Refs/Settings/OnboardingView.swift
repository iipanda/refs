import AppKit
import SwiftUI

/// First-launch setup: the two permissions Refs needs, each with one button.
struct OnboardingView: View {
    @ObservedObject var browsers: BrowserPermissionsModel
    @ObservedObject var preferences: Preferences
    let onDone: () -> Void
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var requestedScreenRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up Refs")
                    .font(.title2.weight(.semibold))
                Text("Two permissions, once. After that, press \(preferences.captureArea?.displayString ?? "your shortcut") anywhere to save a reference.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 8)

            Form {
                Section {
                    LabeledContent {
                        if screenRecording {
                            StatusPill(text: "Granted", ok: true)
                        } else if requestedScreenRecording {
                            Button("Quit & Reopen") { relaunch() }
                        } else {
                            Button("Grant…") {
                                CGRequestScreenCaptureAccess()
                                openPrivacyPane("Privacy_ScreenCapture")
                                requestedScreenRecording = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } label: {
                        step(1, "Screen Recording", requestedScreenRecording && !screenRecording
                             ? "Turn on Refs in System Settings, then quit and reopen Refs."
                             : "Needed to take screenshots.")
                    }
                }

                Section {
                    LabeledContent {
                        if browsers.allDecided {
                            StatusPill(text: "Done", ok: true)
                        } else {
                            Button(browsers.requesting == nil
                                   ? (browsers.pending.isEmpty ? "Retry Browsers" : "Allow All Browsers")
                                   : "Allowing…") {
                                if browsers.pending.isEmpty { browsers.refresh() }
                                else { browsers.allowAll() }
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(!browsers.loaded || browsers.requesting != nil)
                        }
                    } label: {
                        step(2, "Read the page you're on",
                             "Records the website's URL and title with each capture. macOS shows one prompt per browser; browsers that aren't open start in the background and close again.")
                    }
                    BrowserPermissionsList(model: browsers)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Text("You can change these later in Settings › Permissions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(screenRecording ? "Done" : "Skip for Now", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { browsers.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Quits and starts a fresh copy, which macOS needs before a new Screen Recording grant applies.
func relaunch() {
    let path = Bundle.main.bundlePath
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
    try? task.run()
    NSApp.terminate(nil)
}
