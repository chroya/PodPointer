import AppKit
import QuartzCore

/// Brief expanding ring at the click location, so you can see that a tap registered.
enum ClickRipple {
    private static var live: [NSWindow] = []

    /// `p` is in global CG coordinates (top-left origin).
    static func show(at p: CGPoint, count: Int) {
        guard let primary = NSScreen.screens.first else { return }
        let size: CGFloat = 64
        let origin = NSPoint(x: p.x - size / 2, y: primary.frame.height - p.y - size / 2)   // flip to Cocoa
        let w = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true
        w.contentView = v

        let ring = CAShapeLayer()
        ring.frame = v.bounds
        ring.path = CGPath(ellipseIn: v.bounds.insetBy(dx: 6, dy: 6), transform: nil)
        ring.fillColor = NSColor.systemBlue.withAlphaComponent(count > 1 ? 0.35 : 0.22).cgColor
        ring.strokeColor = NSColor.systemBlue.cgColor
        ring.lineWidth = 3
        v.layer?.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.3; scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        ring.add(group, forKey: "ripple")

        w.orderFrontRegardless()
        live.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            w.orderOut(nil)
            live.removeAll { $0 === w }
        }
    }
}
