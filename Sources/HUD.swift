import AppKit
import QuartzCore

/// Everything the on-screen guide can show.
enum Guide {
    case searching
    case disconnected
    case still(progress: Double, moved: Bool)
    case nod(progress: Double, detected: Bool, retry: Bool)
    case done
    case resumed
    case paused, unpaused
    case noAccess
    case accessOK
}

/// Notification-style banner at the top centre of the screen.
/// Never takes focus, never intercepts the mouse, visible on every Space.
final class HUD {
    private enum Animation { case none, pulse, nod, pop }

    private struct Content {
        let key: String
        let symbol: String
        let tint: NSColor
        let title: String
        let subtitle: String
        var progress: Double? = nil
        var autoHide: Double? = nil
        var animation: Animation = .none
    }

    private let width: CGFloat = 380, height: CGFloat = 88
    private let panel: NSPanel
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let track = NSView()
    private let fill = NSView()
    private var hideWork: DispatchWorkItem?
    private var currentKey = ""
    private var animatedKey = ""

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        panel.contentView = blur

        icon.frame = NSRect(x: 18, y: (height - 44) / 2, width: 44, height: 44)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        blur.addSubview(icon)
        // Animate around the centre rather than AppKit's default bottom-left anchor.
        icon.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        icon.layer?.position = CGPoint(x: icon.frame.midX, y: icon.frame.midY)

        titleLabel.frame = NSRect(x: 76, y: height - 38, width: width - 92, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        blur.addSubview(titleLabel)

        subtitleLabel.frame = NSRect(x: 76, y: height - 60, width: width - 92, height: 18)
        subtitleLabel.font = .systemFont(ofSize: 12.5)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        blur.addSubview(subtitleLabel)

        track.frame = NSRect(x: 76, y: 14, width: width - 100, height: 4)
        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        blur.addSubview(track)
        fill.frame = NSRect(x: 0, y: 0, width: 0, height: 4)
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2
        track.addSubview(fill)
    }

    func show(_ g: Guide) { apply(Self.content(for: g)) }

    func hide() {
        hideWork?.cancel(); hideWork = nil
        currentKey = ""
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            if self?.currentKey == "" { self?.panel.orderOut(nil) }
        }
    }

    /// Renders the banner to a PNG (used by `--hud-demo`; the blur is replaced by a flat dark fill).
    func snapshot(to url: URL) {
        guard let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        let img = NSImage(size: v.bounds.size)
        img.lockFocus()
        NSColor(white: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: v.bounds, xRadius: 22, yRadius: 22).fill()
        rep.draw(in: v.bounds)
        img.unlockFocus()
        if let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
           let png = bmp.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    // MARK: - Copy

    private static func content(for g: Guide) -> Content {
        switch g {
        case .searching:
            return Content(key: "searching", symbol: "antenna.radiowaves.left.and.right", tint: .systemBlue,
                           title: L("Looking for your AirPods…", "正在寻找 AirPods…"),
                           subtitle: L("Open the lid and leave the buds inside", "打开盒盖，耳机留在盒内，稍等片刻"),
                           animation: .pulse)
        case .disconnected:
            return Content(key: "disconnected", symbol: "airpods.chargingcase", tint: .systemOrange,
                           title: L("AirPods disconnected", "AirPods 已断开"),
                           subtitle: L("Open the lid to reconnect automatically",
                                       "打开盒盖即可自动重连（合盖约 20 秒会断开）"),
                           autoHide: 5, animation: .pulse)
        case let .still(progress, moved):
            return Content(key: "still", symbol: "airpods.chargingcase.fill",
                           tint: moved ? .systemOrange : .systemBlue,
                           title: L("Step 1 · Hold the case upright", "第 1 步 · 竖起盒子，对准屏幕"),
                           subtitle: moved ? L("Movement detected – hold it steady…", "检测到晃动，请拿稳不动…")
                                           : L("Light facing you, pointing at the screen", "状态灯朝向自己，保持不动"),
                           progress: progress)
        case let .nod(progress, detected, retry):
            let warn = retry && !detected
            return Content(key: "nod", symbol: "airpods.chargingcase.fill",
                           tint: warn ? .systemOrange : (detected ? .systemGreen : .systemBlue),
                           title: warn ? L("Step 2 · Tilt a bit more", "第 2 步 · 仰得再明显一点")
                                       : L("Step 2 · Nod the case", "第 2 步 · 像点头一样转动盒子"),
                           subtitle: detected ? L("Great – keep nodding…", "很好，继续来回点头…")
                                              : L("Tilt the top back, then forward, 3–4 times", "盒子顶部先往后仰、再往前低，来回 3~4 次"),
                           progress: progress, animation: .nod)
        case .done:
            return Content(key: "done", symbol: "checkmark.circle.fill", tint: .systemGreen,
                           title: L("Calibrated – you're pointing", "校准完成，开始指点"),
                           subtitle: L("Rotate to move · tap the front to click", "转动盒子移动光标 · 轻敲盒子正面点击"),
                           autoHide: 3.5, animation: .pop)
        case .resumed:
            return Content(key: "resumed", symbol: "airpods.chargingcase.fill", tint: .systemGreen,
                           title: L("AirPods connected", "AirPods 已连接"),
                           subtitle: L("Using your saved calibration", "沿用上次的校准 · 方向不对可在菜单里重新校准"),
                           autoHide: 3, animation: .pop)
        case .paused:
            return Content(key: "paused", symbol: "pause.circle.fill", tint: .systemGray,
                           title: L("Paused", "已暂停"),
                           subtitle: L("Menu bar › Pause / Resume (⌘P)", "菜单栏 › 暂停 / 继续（⌘P）恢复"),
                           autoHide: 2)
        case .unpaused:
            return Content(key: "unpaused", symbol: "play.circle.fill", tint: .systemGreen,
                           title: L("Resumed", "继续指点"),
                           subtitle: L("Rotate to move · tap the front to click", "转动盒子移动光标 · 轻敲盒子正面点击"),
                           autoHide: 1.5)
        case .noAccess:
            return Content(key: "noAccess", symbol: "lock.shield.fill", tint: .systemRed,
                           title: L("Accessibility permission needed", "需要「辅助功能」权限"),
                           subtitle: L("Privacy & Security › Accessibility › PodPointer",
                                       "隐私与安全性 > 辅助功能 > 勾选 PodPointer"),
                           animation: .pulse)
        case .accessOK:
            return Content(key: "accessOK", symbol: "checkmark.shield.fill", tint: .systemGreen,
                           title: L("Permission granted", "权限已开启"),
                           subtitle: L("You can now control the cursor", "现在可以用盒子控制光标了"),
                           autoHide: 2, animation: .pop)
        }
    }

    // MARK: - Rendering

    private func apply(_ c: Content) {
        let isNew = c.key != currentKey
        currentKey = c.key
        if titleLabel.stringValue != c.title { titleLabel.stringValue = c.title }
        if subtitleLabel.stringValue != c.subtitle { subtitleLabel.stringValue = c.subtitle }
        icon.image = Self.symbol(c.symbol)
        icon.contentTintColor = c.tint

        if let p = c.progress {
            track.isHidden = false
            fill.layer?.backgroundColor = c.tint.cgColor
            fill.frame.size.width = track.bounds.width * CGFloat(min(max(p, 0), 1))
        } else {
            track.isHidden = true
        }

        if isNew {
            reposition()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 1
            }
            animate(c.animation, key: c.key)
        }

        hideWork?.cancel(); hideWork = nil
        if let delay = c.autoHide {
            let key = c.key
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.currentKey == key else { return }
                self.hide()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Top centre of the screen that currently contains the mouse.
    private func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.midX - width / 2, y: vf.maxY - height - 10))
    }

    private func animate(_ a: Animation, key: String) {
        guard let layer = icon.layer, animatedKey != key else { return }
        animatedKey = key
        layer.removeAllAnimations()
        switch a {
        case .none:
            break
        case .pulse:
            let an = CABasicAnimation(keyPath: "opacity")
            an.fromValue = 1; an.toValue = 0.35; an.duration = 0.8
            an.autoreverses = true; an.repeatCount = .infinity
            layer.add(an, forKey: "pulse")
        case .nod:
            // Tilt around the horizontal axis with perspective – demonstrates the gesture.
            func tilt(_ deg: CGFloat) -> NSValue {
                var t = CATransform3DIdentity
                t.m34 = -1.0 / 180
                return NSValue(caTransform3D: CATransform3DRotate(t, deg * .pi / 180, 1, 0, 0))
            }
            let an = CAKeyframeAnimation(keyPath: "transform")
            an.values = [tilt(0), tilt(-40), tilt(0), tilt(40), tilt(0)]
            an.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            an.duration = 1.2; an.repeatCount = .infinity
            layer.add(an, forKey: "nod")
        case .pop:
            let an = CAKeyframeAnimation(keyPath: "transform.scale")
            an.values = [0.6, 1.15, 1.0]; an.duration = 0.35
            layer.add(an, forKey: "pop")
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        for n in [name, "airpods.chargingcase.fill", "airpods", "hand.point.up.left.fill"] {
            if let img = NSImage(systemSymbolName: n, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                return img
            }
        }
        return nil
    }
}
