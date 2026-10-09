# Spike 02: Screen capture options for a macOS 15/26 menu-bar screenshot app

Status legend: **[V]** verified against an Apple page or a cited source. **[U]** unverified (from memory or a third-party/forum report that I could not confirm against Apple docs). Apple pages were fetched on 2026-10-09.

## Recommendation (v1)

1. **Capture with `/usr/sbin/screencapture -i` (shell out), not ScreenCaptureKit.** It gives region and window selection, Space-to-toggle window mode, Esc-to-cancel, and multi-monitor/Retina handling for free, and it adds almost nothing to binary size or idle cost. This matches the "tiny binary, instant capture" goal. [U on exact flags, see Details §1]
2. **Do not build a custom overlay in v1.** It is the only route to a CleanShot-style UX, but it needs ScreenCaptureKit, Screen Recording permission, and per-display window management. Defer it to v2 if the stock UI is not good enough.
3. **Source app: take `NSWorkspace.shared.frontmostApplication` at hotkey time as a heuristic.** `screencapture` does not report which window was selected. Matching the selected rect against the window list is possible but needs more work (Details §4). [U on accuracy]
4. **Permissions:** the stock `screencapture` path needs no code-level Screen Recording request from us. Whether macOS 15/26 still prompts for it when our app spawns it is **unverified**; test on a clean Tahoe machine (Details §3).
5. **Output:** PNG by default; capture at native (Retina) pixels; generate thumbnails with ImageIO. HEIC is smaller but not needed for v1. [U on size/speed numbers; not measured]
6. **Do not use `CGWindowListCreateImage`.** Apple's SDK marks it obsolete on macOS 15 (see Details §1). [V via third-party reports; Apple page fetch returned 404]

## Details

### 1. Options

| Option | Status | Region select | Window select (Cmd+Shift+4 + Space style) | Notes |
|---|---|---|---|---|
| `SCScreenshotManager.captureImage(contentFilter:configuration:)` | Available macOS 14.0+ [V, Apple page] | Only if *we* build the selection overlay (or use `captureImage(in:)`, which takes a rect) | Only if we build it, using `SCShareableContent` windows | Needs Screen Recording permission when we enumerate content [V, forum reports; §3]. Has `captureImage(in: CGRect)` and `captureScreenshot(rect:configuration:)` type methods (Apple page lists them; availability of the rect variants not separately verified). |
| `SCContentSharingPicker` | macOS 14.0+ [V, Apple page] | Yes, system UI | Yes, system UI | Apple: "Avoid creating your own sharing picker. Use … `shared`." It returns a content filter for streaming/capture; it is designed for sharing sessions (`present()`, `setConfiguration`, observers, `maximumStreamCount`), not a one-shot screenshot API. Forum/blog reports say the picker avoids the Screen Recording prompt for user-selected content [U, beta-era commentary]. It has known limits (e.g., cannot pick desktop wallpaper, per a 2025 Apple forum DTS reply [U as summarized by search]). Heavier than a one-shot tool; likely overkill for v1. |
| `/usr/sbin/screencapture -i` | Shipped CLI [V that it exists, Apple forum usage] | Yes, native | Yes: Space toggles to window mode; Esc cancels [V per search summary of man page, see below] | Zero code for UI, cursor/crosshair, dimming, multi-monitor, Retina. Output is a file or clipboard (`-c`). Downside: no hook to know the selected window, no custom overlay. |
| `CGWindowListCreateImage` | Deprecated; SDK marks it obsolete in macOS 15.0 with "Please use ScreenCaptureKit instead" [V via developer reports; Apple page 404 on fetch] | No | No | Do not use. Calling deprecated capture APIs can also trigger a privacy alert on macOS 15 [U, one forum report]. |

`screencapture` flags (from the man page synopsis `screencapture [-SWCTMPcimswxto] file` in an older copy [V that the synopsis exists]):
- `-i` interactive selection or window; `-c` to clipboard; `-t <format>` output format [V in search summary].
- `-W` start in window-selection mode; `-o` omit window shadow; `-x` silent (no sound) [U: from memory. One search result claimed `-x` disables shadow; I believe that is wrong. Verify with `man screencapture` on macOS 15 and 26 before relying on any flag.]
- Format values (`png`, `heic`, `jpg`, ...) on current macOS: [U, check `man`].

Recommended invocation to verify (not yet tested):
```
/usr/sbin/screencapture -i -t png -x /tmp/shot.png
```
Holding Control during `-i` sends the result to the clipboard [V per search summary of man page].

Deprecation of `CGWindowListCreateImage`: search results say first deprecated in macOS 14.0 and marked obsoleted in the macOS 15 SDK, with a compile error pointing to ScreenCaptureKit [V via third-party reports; I could not fetch Apple's page: 404].

### 2. Custom overlay vs `screencapture -i`; CleanShot X and Shottr

- **Custom overlay** (borderless `NSWindow` per `NSScreen`, `level` above the menu bar, crosshair cursor, dimmed frozen snapshot, hover-to-highlight window via window list, Space toggles window mode). Requires a capture of each display first, then cropping. Open-source clones do this: AiShot (frozen overlay + drag select via ScreenCaptureKit), Macshot (freezes and dims the screen, crosshair, one overlay per display), Snippr (inspired by Shottr; frozen overlay + crosshair) [V that these repos describe this; the *implementation of Shottr/CleanShot X themselves is not public* [V: no public docs found]].
- **CleanShot X / Shottr**: proprietary. I found no public statement of which capture API they use. Open-source clone BetterShot uses the system `screencapture` CLI for region/window/fullscreen capture "citing reliability" [V, README per search summary]. Treat "CleanShot uses X" as **unverified**.
- Trade-off: `screencapture -i` is reliable and free; a custom overlay gives control (annotations, freeze, UI tweaks) but adds permission dependence and complexity. One Apple forum report says ScreenCaptureKit presenter overlay only appears with full-screen capture, not window/region [V, forum thread 786301].

### 3. Permissions

**Screen Recording (TCC).**
- Our app calling ScreenCaptureKit APIs that enumerate content or capture requires Screen Recording permission. Apple's SCContentSharingPicker is the documented alternative path [V, Apple DTS reply summarized in search; the "no prompt with picker" behavior is U].
- **`screencapture` from our app:** TCC attributes the request to the *responsible process*. Forum evidence (Catalina era) shows a script run from Terminal triggers the prompt for Terminal.app, and a launchd-run script behaved differently [V, Apple forum thread 127184, search summary]. For our app, the expectation is that the prompt/permission goes to our app bundle when we spawn `screencapture` as a child, but **this is unverified on macOS 15 and 26**. A reported macOS 26.1 bug: plain unbundled executables requesting Screen Recording did not appear in the System Settings list [V, forum threads 807898/807323 as reported; regression status unclear]. Our app is bundled, so this should not apply, but test it.
- Must test: fresh-install flow on macOS 15 and 26: does `screencapture -i` (a) succeed silently, (b) show a permission prompt, (c) return only the wallpaper? Known symptom reported by users: `screencapture` returns desktop only when the parent app lacks permission [U, search summary].

**Sequoia monthly re-authorization nag.**
- Sequoia first planned weekly re-prompts, moved to monthly in beta (Aug 2024), and dropped the post-reboot prompt [V, MacTrast/9to5Mac/TechRadar/TidBITS reports, 2024]. The prompt offers "Allow For One Month" [V].
- Final Sequoia 15.x status: a 9to5Mac report said the monthly change was not yet in the 15.1 beta; a TidBITS report says Apple kept the monthly prompt through betas; a later Apple release note reportedly reduces dialogs for apps that users already accepted [U, version not identified]. **Unverified whether monthly prompts persist in 15.x final.**
- Applies to ScreenCaptureKit: developers reported that the prompt applies to ScreenCaptureKit apps unless the system picker is used [U, forum report summarized in search].
- Persistent content capture entitlement (`com.apple.developer.persistent-content-capture`): Apple-gated, requires application, intended for VNC/remote-desktop style products; not a route for a consumer screenshot app [V, Apple forum threads summarized; scope U].
- Workaround: editing `ScreenCaptureApprovals.plist` to suppress nags (Ricci Adams, Amnesia) [V that the article describes it; unsupported, do not use].
- **macOS 26 Tahoe: no source found that states the monthly prompt status.** Unverified. Test on a Tahoe machine.

### 4. Getting the window under the selection

- **`screencapture -i`**: returns pixels only. No window identity. Options: (a) take frontmost app at hotkey time (cheap, approximate; wrong when user selects a region of a non-frontmost window); (b) after capture, `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly`, pick the window whose bounds contain the selection's center, prefer frontmost. Window owner names may be available without Screen Recording permission, but window *titles* need it on macOS 10.15+ [U, from memory; verify]. (b) needs the selection rect; `screencapture` does not return it, so a rect-match would have to be done by diffing or by using the -i result position, which we do not have. **So with the shell-out path, source app is approximate (option a) unless the overlay is custom.**
- **SCScreenshotManager with own overlay**: `SCShareableContent.windows` gives `SCWindow` with `owningApplication` (bundle id, name), `frame`, `windowLayer`. Exact. Requires Screen Recording permission.
- **SCContentSharingPicker**: returns an `SCContentFilter` for the chosen content, which exposes included windows/apps. Exact for selected content [U on exact API surface; check the `SCContentFilter` docs].
- **CGWindowListCreateImage**: deprecated; avoid.

### 5. Output: PNG vs HEIC, Retina, thumbnails

- **Retina**: `screencapture` by default captures at the display's backing pixel density [U, from experience, verify]. With ScreenCaptureKit you must set `SCStreamConfiguration.width/height` to points × backing scale yourself (no Apple source verified in this spike).
- **PNG vs HEIC**: HEIC is smaller for photos, PNG is lossless and better for UI screenshots with text. Size and speed numbers were **not measured**. Recommend PNG for v1 (lossless, ImageIO-native, no HEIC encode cost concerns).
- **Thumbnail**: use ImageIO `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` and `kCGImageSourceCreateThumbnailFromImageAlways` [U, from memory of the ImageIO API; verify names against the SDK]. Generate off the main thread, lazily, only when the menu opens.

### 6. Minimal Swift sketch (v1: shell out, PNG, clipboard/file)

```swift
import AppKit

final class CaptureController {
    private var running = false

    func captureRegionOrWindow(saveTo url: URL, completion: @escaping (URL?) -> Void) {
        guard !running else { return }
        running = true

        // Approximate source app: frontmost at hotkey time (see Details §4).
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", "-t", "png", url.path]   // -x/-t flags: verify in `man screencapture`
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.running = false
                // screencapture exits 0 even on Esc in some versions; check file exists.
                let ok = proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
                _ = sourceBundleID // store alongside the capture record
                completion(ok ? url : nil)
            }
        }
        do { try p.run() } catch { running = false; completion(nil) }
    }
}

// Thumbnail (lazy, background):
func thumbnail(for url: URL, maxPixels: Int = 256) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}
```

Idle cost: `NSStatusItem` plus a hotkey (Carbon `RegisterEventHotKey` needs no Accessibility permission [U, from memory]; `NSEvent.addGlobalMonitorForEvents` does need Accessibility [U]). No timers, no polling, no background ScreenCaptureKit streams.

Binary size: not measured. Shell-out avoids linking ScreenCaptureKit entirely, which should keep it small. Verify with `ls -l` on a release build.

### Open items to verify before committing to the approach
1. Run `screencapture -i` from a bundled, signed menu-bar app on a clean macOS 15 and macOS 26 machine: permission prompt? output content (wallpaper-only failure)?
2. Confirm `-x`, `-o`, `-W`, and `-t` values on macOS 15/26 with `man screencapture`.
3. Confirm whether monthly Screen Recording re-prompts apply to macOS 15.x final and 26.
4. Measure PNG vs HEIC size/time on a real Retina screenshot.

## Sources

- Apple, SCContentSharingPicker (availability macOS 14.0+; "Avoid creating your own sharing picker"): https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker.md
- Apple, SCScreenshotManager (availability macOS 14.0+; captureImage / captureSampleBuffer / captureScreenshot signatures): https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager.md
- Apple, CGWindowListCreateImage (fetch returned 404; status from third-party reports): https://developer.apple.com/documentation/coregraphics/1454852-cgwindowlistcreateimage
- Apple Developer Forums, ScreenCaptureKit tag (picker/permission discussions): https://developer.apple.com/forums/tags/screencapturekit?page=4
- Apple Developer Forums, "ScreenCaptureKit is NOT a full replacement for CGWindowListCreateImage": https://developer.apple.com/forums/thread/849969
- Apple Developer Forums, "App is Requesting to Bypass System Private Window Picker": https://developer.apple.com/forums/thread/765103
- Apple Developer Forums, permissions within shell scripts (screencapture / Terminal responsibility): https://developer.apple.com/forums/thread/127184
- Apple Developer Forums, plain executables not in Screen Recording list on macOS 26.1: https://developer.apple.com/forums/thread/807898 and https://developer.apple.com/forums/thread/807323
- Apple Developer Forums, Presenter Overlay with ScreenCaptureKit (window/region): https://developer.apple.com/forums/thread/786301
- Apple Developer Forums, persistent-content-capture entitlement: https://developer.apple.com/forums/thread/761641 and https://developer.apple.com/forums/thread/770675
- nonstrict.eu, "A look at ScreenCaptureKit on macOS Sonoma" (2023): https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/
- MacTrast, Sequoia beta monthly screen recording prompts (Aug 2024): https://www.mactrast.com/2024/08/macos-sequoia-beta-requires-users-to-update-screen-recording-app-permissions-monthly/
- 9to5Mac, Sequoia screen recording prompt monthly (Aug 14, 2024): https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/
- TechRadar, monthly screen recording pop-ups on Sequoia: https://www.techradar.com/computing/mac-os/on-macos-sequoia-youll-only-have-to-deal-with-screen-recording-permission-pop-ups-once-a-month-rather-than-once-a-week
- TidBITS, Apple reduces excessive Sequoia permission requests (Aug 19, 2024): https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly
- Ricci Adams / lapcatsoftware, workaround via ScreenCaptureApprovals.plist (unsupported): https://pxlnv.com/linklog/sequoia-screen-recording-bypass/
- Eternal Storms, PSA on Sequoia monthly reminders (Sep 23, 2024): https://blog.eternalstorms.at/2024/09/23/psa-no-more-macos-15-sequoia-monthly-screen-recording-permission-reminders/
- Man page copy (older, incomplete): https://leancrew.com/all-this/man/man1/screencapture.html
- Eclectic Light, "Screenshots aren't simple any more" (2019): https://eclecticlight.co/2019/03/14/screenshots-arent-simple-any-more/
- BetterShot (open-source CleanShot-style app, uses screencapture CLI): https://github.com/KartikLabhshetwar/better-shot
- Mio, tiny open-source macOS screenshot app (SwiftUI + ScreenCaptureKit): https://forums.swift.org/t/mio-a-tiny-open-source-macos-screenshot-utility-built-with-swiftui-screencapturekit/87099
- Snippr (Shottr-inspired, frozen overlay): https://github.com/fantasy9876/snippr
- Not fetched or verified in this spike: ImageIO thumbnail keys, Carbon hotkey behavior, SCStreamConfiguration Retina sizing, macOS 26 release notes for screen capture.
