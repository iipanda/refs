import AppKit

/// A transparent full-screen panel that dims the screen and shows the selection. One per display.
/// It's non-activating: it receives keys and clicks while the captured app stays frontmost.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen, session: CaptureSession) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = OverlayView(session: session)
    }

    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    private unowned let session: CaptureSession
    private var trackingArea: NSTrackingArea?

    init(session: CaptureSession) {
        self.session = session
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) { session.mouseDown(at: NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { session.mouseDragged(to: NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { session.mouseUp(at: NSEvent.mouseLocation) }
    override func mouseMoved(with event: NSEvent) {
        session.mouseMoved(to: NSEvent.mouseLocation)
        cursorUpdate(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        (session.mode == .area ? NSCursor.crosshair : NSCursor.pointingHand).set()
    }

    override func rightMouseDown(with event: NSEvent) { session.cancel() }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: session.cancel() // esc
        case 49: session.toggleMode() // space
        default: break
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let window else { return }
        let origin = window.frame.origin
        func local(_ rect: NSRect) -> NSRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }

        var hole: NSRect?
        var highlightWindow = false
        if let selection = session.selection {
            hole = local(selection)
        } else if session.mode == .window, let frame = session.hoveredCocoaFrame {
            hole = local(frame)
            highlightWindow = true
        }

        let dim = NSBezierPath(rect: bounds)
        if let hole { dim.append(NSBezierPath(rect: hole)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.38).setFill()
        dim.fill()

        if let hole {
            if highlightWindow {
                NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
                NSBezierPath(rect: hole).fill()
                NSColor.controlAccentColor.setStroke()
            } else {
                NSColor.white.setStroke()
            }
            let border = NSBezierPath(rect: hole.insetBy(dx: -0.75, dy: -0.75))
            border.lineWidth = 1.5
            border.stroke()

            if let size = session.selectionPixelSize {
                drawSizeLabel("\(Int(size.width)) × \(Int(size.height))", below: hole)
            }
        }

        if window.frame.contains(NSEvent.mouseLocation) || window.isKeyWindow {
            drawHUD()
        }
    }

    private func drawSizeLabel(_ text: String, below rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var box = NSRect(x: rect.maxX - size.width - 12, y: rect.minY - size.height - 12,
                         width: size.width + 12, height: size.height + 6)
        if box.minY < bounds.minY + 4 { box.origin.y = rect.minY + 6 }
        box.origin.x = max(box.origin.x, bounds.minX + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    private func drawHUD() {
        let source = session.sourceDescription
        let modeText = session.mode == .area ? "Area" : "Window"
        let hint = "\(modeText)  ·  space to switch  ·  esc"

        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        let sourceAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: truncating,
        ]
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
        ]
        let sourceText = source as NSString
        var sourceSize = sourceText.size(withAttributes: sourceAttrs)
        sourceSize.width = min(sourceSize.width, min(bounds.width * 0.6, 640))
        let hintSize = (hint as NSString).size(withAttributes: hintAttrs)

        let padding: CGFloat = 14
        let gap: CGFloat = 18
        let width = sourceSize.width + gap + hintSize.width + padding * 2
        let height: CGFloat = 34
        let topInset = (window?.screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 24) + 14
        let box = NSRect(x: bounds.midX - width / 2, y: bounds.maxY - topInset - height, width: width, height: height)

        NSColor(white: 0.11, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: box, xRadius: 11, yRadius: 11).fill()
        sourceText.draw(in: NSRect(x: box.minX + padding, y: box.midY - sourceSize.height / 2,
                                   width: sourceSize.width, height: sourceSize.height), withAttributes: sourceAttrs)
        (hint as NSString).draw(at: NSPoint(x: box.maxX - padding - hintSize.width, y: box.midY - hintSize.height / 2),
                                withAttributes: hintAttrs)
    }
}
