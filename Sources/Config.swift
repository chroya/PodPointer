import Foundation

/// Runtime options. Every tuning knob is a launch argument so you can adjust
/// the feel without rebuilding (rebuilding may require re-granting Accessibility).
struct Config {
    // Mode
    var probeOnly = false        // --probe       log sensor data only, never move the cursor
    var hudDemo = false          // --hud-demo    cycle through every HUD state (for screenshots)
    var routeAudio = true        // --no-route    don't switch the system output to AirPods
    var language: String? = nil  // --lang en|zh  override UI language

    // Pointer feel
    var gain = 1400.0            // --gain        pixels per radian
    var accel = 0.8              // --accel       extra gain for fast turns
    var deadzone = 0.03          // --deadzone    rad/s treated as hand tremor
    var smoothing = 0.35         // --smooth      EMA factor (higher = snappier but jittery)
    var invertX = false          // --invert-x
    var invertY = false          // --invert-y

    // Tap-to-click (see TapDetector for the algorithm)
    var tap = TapDetector.Params()
    var tapDebug = false         // --tap-debug   log rejected tap candidates and why

    static let supportDir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PodPointer")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// `open --args` is occasionally dropped by LaunchServices; scripts/run.sh
    /// therefore also writes the arguments here as a fallback.
    static let argsFile = supportDir.appendingPathComponent("launch-args")

    static func parse(_ argv: [String] = Array(CommandLine.arguments.dropFirst())) -> Config {
        var args = argv
        if args.isEmpty, let s = try? String(contentsOf: argsFile, encoding: .utf8) {
            args = s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        }
        var c = Config()
        var it = args.makeIterator()
        func num(_ fallback: Double) -> Double { Double(it.next() ?? "") ?? fallback }
        while let a = it.next() {
            switch a {
            case "--probe": c.probeOnly = true
            case "--hud-demo": c.hudDemo = true
            case "--no-route": c.routeAudio = false
            case "--route": c.routeAudio = true            // kept for backwards compatibility
            case "--lang": c.language = it.next()
            case "--gain": c.gain = num(c.gain)
            case "--accel": c.accel = num(c.accel)
            case "--deadzone": c.deadzone = num(c.deadzone)
            case "--smooth": c.smoothing = num(c.smoothing)
            case "--invert-x": c.invertX = true
            case "--invert-y": c.invertY = true
            case "--tap": c.tap.threshold = num(c.tap.threshold)
            case "--jerk": c.tap.jerk = num(c.tap.jerk)
            case "--decay": c.tap.decay = num(c.tap.decay)
            case "--quiet-a": c.tap.quietAccel = num(c.tap.quietAccel)
            case "--quiet-w": c.tap.quietRotation = num(c.tap.quietRotation)
            case "--tap-debug": c.tapDebug = true
            default: Log.p("Ignoring unknown argument: \(a)")
            }
        }
        return c
    }
}
