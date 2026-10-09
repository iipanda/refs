import AppKit
import CoreGraphics

/// An on-screen window from CGWindowList. `bounds` is in global CG coordinates (top-left origin).
struct WindowInfo: Equatable {
    var id: CGWindowID
    var pid: pid_t
    var ownerName: String
    var title: String?
    var bounds: CGRect

    var bundleID: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    var appName: String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? ownerName
    }
}

enum WindowList {
    /// Normal app windows, front to back. Excludes our own process, menus, the Dock and tiny windows.
    static func snapshot() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ourPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ourPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 40, bounds.height > 40
            else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { return nil }
            return WindowInfo(
                id: id,
                pid: pid,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "Unknown",
                title: (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 },
                bounds: bounds
            )
        }
    }

    /// The topmost window containing `point` (CG coordinates).
    static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.bounds.contains(point) }
    }

    /// The window a captured area most likely came from: the topmost window under the area's centre,
    /// otherwise the topmost window overlapping it.
    static func sourceWindow(for rect: CGRect, in windows: [WindowInfo]) -> WindowInfo? {
        window(at: CGPoint(x: rect.midX, y: rect.midY), in: windows)
            ?? windows.first { $0.bounds.intersects(rect) }
    }

    /// Whether `window` is its app's frontmost window, which is what AppleScript calls `front window`.
    static func isFrontmostOfApp(_ window: WindowInfo, in windows: [WindowInfo]) -> Bool {
        windows.first { $0.pid == window.pid }?.id == window.id
    }
}

/// Converts between Cocoa global coordinates (bottom-left origin) and CG global coordinates (top-left).
enum ScreenGeometry {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func cgRect(fromCocoa rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoaRect(fromCG rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgPoint(fromCocoa point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
