import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay, windowGone

    var errorDescription: String? {
        switch self {
        case .noDisplay: "The selected area isn't on any display."
        case .windowGone: "That window closed before it could be captured."
        }
    }
}

/// Takes screenshots with ScreenCaptureKit. Our own windows (the selection overlay) are always excluded.
enum ScreenCapturer {
    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Captures an area given in global CG coordinates. Areas spanning displays are clipped to the
    /// display holding most of the area.
    static func captureArea(_ rect: CGRect, content: SCShareableContent) async throws -> (CGImage, CGFloat) {
        let display = content.displays.max { a, b in
            area(a.frame.intersection(rect)) < area(b.frame.intersection(rect))
        }
        guard let display, display.frame.intersects(rect) else { throw CaptureError.noDisplay }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        let ourApps = content.applications.filter { $0.processID == ourPID }
        let filter = SCContentFilter(display: display, excludingApplications: ourApps, exceptingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)

        let clipped = rect.intersection(display.frame)
        let config = SCStreamConfiguration()
        config.sourceRect = clipped.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = Int((clipped.width * scale).rounded())
        config.height = Int((clipped.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }

    /// Captures a single window, even if it's partly covered, without its shadow.
    static func captureWindow(id: CGWindowID, content: SCShareableContent) async throws -> (CGImage, CGFloat) {
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowGone }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)

        let config = SCStreamConfiguration()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
