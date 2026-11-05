import AppKit

/// Menu bar item ("PP") + wiring between the engine and the HUD.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cfg: Config
    private let engine: PointerEngine
    private let hud = HUD()
    private var item: NSStatusItem!
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(cfg: Config) {
        self.cfg = cfg
        self.engine = PointerEngine(cfg: cfg)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = buildMenu()

        engine.onStateChange = { [weak self] s in
            self?.stateItem.title = L("Status: ", "状态：") + s.menuTitle
            self?.refreshIcon()
        }
        engine.onTrustChange = { [weak self] _ in self?.refreshIcon() }
        engine.onGuide = { [weak self] g in self?.hud.show(g) }
        stateItem.title = L("Status: ", "状态：") + engine.state.menuTitle

        if cfg.hudDemo { runHUDDemo(); return }
        engine.start()
        refreshIcon()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Recalibrate", "重新校准"), #selector(recalibrate), "r"))
        menu.addItem(menuItem(L("Pause / Resume", "暂停 / 继续"), #selector(togglePause), "p"))
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Open Log", "打开日志"), #selector(openLog), "l"))
        menu.addItem(menuItem(L("Accessibility Settings…", "打开辅助功能设置…"), #selector(openAccessibility), ""))
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Quit PodPointer", "退出 PodPointer"), #selector(quit), "q"))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    /// "PP⚠︎" = missing permission, "PP●" = pointing, "PP" = idle.
    private func refreshIcon() {
        let ok = cfg.probeOnly || engine.trusted
        item.button?.title = !ok ? "PP⚠︎" : (engine.state == .running ? "PP●" : "PP")
    }

    /// Cycles through every HUD state and writes PNG snapshots to /tmp/podpointer-hud/.
    private func runHUDDemo() {
        let dir = URL(fileURLWithPath: "/tmp/podpointer-hud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let states: [Guide] = [.searching,
                               .still(progress: 0.6, moved: false), .still(progress: 0, moved: true),
                               .nod(progress: 0.4, detected: false, retry: false), .nod(progress: 0.7, detected: true, retry: true),
                               .done, .disconnected, .noAccess]
        for (i, g) in states.enumerated() {
            let t = 0.5 + Double(i) * 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { self.hud.show(g) }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.4) {
                self.hud.snapshot(to: dir.appendingPathComponent("\(i).png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { ClickRipple.show(at: Mouse.location(), count: 1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(states.count) * 1.5) { NSApp.terminate(nil) }
    }

    @objc private func recalibrate() { engine.recalibrate() }
    @objc private func togglePause() { engine.togglePause() }
    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }
    @objc private func openAccessibility() { Mouse.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
