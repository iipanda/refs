# Spike 04: Native Swift macOS menu-bar app shell (v1)

Status legend: **[V]** verified against Apple docs or the package's own page in this session. **[S]** secondary source (forum, blog, third-party page). **[U]** unverified, from memory or not found; check before relying on it.

## Recommendation

- **Shell:** AppKit `NSStatusItem` as the menu-bar icon, with the settings window in SwiftUI (hosted via `NSHostingView` or a plain `NSWindow`). AppKit gives direct control over show/hide, click handling, and the popup. `MenuBarExtra` (macOS 13+) is viable for a dumb menu but has weak control (see section 1).
- **Dock icon:** `LSUIElement = YES` in Info.plist for the default state (no Dock icon). Switch to `NSApp.setActivationPolicy(.regular)` only while the settings window is open, if the user chooses "show Dock icon". Test window activation carefully (section 2).
- **Hide menu-bar icon:** The app must always have a second way back in. Keep the Dock icon or a global hotkey as the guaranteed route. Never allow "hide menu-bar icon AND hide Dock icon" without a reachable settings path (section 2).
- **Hotkey:** `sindresorhus/KeyboardShortcuts` (v3.1.0 per its page). Sandbox/App Store compatible, ships a recorder, avoids the Accessibility permission. Do not use an `NSEvent` global monitor for the shortcut (section 3).
- **Launch at login:** `SMAppService.mainApp.register()/unregister()`, macOS 13+, check `.status` to reflect reality (section 4).
- **Distribution:** Developer ID + hardened runtime + notarization, DMG, Sparkle for updates. Skip the Mac App Store for v1 because the app needs Apple Events and screen capture, and the sandbox limits both (section 5). Sparkle size is unverified.
- **Minimum macOS:** 14 recommended (section 6). Hard floor from the APIs used is 13.
- **Idle RAM:** No verified benchmark numbers in this spike. Measure a skeleton with Activity Monitor before committing to any claim.

---

## 1. Menu-bar item: MenuBarExtra vs NSStatusItem

**MenuBarExtra (SwiftUI)**
- Availability: macOS 13.0+ [V] (developer.apple.com/documentation/swiftui/menubarextra).
- Initializers include `init(_:systemImage:isInserted:content:)` and `init(isInserted: Binding<Bool>, content:label:)`. The item is shown when the binding is `true`. If the user removes it from the menu bar (Cmd-drag), the binding is set to `false` [V]. This is the supported way to hide/show the icon.
- Styles: default menu style, or `.menuBarExtraStyle(.window)` for a popover-like window with arbitrary SwiftUI content [V].
- **Limitation [V]:** "An app that only shows in the menu bar will be automatically terminated if the user removes the extra from the menu bar." Relevant if the app has no other windows or Dock presence. Keep a non-menu-bar entry point.
- **Limitation [S]:** A third-party package (MenuBarExtraAccess, swiftpackageregistry.com) states there is no first-party API on macOS 13 to read or set presentation state, access the status item, or access the popup's NSWindow. It adds programmatic show/hide/toggle of the menu via a Bool binding. Treat the claim as the package author's reading of the API.
- **Unverified [U]:** Exact idle RAM and launch time difference versus NSStatusItem.

**NSStatusItem (AppKit)**
- Full control: `button` action, left vs right click, `isVisible`, and direct access to the popover/window. Works from macOS 10.x onward [U on exact version; standard AppKit].
- Costs: more boilerplate. Settings and popover are wired by hand.
- Footprint: both approaches are native AppKit/SwiftUI with no runtime bundled. Expect a tiny binary either way. Exact size is **[U]**. Measure with a skeleton.

**Electron comparison [U]**
- No verified numbers in this spike. Commonly cited: Electron apps idle at hundreds of MB because each ships Chromium. Mark as unverified until measured.

## 2. Dock icon and menu-bar behavior

**Static: LSUIElement**
- Info.plist key, "A Boolean value indicating whether the app is an agent app that runs in the background and doesn't appear in the Dock" [V] (developer.apple.com/documentation/bundleresources/information-property-list/lsuielement).
- Gotcha [S]: the app also loses its menu bar when active, so there is no app menu (Quit, Settings shortcut). Add your own Quit in the status menu and handle Cmd-, yourself if you want it.

**Runtime: setActivationPolicy**
- `.accessory`: "doesn't appear in the Dock and doesn't have a menu bar, but it may be activated programmatically or by clicking on one of its windows." It "corresponds to value of the LSUIElement key being 1" [V] (developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory).
- `.regular`: standard app with Dock icon and menu bar [U on exact wording; from memory].
- Gotchas [S]:
  - Developer forum thread (developer.apple.com/forums/thread/735682, "Using NSApplicationActivationPolicyAccessory does not hide the icon in dock") reports the runtime call did not reliably hide the Dock icon in some cases (child app launched by another app). Reproduce in your own build.
  - Accessory apps have trouble bringing windows forward. Workaround reported: set `.regular`, show the window, then return to `.accessory` on close. Also see developer.apple.com/forums/thread/836619 ("NSApp.activate() does not work with menu bar (background) apps").
  - Forum thread 848143 mentions a change in App Exposé behavior for accessory apps on macOS 27. This is a beta-era report [S, unverified against release notes].
- Recommended pattern: `LSUIElement=YES` for default, toggle to `.regular` when the user opens settings and "show Dock icon" is on, and back to `.accessory` on close. Call `NSApp.activate(ignoringOtherApps: true)` after switching.

**Hiding the menu-bar icon entirely**
- Options for re-entry if the menu-bar icon is hidden:
  1. Keep the Dock icon (when the user has "show Dock icon" on). Clicking the Dock icon re-opens settings. Re-open handling is `applicationShouldHandleReopen` [U; standard AppKit delegate, not verified in this session].
  2. Global hotkey that opens settings (always available if the app runs). Best fallback.
  3. Relaunch via Finder/Spotlight: relaunching an already-running app triggers the reopen delegate method [U].
- Recommendation: forbid the state "menu-bar icon hidden AND Dock icon hidden" unless a hotkey-to-settings is set. Or show settings automatically on launch when no icon is visible.
- How Bartender-style managers and CleanShot handle this: **not researched in this spike [U].** Do not state how they work without checking.

## 3. Global hotkey

**Options**
- **KeyboardShortcuts (sindresorhus)** [V for listed facts]:
  - macOS 10.15+, "fully sandboxed and Mac App Store compatible," no permission dialogs.
  - Ships `KeyboardShortcuts.Recorder` (SwiftUI) and `RecorderCocoa` (AppKit). Persists user choice (UserDefaults, [S]).
  - Warns the user when a chosen shortcut is already used by the system or the app's main menu [V].
  - Does not support media keys or Caps Lock [V].
  - Latest version 3.1.0 per the package page [V]. Swift Package Index shows a build with Swift 6.2 [S]. Check the current release before pinning.
  - Underlying API: the page says it uses Carbon for global shortcuts because Apple never shipped a replacement. The `RegisterEventHotKey` attribution comes from a secondary source [S], not verified in the package source.
- **Carbon `RegisterEventHotKey`** [U]: the call the package wraps (per [S]). Works without Accessibility permission. Official doc page could not be fetched in this session (404). Still usable in practice, but not confirmed here as deprecated or supported long-term. Only use it directly if you do not want a dependency.
- **NSEvent global monitor** [V]: `addGlobalMonitorForEvents(matching:handler:)` is observe-only, cannot block events, and "Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access." Also "your handler will not be called for events that are sent to your own application." **Conclusion: requires Accessibility permission for keys. Do not use for the hotkey.**

**Conflicts with system shortcuts**
- Cmd+Shift+4 (and Cmd+Shift+3, Cmd+Shift+5) are macOS screenshot shortcuts. Apple's Mac Help page documents Shift-Command-4 as the partial-screen capture [V, page written for 10.13]. The settings location (System Settings > Keyboard > Keyboard Shortcuts > Screenshots) is from [S]. The user can disable or change them there.
- **Plan:** Default the app's hotkey to a combo that does not collide (e.g. Ctrl+Opt+Cmd+letter or Cmd+Shift+Ctrl+letter). Use the Recorder warning. Do not silently steal system screenshot shortcuts. Carbon hotkeys can take a combo the system also uses; which wins is **[U]**, test it.

## 4. Launch at login

- `SMAppService.mainApp` is "an app service object that corresponds to the main application as a login item. Use this SMAppService to configure the main app to launch at login." macOS 13.0+ [V] (developer.apple.com/documentation/servicemanagement/smappservice/mainapp).
- API: `register()`, `unregister()`, `status` with cases `.enabled`, `.notRegistered`, `.requiresApproval`, `.notFound` [S for status cases; from third-party guide and general knowledge, verify on the SMAppService page].
- Gotchas:
  - User can disable the item in System Settings. `.requiresApproval` must be handled in the toggle UI [S].
  - Read `status` on every settings open. Do not trust a stored Bool.
  - Forum (developer.apple.com/forums/thread/791948): an Apple DTS engineer notes that registering the main app is sometimes fine, but a launch agent may be better if a background service must survive quit [S].
- Sandboxing does not block `mainApp` [U].

## 5. Distribution

**Developer ID + notarization (recommended for v1)**
- Notarization does not require sandboxing. It requires hardened runtime [S, from forum and blog; confirm on Apple's notarization page, which returned 404 in this session].
- **Apple Events** [V]: "Apple Events entitlement: a Boolean value that indicates whether the app may prompt the user for permission to send Apple events to other apps." Requires Hardened Runtime to be enabled, then Resource Access > Apple Events. Not needed for events to itself or to same-team-ID processes. macOS still asks the user for consent per target app [S].
- **Screen recording** [V on the API existence]: `CGPreflightScreenCaptureAccess()` (macOS 10.15+) and `CGRequestScreenCaptureAccess()`. Permission is a TCC privacy grant, not an entitlement [S]. A running process may need a relaunch after the user grants it [U; general knowledge]. ScreenCaptureKit is macOS 12.3+ [V]. It requires `NSScreenCaptureUsageDescription` in Info.plist [V].
- Fits a menu-bar screenshot app with browser Apple Events, which the sandbox restricts.

**Mac App Store**
- App Sandbox is mandatory: "To distribute a macOS app through the Mac App Store, you must enable the App Sandbox capability" [V].
- Sandbox restrictions relevant here [S]: sandboxed apps cannot control other apps via the Accessibility API even if the user grants it. Temporary-exception Apple Events entitlements are generally not allowed without special approval. Screen capture uses a TCC grant, but store validation rejects unsupported entitlement keys [S].
- Verdict: MAS would need a feature cut (browser Apple Events integration) or a split build. Not worth it for v1.

**Auto-updates: Sparkle**
- Open-source framework. Works with sandboxed apps (requires its sandbox guide). Uses EdDSA signing (`generate_keys`, `SUPublicEDKey`). Recommends HTTPS, Developer ID signing, and notarization [V] (sparkle-project.org/documentation).
- XPC services can be removed to save space for non-sandboxed apps [V].
- **Size cost: not verified.** Do not quote a number without measuring the framework in your build.

## 6. Minimum macOS target

- Hard floors from APIs in this spike: MenuBarExtra and SMAppService.mainApp are macOS 13.0 [V]; ScreenCaptureKit is 12.3 [V]; CGPreflight/Request screen capture is 10.15 [V]; KeyboardShortcuts is 10.15 [V].
- Recommendation: **macOS 14** as the v1 target, to get current SwiftUI/AppKit behavior and newer ScreenCaptureKit APIs. Confirm the exact availability of any specific screenshot API (e.g. single-frame capture) on its doc page before relying on it [U].
- Rationale to check: fewer OS branches to test. Not measured.

## 7. Recommended v1 skeleton (sketch, not compiled)

Info.plist: `LSUIElement = YES`, `NSScreenCaptureUsageDescription = "..."`.

```swift
import AppKit
import SwiftUI
import KeyboardShortcuts        // sindresorhus/KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", default: .init(.r, modifiers: [.control, .option, .command]))
    static let openSettings  = Self("openSettings",  default: .init(.comma, modifiers: [.control, .option, .command]))
}

@main
struct ShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { SettingsView() }   // SwiftUI settings window
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        let showIcon = UserDefaults.standard.object(forKey: "showMenuIcon") as? Bool ?? true
        if showIcon { installStatusItem() }
        KeyboardShortcuts.onKeyUp(for: .captureRegion) { /* start capture */ }
        KeyboardShortcuts.onKeyUp(for: .openSettings)  { self.openSettings() }
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory) // [U] verify window activation
    }

    func setMenuIconVisible(_ visible: Bool) {
        if visible, statusItem == nil { installStatusItem() }
        else if !visible, let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot")
        // attach NSMenu: Capture, Settings, Quit
    }

    func openSettings() {
        NSApp.setActivationPolicy(.regular)     // needed to reliably front the window [U]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) // [U] selector name
    }

    // Launch at login
    func setLaunchAtLogin(_ on: Bool) throws {
        on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
    }
}
```

Notes on the sketch:
- Selector for opening the SwiftUI `Settings` scene is **[U]** (commonly `showSettingsWindow:` on macOS 14+, earlier `showPreferencesWindow:`). Verify.
- `showDockIcon` is not defined; it is the user preference.
- Settings toggle for hide-menu-icon must keep a reachable path (Dock or hotkey). See section 2.

## 8. Open items before building

1. Measure an empty NSStatusItem app and an empty MenuBarExtra app: binary size, idle RSS, launch time. No numbers in this spike.
2. Test `.accessory` <-> `.regular` toggling for window activation on macOS 14 and 15/26.
3. Test hotkey conflicts with Cmd+Shift+3/4/5 on the target OS.
4. Confirm Sparkle framework size in a real build.
5. Check how Bartender-style tools and CleanShot handle hiding the menu-bar icon (not researched).
6. Confirm the `SMAppService` status cases and `RegisterEventHotKey` on their official pages (Apple pages for these returned titles only or 404 in this session).

## Sources

- MenuBarExtra (Apple, verified): https://developer.apple.com/documentation/swiftui/menubarextra.md
- SMAppService.mainApp (Apple): https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp.md
- NSApplication.ActivationPolicy.accessory (Apple): https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory.md
- LSUIElement (Apple): https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement.md
- NSEvent.addGlobalMonitorForEvents (Apple): https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:).md
- CGPreflightScreenCaptureAccess (Apple, availability only): https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess().md
- ScreenCaptureKit (Apple): https://developer.apple.com/documentation/screencapturekit.md
- App Sandbox (Apple): https://developer.apple.com/documentation/security/app-sandbox.md
- Apple Events entitlement (Apple): https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events.md
- KeyboardShortcuts package page (sindresorhus): https://github.com/sindresorhus/KeyboardShortcuts
- Sparkle documentation: https://sparkle-project.org/documentation/
- Forum: activation policy accessory not hiding Dock icon: https://developer.apple.com/forums/thread/735682
- Forum: NSApp.activate with menu bar apps: https://developer.apple.com/forums/thread/836619
- Forum: SMAppService / need to start app automatically: https://developer.apple.com/forums/thread/791948
- Mac help, screenshot shortcuts (10.13 page): https://support.apple.com/en-asia/guide/mac-help/mh26782/10.13
- Secondary: KeyboardShortcuts on Swift Package Index: https://swiftpackageindex.com/builds/2DA7DD71-FCF4-444C-8594-18A074EC7575
- Secondary: MenuBarExtraAccess package: https://swiftpackageregistry.com/orchetect/MenuBarExtraAccess
- Secondary: Cindori menu bar tutorial: https://cindori.com/developer/hands-on-menu-bar
- Secondary: Nil Coalescing, launch at login: https://nilcoalescing.com/blog/LaunchAtLoginSetting
- Secondary: Mac App Store vs Developer ID build matrix: https://ibl.ai/developer/os/macos-builds.md
- Secondary: Red Eye MAS rejection (2019): https://mjtsai.com/blog/2019/09/03/red-eye-rejected-from-the-mac-app-store
