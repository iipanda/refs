import Foundation
import CoreGraphics
import RefsCore
import Testing
@testable import Refs

@Suite struct BrowserAutomationTests {
    @Test @MainActor func browserTabRequestsStaySerializedAndHealthyCaptureKeepsItsURL() async throws {
        let firstBrowser = syntheticBrowser(bundleID: "test.first.browser")
        let secondBrowser = syntheticBrowser(bundleID: "test.second.browser")
        let firstTabs = [BrowserTab(windowName: "First window", url: "https://first.example", title: "First")]
        let secondTabs = [BrowserTab(windowName: "Second window", url: "https://second.example", title: "Second")]
        let gate = BlockingNativeCall()
        let watchdog = watchdog(for: gate)
        defer {
            watchdog.cancel()
            gate.release()
        }
        let automation = BrowserAutomation(
            permissionLookup: { _, _ in .granted },
            tabLookup: { browser in
                gate.block()
                return browser.bundleID == firstBrowser.bundleID ? firstTabs : secondTabs
            }
        )
        let firstRequest = Task { await automation.tabs(for: firstBrowser, timeout: 1) }
        let firstStarted = await waitUntil { gate.activeCount == 1 }
        try #require(firstStarted, "The first injected tab lookup never started")
        let secondRequest = Task {
            guard await automation.permission(for: secondBrowser.bundleID, ask: false, timeout: 1) == .granted else {
                return [BrowserTab]()
            }
            return await automation.tabs(for: secondBrowser, timeout: 1)
        }
        let capture = try syntheticCapture(browser: secondBrowser, windowTitle: "Second window")
        let completion = Task {
            await capture.resolvingBrowserMetadata(tabs: secondRequest, accessLookup: { _ in nil })
        }
        // The second request reaches the serialized lookup while the first native call stays held.
        try await Task.sleep(for: .milliseconds(100))
        #expect(gate.activeCount == 1)
        gate.release()

        #expect(await firstRequest.value == firstTabs)
        #expect(await secondRequest.value == secondTabs)
        let result = await completion.value
        #expect(result.web == WebSource(url: "https://second.example", title: "Second"))
        #expect(result.image === capture.image)
        #expect(gate.maxActiveCount == 1)
        #expect(!gate.ranOnMainThread)
    }

    @Test(arguments: ["permission", "tabs"])
    @MainActor func captureFinalizationKeepsTheImageWhenBrowserMetadataStalls(blockedLookup: String) async throws {
        let browser = syntheticBrowser()
        let capture = try syntheticCapture(browser: browser)
        let gate = BlockingNativeCall()
        let watchdog = watchdog(for: gate)
        defer {
            watchdog.cancel()
            gate.release()
        }
        let automation = BrowserAutomation(
            permissionLookup: { _, _ in
                if blockedLookup == "permission" { gate.block() }
                return .granted
            },
            tabLookup: { _ in
                if blockedLookup == "tabs" { gate.block() }
                return [BrowserTab(windowName: "Selected window", url: "https://late.example", title: "Late")]
            }
        )
        let metadata = Task {
            guard await automation.permission(for: browser.bundleID, ask: false, timeout: 0.15) == .granted else {
                return [BrowserTab]()
            }
            return await automation.tabs(for: browser, timeout: 0.15)
        }

        let result = await capture.resolvingBrowserMetadata(tabs: metadata, accessLookup: { app in
            #expect(app == capture.app)
            return nil
        })

        #expect(result.image === capture.image)
        #expect(result.image.width == 1)
        #expect(result.image.height == 1)
        #expect(result.scale == capture.scale)
        #expect(result.app == capture.app)
        #expect(result.windowTitle == capture.windowTitle)
        #expect(result.frame == capture.frame)
        #expect(result.sourceWindow == capture.sourceWindow)
        #expect(result.web == nil)
        #expect(gate.activeCount == 1)
        #expect(!gate.ranOnMainThread)
    }

    @Test @MainActor func permissionDeadlineReleasesTheCallerWhileTheNativeCallIsBlocked() async throws {
        let gate = BlockingNativeCall()
        let watchdog = watchdog(for: gate)
        defer {
            watchdog.cancel()
            gate.release()
        }
        let automation = BrowserAutomation(
            maxConcurrentOperations: 1,
            permissionLookup: { _, _ in
                gate.block()
                return .granted
            },
            tabLookup: { _ in [] }
        )

        let request = Task { await automation.permission(for: "test.synthetic.browser", ask: false, timeout: 0.15) }
        let started = await waitUntil { gate.activeCount == 1 }
        try #require(started, "The injected native permission call never started")
        // The test resumes on MainActor while the synchronous native call is still held.
        #expect(!gate.ranOnMainThread)
        let result = await request.value

        #expect(result == .unknown(-1712))
        #expect(gate.activeCount == 1)
    }

    @Test func tabDeadlineFallsBackWhileTheNativeCallIsBlocked() async {
        let gate = BlockingNativeCall()
        let watchdog = watchdog(for: gate)
        defer {
            watchdog.cancel()
            gate.release()
        }
        let lateTabs = [BrowserTab(windowName: "Late window", url: "https://late.example", title: "Late")]
        let automation = BrowserAutomation(
            maxConcurrentOperations: 1,
            permissionLookup: { _, _ in .granted },
            tabLookup: { _ in
                gate.block()
                return lateTabs
            }
        )

        let tabs = await automation.tabs(for: syntheticBrowser(), timeout: 0.15)

        #expect(tabs.isEmpty)
        #expect(gate.activeCount == 1)
        #expect(!gate.ranOnMainThread)
    }

    @Test func successfulInjectedLookupsPreservePermissionAndTabs() async {
        let browser = syntheticBrowser()
        let expectedTabs = [BrowserTab(windowName: "Selected window", url: "https://selected.example", title: "Selected")]
        let automation = BrowserAutomation(
            permissionLookup: { bundleID, ask in
                #expect(bundleID == browser.bundleID)
                #expect(!ask)
                return .granted
            },
            tabLookup: { requestedBrowser in
                #expect(requestedBrowser == browser)
                return expectedTabs
            }
        )

        #expect(await automation.permission(for: browser.bundleID, ask: false) == .granted)
        #expect(await automation.tabs(for: browser) == expectedTabs)
    }

    @Test(arguments: [BrowserSupport.Permission.unknown(-1712), .notRunning, .notDetermined])
    @MainActor func unavailablePermissionDoesNotDecideAllBrowsers(permission: BrowserSupport.Permission) async throws {
        let browser = syntheticBrowser()
        let model = BrowserPermissionsModel(
            observeChanges: false,
            loadBrowsers: { (supported: [browser], unsupported: []) },
            lookupPermission: { _ in permission }
        )

        model.refresh()
        let loaded = await waitUntil { await MainActor.run { model.loaded } }
        try #require(loaded)

        #expect(model.rows.map(\.permission) == [permission])
        #expect(!model.allDecided)
    }

    @Test @MainActor func refreshesCoalesceWhilePermissionLookupIsHeld() async throws {
        let browser = syntheticBrowser()
        let gate = HeldPermissionLookup()
        let watchdog = DispatchWorkItem { gate.releaseAll() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
        defer {
            watchdog.cancel()
            gate.releaseAll()
        }
        let model = BrowserPermissionsModel(
            observeChanges: false,
            loadBrowsers: { (supported: [browser], unsupported: []) },
            lookupPermission: { _ in await gate.lookup() }
        )

        for _ in 0..<16 { model.refresh() }
        let started = await waitUntil { gate.activeCount > 0 }
        try #require(started, "The injected permission lookup never started")
        // Give all queued refreshes a chance to reach the held lookup. A coalesced refresh keeps
        // exactly one lookup active throughout this interval.
        _ = await waitUntil(timeout: .milliseconds(250)) { gate.activeCount == 16 }

        #expect(gate.activeCount == 1)
        #expect(!model.loaded)
        gate.releaseAll()
        let loaded = await waitUntil { await MainActor.run { model.loaded } }
        #expect(loaded)
    }

    @Test func matchesTheSelectedWindowBeforeTheFrontTab() {
        let window = WindowInfo(
            id: 1, pid: -1, ownerName: "Synthetic Browser", title: "Selected window",
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
        let frontTab = BrowserTab(windowName: "Front window", url: "https://front.example", title: "Front")
        let selectedTab = BrowserTab(windowName: "Selected window", url: "https://selected.example", title: "Selected")

        #expect(BrowserSupport.tab(for: window, among: [frontTab, selectedTab], isFrontmostOfApp: false) == selectedTab)
    }
}

private func syntheticBrowser(bundleID: String = "test.synthetic.browser") -> BrowserSupport.Browser {
    BrowserSupport.Browser(
        bundleID: bundleID, name: "Synthetic Browser", dialect: .chromium,
        appURL: URL(fileURLWithPath: "/not-an-installed-app/Synthetic.app")
    )
}

private func syntheticCapture(
    browser: BrowserSupport.Browser, windowTitle: String = "Selected window"
) throws -> CaptureResult {
    let provider = try #require(CGDataProvider(data: Data([0, 0, 0, 255]) as CFData))
    let image = try #require(CGImage(
        width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ))
    let window = WindowInfo(
        id: 1, pid: -1, ownerName: browser.name, title: windowTitle,
        bounds: CGRect(x: 10, y: 20, width: 100, height: 100)
    )
    return CaptureResult(
        image: image, scale: 2, app: SourceApp(name: browser.name, bundleID: browser.bundleID),
        windowTitle: windowTitle, web: nil, browserAccess: nil, frame: window.bounds,
        sourceWindow: window, sourceWindowIsFrontmostOfApp: true
    )
}

private final class BlockingNativeCall: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false
    private var active = 0
    private var maximumActive = 0
    private var mainThread = false

    var activeCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return active
    }

    var ranOnMainThread: Bool {
        condition.lock()
        defer { condition.unlock() }
        return mainThread
    }

    var maxActiveCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return maximumActive
    }

    func block() {
        condition.lock()
        active += 1
        maximumActive = max(maximumActive, active)
        mainThread = mainThread || Thread.isMainThread
        while !released { condition.wait() }
        active -= 1
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private func watchdog(for gate: BlockingNativeCall) -> DispatchWorkItem {
    let watchdog = DispatchWorkItem { gate.release() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
    return watchdog
}

private final class HeldPermissionLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<BrowserSupport.Permission, Never>] = []
    private var released = false

    var activeCount: Int { lock.withLock { continuations.count } }

    func lookup() async -> BrowserSupport.Permission {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard !released else { return true }
                continuations.append(continuation)
                return false
            }
            if shouldResume { continuation.resume(returning: .granted) }
        }
    }

    func releaseAll() {
        let pending = lock.withLock {
            released = true
            let pending = continuations
            continuations.removeAll()
            return pending
        }
        pending.forEach { $0.resume(returning: .granted) }
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1), condition: () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}
