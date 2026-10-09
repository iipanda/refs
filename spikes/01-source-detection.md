# Spike 01: Source app and source website detection (macOS 15 / macOS 26)

Status: research only, no code built or run. Facts marked **[verified]** were confirmed on an Apple or vendor page. Items marked **[reported]** come from forum posts or third-party pages. Items marked **[unverified]** are my inference or general knowledge and need a test on a real machine.

## Recommendation (v1)

1. **Source app = the app owning the window under the captured region, not `NSWorkspace.frontmostApplication`.** Snapshot `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` at capture start (before the selection overlay takes focus), take the first layer-0 window that intersects the region, and map its `kCGWindowOwnerPID` to a bundle id with `NSRunningApplication(processIdentifier:)`. Use `frontmostApplication` only as a fallback when no window intersects, or for full-screen captures.
2. **Source website = AppleScript for a short allowlist of browsers, run off the main thread with a hard timeout (about 500 ms, to be measured).** Safari and Chromium-family browsers (Chrome, Brave, Edge, Arc) expose `URL` and `title` of the active tab. Use the window title as the fallback for everything else.
3. **Fallback chain:** AppleScript URL and title, then the window title from the CG window list (`kCGWindowName`, which the app can read because it already holds Screen Recording permission), then the bare app name. Firefox and Zen get only the window title in v1. Dia and Orion are unverified and should be tested before being put on the allowlist.
4. **Distribution:** Developer ID, non-sandboxed, Hardened Runtime, with `com.apple.security.automation.apple-events` and `NSAppleEventsUsageDescription`. Do not build the v1 browser feature for the Mac App Store sandbox; it needs temporary-exception or scripting-targets entitlements, which carry review risk.
5. **Unsupported in v1:** Firefox, Zen, and any browser not on the allowlist (window title only). Dia and Orion are "test first".

---

## 1. Source app detection

### Frontmost app vs. window under the region
- `NSWorkspace.frontmostApplication` answers "which app has keyboard focus". It is the wrong answer when the user drags a region over a window that is not focused, which is the common case (for example, a Slack window visible behind a focused Terminal). **[unverified against the live page; Apple's page did not render in the fetch tool, but this follows from the API's definition]**
- The window under the region is the right answer. `CGWindowListCopyWindowInfo` returns windows in front-to-back order, with owner PID, owner name, layer, bounds, and window name. **[front-to-back ordering: unverified; confirm on the live CoreGraphics reference]**
- ScreenCaptureKit alternative: `SCShareableContent` exposes `SCWindow` with `owningApplication` (an `SCRunningApplication` with `bundleIdentifier`, `applicationName`, `processID`). WWDC22 session 10156 describes this. **[verified via search summary of WWDC22 10156; no live page fetched]** Because the app already needs Screen Recording for capture, this path is available with no extra permission. Its window ordering is not documented as front-to-back in what I checked, so do the region intersection yourself using `windowLayer` and the frame.
- Edge cases: a region spanning two windows (use the window with the largest intersection area, or the topmost one covering >50% of the region); the capture tool's own overlay and menu-bar windows (filter by layer 0); windows with `NSWindowSharingNone` may be missing from ScreenCaptureKit results (Apple forum thread 808016, reported).

### Permissions for window data
- **Owner name and PID:** reported as available without Screen Recording permission on macOS 10.15 to 26. A macOS 26 developer reported `kCGWindowOwnerName` is nil for other apps' windows without permission, and populated after granting it. A macOS 27 beta reportedly returns owner names without permission (possible regression). **[reported, conflicting; test on macOS 15 and 26]**
- **Window title (`kCGWindowName`):** reported as withheld from other processes' windows without Screen Recording permission, since macOS 10.15. Apple's CGWindowListCopyWindowInfo page did not render any permission text in my fetch. **[reported; verify on the Required Window List Keys page]**
- **Practical consequence:** the app needs Screen Recording permission for capture anyway, so titles are available in practice. If the user has not granted it, the app cannot capture at all.

---

## 2. Browser URL per browser

Methods: **AS** = AppleScript (`tell application ... to URL of active tab of front window`), **AX** = Accessibility API, **JS** = AppleScript `execute` JavaScript (avoid; see notes).

| Browser | Engine | URL via AS | Notes | Status |
|---|---|---|---|---|
| Safari | WebKit | `URL of current tab of front window` | Safari has a native dictionary with `current tab`. | Widely used pattern **[reported]**; not fetched from Apple's Safari dictionary |
| Chrome | Chromium | `URL of active tab of front window`, `title of active tab of front window` | The Chromium design doc I fetched does not list these properties. Forum posts show they work. JS execution is gated (see notes). | **[reported]** |
| Brave | Chromium | Likely same as Chrome | No sources found. | **[unverified]** |
| Edge | Chromium | Likely same as Chrome | No sources found. | **[unverified]** |
| Arc | Chromium | `URL of active tab of front window` | Reported working in a Keyboard Maestro thread. Dictionary coverage is partial (a community project says so). "Little Arc" windows reportedly do not accept AppleScript. | **[reported]** |
| Dia | Chromium | Unclear | Sources conflict: one forum post says no AppleScript support in an earlier beta, a later post says an update added it. | **[unverified]**; test |
| Orion | WebKit | `URL of current tab of window 1`; `active tab` is undocumented | Use `window index 1` or `front window`, since a named window can break `tell window 1`. | **[reported]**, partial |
| Firefox | Gecko | None | No AppleScript dictionary. Only AX/UI scripting. | **[reported]** |
| Zen | Gecko (Firefox fork) | None | Described as having effectively no tab-level scripting. | **[reported]** |

### Accessibility fallback
- Firefox-family address bar: UI scripting via System Events, walking the window toolbar to an `AXTextField` whose description contains "address". Reported as fragile and as having broken in some Firefox versions. Some reports say VoiceOver needs to be on; others say it does not. **[reported; test before relying on it]**
- `AXDocument` / `AXURL` on the window or web area: I did not verify whether Safari or Chromium expose the page URL this way on macOS 15 or 26. **[unverified]**
- Clipboard-copy-the-URL approach: works but disturbs the clipboard. Not recommended for a screenshot tool.

### JavaScript execution: avoid it
- Chromium's AppleScript page says "JavaScript injection via AppleScript will soon be disabled by default in Chrome stable". Users can re-enable it under View > Developer > Allow JavaScript from Apple Events. **[verified on chromium.org]**
- The same page recommends a published extension with Native Messaging for apps that need page content. **[verified on chromium.org]** This is the right long-term route for v1.1 if richer page data is needed.
- Safari has an equivalent gate in the Develop menu for JS execution. **[reported]**
- URL and title reads (no JS) were not described as gated in what I read. **[unverified; test that URL/title reads work with the default settings on macOS 26]**

---

## 3. Permission UX

- **Automation (Apple Events) consent:** the first Apple event from the app to a given target app triggers a TCC prompt for that target. The user can review it in System Settings > Privacy & Security > Automation. The prompt text comes from `NSAppleEventsUsageDescription`. **[reported; the usage-description key is standard, but I did not verify the current Apple wording]** The prompt is per target app, so each browser prompts once.
- **`com.apple.security.automation.apple-events`:** a Boolean that lets the app prompt to send Apple events to other apps. It is needed for non-sandboxed apps under Hardened Runtime. An app that only sends Apple events to itself or to processes with the same team ID does not need it. Enable it in Xcode via Hardened Runtime > Resource Access > Apple Events. **[verified on Apple's entitlement page]**
- **Sandboxed (App Store) apps:** a sandboxed app cannot send Apple events to other apps unless it has either a `scripting-targets` entitlement (preferred, scoped to access groups the target app publishes) or an `apple-events` temporary exception (an array of bundle ids, meant to be temporary). Requesting temporary exceptions for Finder or System Events likely fails review. **[verified on Apple QA1888]** Browsers may or may not publish access groups for URL reads; this is unverified and would need a review-risk assessment. For v1 this is not worth the risk.
- **Accessibility permission:** needed for the AX fallback only. Requested in System Settings > Privacy & Security > Accessibility, checked with `AXIsProcessTrusted`. **[general knowledge, unverified in this spike]**
- **Screen Recording:** needed for capture and for window titles. Tahoe 26.1 reportedly does not list unbundled executables in the Screen Recording pane, so ship as a real `.app` bundle. **[reported]**
- **Stable code signing:** a reported issue on macOS 26 is that ad-hoc signed builds lose permissions on every rebuild, because TCC keys off the signing identity. Use a stable Developer ID or Apple Development identity during development. **[reported]**

---

## 4. Latency

- I found no measured numbers for `osascript` round trips to Chrome or Safari, so I have no latency figures to report. **[unverified]**
- Design implications: run the Apple event on a background task, never on the main thread. Set a timeout and treat a timeout as "no URL". Start it at the moment the capture starts, in parallel with the capture, so the screenshot is not delayed; attach the result when it arrives or after a short grace period.
- Measure on macOS 15 and 26 with Safari, Chrome, and Arc: cold (first call after launch) and warm.

---

## Minimal Swift sketch (unverified; for shape only)

```swift
import AppKit
import CoreGraphics

struct SourceInfo {
    let bundleID: String?
    let appName: String?
    let windowTitle: String?
}

/// Call at capture start, before the selection overlay takes focus.
/// `rect` is in global CG coordinates (origin top-left of the primary display).
func sourceWindow(under rect: CGRect) -> SourceInfo? {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return nil }

    // Assumed front-to-back (verify). Take the first normal window that overlaps the region.
    for w in list {
        guard (w[kCGWindowLayer as String] as? Int) == 0,
              let pid = w[kCGWindowOwnerPID as String] as? pid_t,
              let boundsRaw = w[kCGWindowBounds as String],
              let bounds = CGRect(dictionaryRepresentation: boundsRaw as! CFDictionary),
              bounds.intersects(rect) else { continue }

        let app = NSRunningApplication(processIdentifier: pid)
        return SourceInfo(
            bundleID: app?.bundleIdentifier,
            appName: app?.localizedName ?? w[kCGWindowOwnerName as String] as? String,
            windowTitle: w[kCGWindowName as String] as? String  // may be nil without Screen Recording
        )
    }
    return nil
}

/// Browser URL + title via AppleScript, with a timeout. Run off the main thread.
func browserPage(bundleID: String, timeout: TimeInterval = 0.5) async -> (url: String, title: String)? {
    let script: String
    switch bundleID {
    case "com.apple.Safari":
        script = #"tell application id "com.apple.Safari" to return (URL of current tab of front window) & linefeed & (name of current tab of front window)"#
    case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser":
        // Arc's bundle id and Brave/Edge support are unverified.
        script = #"tell application id "\#(bundleID)" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)"#
    default:
        return nil  // Firefox, Zen, Dia, Orion: window-title fallback in v1
    }

    return await Task.detached(priority: .userInitiated) { () -> (String, String)? in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return nil }

        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
        guard p.terminationStatus == 0, parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }.value.map { (url: $0.0, title: $0.1) }
}
```

Notes on the sketch: the `NSAppleScript` class is an alternative to `osascript`, but it runs in-process and is harder to time out. Test whether `osascript` launched as a child process shows the TCC prompt under the app's name; it should, because the child inherits the app's responsible-process context, but this is unverified. Replace the polling loop with a proper continuation if the spike goes further.

---

## Open questions to test (in order)

1. On macOS 15 and 26, without Screen Recording permission, do `kCGWindowOwnerPID` and `kCGWindowOwnerName` come back for other apps' windows? (Decides whether the source app can be known before permission is granted.)
2. Is the CG window list front-to-back, and does it match what the user sees under a drag?
3. Does `URL of active tab of front window` work with default Chrome, Brave, Edge, and Arc settings, without enabling "Allow JavaScript from Apple Events"?
4. Dia and Orion: do the dictionaries expose URL and title on current builds?
5. Measured latency for the Apple event (cold and warm) for Safari, Chrome, and Arc.
6. Does the Automation prompt appear with the Developer ID build and the Hardened Runtime entitlement, and is it shown with the app's name?

---

## Sources

Verified on Apple or vendor pages:
- Apple Entitlement reference, Apple Events entitlement (`com.apple.security.automation.apple-events`): https://developer.apple.com/tutorials/data/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events.json
- Apple QA1888, Sandboxing and Automation in OS X (archived): https://developer.apple.com/library/content/qa/qa1888/_index.html
- Chromium AppleScript support design page: https://www.chromium.org/developers/applescript/

Found via search, not fetched in full (pages did not render, or I used the search summary):
- Apple CGWindowListCopyWindowInfo reference: https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:) (title only; no permission text rendered)
- Apple NSWorkspace.frontmostApplication: https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication (not rendered)
- Apple ScreenCaptureKit capturing screen content (sample): https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos.md
- WWDC22 session 10156 (ScreenCaptureKit): https://developer.apple.com/videos/play/wwdc2022/10156/
- WWDC22 session 10155: https://developer.apple.com/fr/videos/play/wwdc2022/10155/
- ScreenCaptureKit sample omits app with NSWindowSharingNone: https://developer.apple.com/forums/thread/808016
- Apple Developer Forums, window names and Screen Recording (macOS 10.15): https://developer.apple.com/forums/thread/126860
- Apple Developer Forums, kCGWindowOwnerName on macOS 26 and macOS 27 beta: https://developer.apple.com/forums/thread/839069
- Apple Developer Forums, ScreenCaptureKit is not a full replacement for CGWindowListCreateImage: https://developer.apple.com/forums/thread/849969
- Apple Developer Forums, Apple Events won't trigger Privacy & Security alerts due to sandboxing: https://developer.apple.com/forums/thread/771769
- Apple Developer Forums, sandboxed app Apple Events temporary-exception: https://developer.apple.com/forums/thread/665646
- Apple Developer Forums, Plain executables not appearing under Screen & System Audio Recording (macOS 26.1): https://developer.apple.com/forums/thread/807898
- Chromium permissions utils (window-name check, 10.15+): https://chromium.googlesource.com/chromium/src/+/711ab9bc/ui/base/cocoa/permissions_utils.mm
- Vivaldi forum, "Allow JavaScript from Apple Events": https://forum.vivaldi.net/topic/30458/support-for-allow-javascript-from-apple-events
- Keyboard Maestro forum, Chrome active tab AppleScript: https://forum.keyboardmaestro.com/t/applescript-for-active-tab-in-google-chrome/20146
- Keyboard Maestro forum, Arc active tab name and URL: https://forum.keyboardmaestro.com/t/copy-name-and-url-of-all-the-opened-tabs-of-the-frontmost-arc-browser-window/35178
- Keyboard Maestro forum, Orion URL or title via AppleScript: https://forum.keyboardmaestro.com/t/orion-web-browser-getting-url-or-title-via-applescript/31908
- Keyboard Maestro forum, Firefox AppleScript and UI scripting: https://forum.keyboardmaestro.com/t/url-and-title-from-firefox-subroutine/29351
- MacScripter, Firefox URL stopped working (System Events): https://macscripter.net/t/get-url-from-firefox-suddenly-stopped-working/76585
- MacScripter, Using AppleScript in Orion: https://macscripter.net/t/using-applescript-in-orion-browser/73651
- PopClip forum, Dia browser support: https://forum.popclip.app/t/support-dia-browser/3448
- Opal community, browser support (Firefox, Dia, Orion, Zen): https://community.opalapp.com/t/mac-app-browser-support-firefox-dia-atlas-orion-perplexity-ecosia-zen/264?page=3
- Resurf feedback, Zen browser automation: https://resurf.userjot.com/board/p/link-copying-doesnt-work-on-different-browser
- Apple Developer Forums, Safari "Allow JavaScript from Apple Events" on Tahoe: https://developer.apple.com/forums/thread/836299
- Apple Developer Forums, ad-hoc signing resets screen recording permission: no dedicated URL retained in this spike; see thread 807898 above.
