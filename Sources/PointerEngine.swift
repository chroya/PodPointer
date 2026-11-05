import AppKit
import CoreMotion
import simd

/// Turns earbud motion into cursor motion and taps into clicks.
///
/// The buds sit rigidly inside the open case, so the IMU of whichever bud is
/// streaming describes the orientation of the whole case:
///   * yaw   = rotation about gravity          -> cursor X
///   * pitch = rotation about a calibrated axis -> cursor Y
/// Rotation *rate* (not absolute angle) drives cursor *velocity*, like a gyro
/// air-mouse, so there is no drift and no need to re-centre.
final class PointerEngine: NSObject, CMHeadphoneMotionManagerDelegate {
    enum State: String {
        case waiting, calibratingStill, calibratingNod, running, paused

        var menuTitle: String {
            switch self {
            case .waiting: return L("Waiting for AirPods", "等待耳机")
            case .calibratingStill: return L("Calibrating: hold still", "校准：保持不动")
            case .calibratingNod: return L("Calibrating: nod", "校准：点头")
            case .running: return L("Pointing", "指点中")
            case .paused: return L("Paused", "已暂停")
            }
        }
    }

    let cfg: Config
    var onStateChange: ((State) -> Void)?
    var onTrustChange: ((Bool) -> Void)?
    var onGuide: ((Guide) -> Void)?

    private(set) var state = State.waiting { didSet { if oldValue != state { onStateChange?(state) } } }
    private(set) var trusted = Mouse.isTrusted

    private let motion = CMHeadphoneMotionManager()
    private var timer: DispatchSourceTimer?

    // Stream health
    private var lastSample = 0.0, connectedAt = 0.0, resubscribes = 0
    private var statStart = 0.0, statCount = 0, statPeakA = 0.0, statPeakW = 0.0
    private var location: CMDeviceMotion.SensorLocation = .default
    private var lastRouteCheck = 0.0, lastRouteStatus: AudioRoute.Status?
    private var lastTrustCheck = 0.0, lastTrustWarning = 0.0

    // Calibration
    private var stateStart = 0.0
    private var stillFrames = 0
    private var lastShake = 0.0
    private var nodSamples: [SIMD3<Double>] = []
    private var firstNod: SIMD3<Double>?
    private var nodRetry = false
    private var pitch = PitchCalibration(axis: [1, 0, 0], sign: 1)
    private var calibrations = CalibrationStore.load()
    private var calibratedLocation = -1
    private var forceCalibration = false

    // Cursor
    private var vx = 0.0, vy = 0.0, remX = 0.0, remY = 0.0
    private var cursorHistory: [(t: Double, p: CGPoint)] = []
    private var freezeUntil = 0.0

    // Clicks
    private var taps: TapDetector
    private var lastClickAt = 0.0, lastClickPoint = CGPoint.zero, clickCount = 1

    // Tunables that aren't worth a CLI flag
    private let tickRate = 120.0        // cursor is interpolated at 120 Hz; motion arrives at ~50 Hz
    private let stillDuration = 1.5     // s
    private let stillTolerance = 0.15   // rad/s
    private let nodDuration = 3.5       // s
    private let nodMinRate = 0.25       // rad/s
    private let nodMinSamples = 6

    init(cfg: Config) {
        self.cfg = cfg
        self.taps = TapDetector(params: cfg.tap)
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        Log.p("PodPointer starting | mode=\(cfg.probeOnly ? "probe" : "pointer") | \(ProcessInfo.processInfo.operatingSystemVersionString)")
        Log.p("Motion permission: \(Self.describe(CMHeadphoneMotionManager.authorizationStatus())) | headphone motion available: \(motion.isDeviceMotionAvailable)")
        if !cfg.probeOnly {
            trusted = Mouse.requestTrust()
            Log.p("Accessibility: \(trusted ? "granted ✔" : "NOT granted – the cursor will not move until PodPointer is enabled in System Settings > Privacy & Security > Accessibility")")
            if !trusted {
                Mouse.openAccessibilitySettings()
                DispatchQueue.main.async { self.guide(.noAccess) }
            }
        }
        motion.delegate = self
        subscribe()

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / tickRate)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func recalibrate() {
        vx = 0; vy = 0
        forceCalibration = true
        nodRetry = false
        lastShake = 0
        enter(.calibratingStill)
        guide(.still(progress: 0, moved: false))
        Log.p(">> Calibration step 1: hold the case upright, status light facing you, pointing at the screen")
    }

    func togglePause() {
        switch state {
        case .paused: enter(.running); guide(.unpaused); Log.p(">> Resumed")
        case .running: enter(.paused); vx = 0; vy = 0; guide(.paused); Log.p(">> Paused")
        default: break
        }
    }

    // MARK: - CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        connectedAt = CACurrentMediaTime(); resubscribes = 0
        Log.p("== Motion stream connected | output: \(AudioRoute.defaultOutputName())")
        if state == .running || state == .paused { guide(.resumed) }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        let lasted = connectedAt > 0 ? String(format: "%.1fs", CACurrentMediaTime() - connectedAt) : "?"
        Log.p("== Motion stream disconnected after \(lasted) | output: \(AudioRoute.defaultOutputName())")
        guide(.disconnected)
    }

    // MARK: - Motion

    private func subscribe() {
        guard motion.isDeviceMotionAvailable else {
            Log.p("!! No head-tracking capable headphones available. Open the case lid so the AirPods connect.")
            return
        }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, err in
            if let err { Log.p("Motion error: \(err.localizedDescription)"); return }
            if let m { self?.handle(m) }
        }
        resubscribes += 1
        if resubscribes <= 2 || resubscribes % 10 == 0 { Log.p("Subscribed to headphone motion (#\(resubscribes))") }
    }

    private func handle(_ m: CMDeviceMotion) {
        let now = CACurrentMediaTime()
        lastSample = now
        let w = SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
        let a = SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
        let gRaw = SIMD3(m.gravity.x, m.gravity.y, m.gravity.z)
        let g = simd_length(gRaw) > 0.1 ? simd_normalize(gRaw) : SIMD3(0, 0, -1)
        let wMag = simd_length(w)

        logStats(m, now: now, aMag: simd_length(a), wMag: wMag, g: g)
        selectCalibration(for: m.sensorLocation)
        detectTap(a, wMag: wMag, now: now)

        switch state {
        case .calibratingStill: calibrateStill(wMag: wMag, now: now)
        case .calibratingNod: calibrateNod(w: w, g: g, now: now)
        case .running: updateVelocity(w: w, g: g)
        default: break
        }
    }

    private func logStats(_ m: CMDeviceMotion, now: Double, aMag: Double, wMag: Double, g: SIMD3<Double>) {
        if m.sensorLocation != location {
            location = m.sensorLocation
            Log.p("Motion source: \(location.label)")
        }
        statCount += 1; statPeakA = max(statPeakA, aMag); statPeakW = max(statPeakW, wMag)
        if statStart == 0 { statStart = now }
        let interval = cfg.probeOnly ? 1.0 : 5.0
        guard now - statStart >= interval else { return }
        Log.p(String(format: "%5.1f Hz | %@ | peak |w| %.3f rad/s | peak |a| %.3f g | gravity (%.2f, %.2f, %.2f) | %@",
                     Double(statCount) / (now - statStart), location.label, statPeakW, statPeakA, g.x, g.y, g.z, state.rawValue))
        statStart = now; statCount = 0; statPeakA = 0; statPeakW = 0
    }

    /// Use the stored calibration for the streaming bud, or start calibrating.
    private func selectCalibration(for loc: CMDeviceMotion.SensorLocation) {
        let key = loc.rawValue
        let needsCalibration = state == .waiting
            || (key != calibratedLocation && (state == .running || state == .paused))
        guard needsCalibration else { return }

        if let c = calibrations[key], !forceCalibration {
            pitch = c; calibratedLocation = key
            vx = 0; vy = 0
            if state == .waiting { enter(cfg.probeOnly ? .paused : .running) }
            guide(.resumed)
            Log.p(">> Using saved calibration for the \(loc.label)")
        } else if state != .calibratingStill && state != .calibratingNod {
            calibratedLocation = key
            recalibrate()
        }
    }

    // MARK: - Calibration

    /// Step 1: hold still so the nod in step 2 starts from rest
    /// (its first direction defines "up").
    private func calibrateStill(wMag: Double, now: Double) {
        if wMag > stillTolerance {
            lastShake = now
            enter(.calibratingStill)
            guide(.still(progress: 0, moved: true))
            return
        }
        stillFrames += 1
        guide(.still(progress: (now - stateStart) / stillDuration, moved: now - lastShake < 0.8))
        if now - stateStart > stillDuration && stillFrames >= 10 {
            enter(.calibratingNod)
            guide(.nod(progress: 0, detected: false, retry: nodRetry))
            Log.p(">> Calibration step 2: nod the case – tilt the top back, then forward, 3–4 times")
        }
    }

    /// Step 2: horizontal rotations collected while nodding; their principal axis
    /// is the pitch axis. Yaw needs no calibration – it is always rotation about gravity.
    private func calibrateNod(w: SIMD3<Double>, g: SIMD3<Double>, now: Double) {
        let horizontal = w - simd_dot(w, g) * g
        if simd_length(horizontal) > nodMinRate {
            nodSamples.append(horizontal)
            if firstNod == nil { firstNod = horizontal }
        }
        guide(.nod(progress: (now - stateStart) / nodDuration, detected: nodSamples.count >= nodMinSamples, retry: nodRetry))
        guard now - stateStart > nodDuration else { return }

        guard nodSamples.count >= nodMinSamples, let first = firstNod else {
            Log.p("Nod too small, retrying")
            nodRetry = true
            enter(.calibratingNod)
            return
        }
        // Principal axis of the samples via power iteration on Σ s·sᵀ.
        var cov = simd_double3x3(0)
        for s in nodSamples { cov += simd_double3x3(columns: (s * s.x, s * s.y, s * s.z)) }
        var axis = simd_normalize(first)
        for _ in 0..<40 { axis = simd_normalize(cov * axis) }

        pitch = PitchCalibration(axis: axis, sign: simd_dot(first, axis) >= 0 ? 1 : -1)
        calibratedLocation = location.rawValue
        calibrations[calibratedLocation] = pitch
        CalibrationStore.save(calibrations)
        forceCalibration = false
        nodRetry = false
        Log.p(String(format: ">> Calibrated %@: pitch axis (%.2f, %.2f, %.2f) sign %+.0f – saved",
                     location.label, axis.x, axis.y, axis.z, pitch.sign))
        guide(.done)
        enter(cfg.probeOnly ? .paused : .running)
    }

    // MARK: - Pointing

    private func updateVelocity(w: SIMD3<Double>, g: SIMD3<Double>) {
        let yaw = simd_dot(w, g)
        let pitchRate = pitch.sign * simd_dot(w, pitch.axis)
        let tx = shape(yaw) * (cfg.invertX ? -1 : 1)
        let ty = -shape(pitchRate) * (cfg.invertY ? -1 : 1)   // screen Y grows downwards
        vx = cfg.smoothing * tx + (1 - cfg.smoothing) * vx
        vy = cfg.smoothing * ty + (1 - cfg.smoothing) * vy
    }

    /// rad/s -> px/s with dead zone and mild acceleration.
    private func shape(_ rate: Double) -> Double {
        let m = max(0, abs(rate) - cfg.deadzone)
        return (rate < 0 ? -1 : 1) * cfg.gain * m * (1 + cfg.accel * m)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        checkTrust(now)
        checkRoute(now)

        if lastSample > 0 && now - lastSample > 3 {               // stream stalled: resubscribe
            if resubscribes < 2 { Log.p("!! No motion data for 3 s, resubscribing (silently from now on)") }
            lastSample = now; vx = 0; vy = 0
            motion.stopDeviceMotionUpdates(); subscribe()
            return
        }
        guard state == .running, !cfg.probeOnly else { return }
        if now - lastSample > 0.15 { vx = 0; vy = 0 }             // don't coast on stale data

        var p = Mouse.location()
        cursorHistory.append((now, p))
        if cursorHistory.count > 60 { cursorHistory.removeFirst(cursorHistory.count - 60) }
        guard now >= freezeUntil else { return }

        remX += vx / tickRate; remY += vy / tickRate
        let dx = remX.rounded(.towardZero), dy = remY.rounded(.towardZero)
        remX -= dx; remY -= dy
        guard dx != 0 || dy != 0 else { return }
        let b = Mouse.desktopBounds()
        p.x = min(max(p.x + dx, b.minX), b.maxX - 1)
        p.y = min(max(p.y + dy, b.minY), b.maxY - 1)
        Mouse.move(to: p)
    }

    // MARK: - Clicking

    private func detectTap(_ a: SIMD3<Double>, wMag: Double, now: Double) {
        switch taps.feed(acceleration: a, rotationMagnitude: wMag, at: now) {
        case .none: break
        case let .tap(m, latency):
            Log.p("TAP \(m)")
            if state == .running && !cfg.probeOnly { click(tappedAt: now - latency) }
        case let .rejected(m, reasons):
            if cfg.tapDebug || cfg.probeOnly { Log.p("  tap rejected \(m) | \(reasons.joined(separator: ", "))") }
        }
    }

    /// The tap itself jolts the case, so click where the cursor was ~100 ms before it.
    private func click(tappedAt tapTime: Double) {
        let now = CACurrentMediaTime()
        let target = cursorHistory.last(where: { tapTime - $0.t >= 0.1 })?.p ?? Mouse.location()
        freezeUntil = now + 0.2; vx = 0; vy = 0
        let samePlace = hypot(target.x - lastClickPoint.x, target.y - lastClickPoint.y) < 8
        clickCount = (now - lastClickAt < 0.45 && samePlace) ? min(clickCount + 1, 3) : 1
        lastClickAt = now; lastClickPoint = target
        Mouse.move(to: target)
        Mouse.click(at: target, count: clickCount)
        ClickRipple.show(at: target, count: clickCount)
        Log.p("CLICK x\(clickCount) @ (\(Int(target.x)), \(Int(target.y)))")
    }

    // MARK: - Environment checks

    private func checkTrust(_ now: Double) {
        guard !cfg.probeOnly, now - lastTrustCheck > 1 else { return }
        lastTrustCheck = now
        let t = Mouse.isTrusted
        if t != trusted {
            trusted = t
            Log.p(t ? "Accessibility granted ✔" : "Accessibility revoked")
            onTrustChange?(t)
            if t { onGuide?(.accessOK) } else { guide(.noAccess) }
        }
        if !t && state == .running && now - lastTrustWarning > 10 {
            lastTrustWarning = now
            Log.p("!! Pointing without Accessibility permission – mouse events are being dropped")
        }
    }

    /// While no data arrives, make sure the AirPods are the audio output (logged only on change).
    private func checkRoute(_ now: Double) {
        guard now - lastSample > 2, now - lastRouteCheck > 2 else { return }
        lastRouteCheck = now
        let status = AudioRoute.check(route: cfg.routeAudio)
        guard status != lastRouteStatus else { return }
        lastRouteStatus = status
        Log.p("[route] no motion data | \(status.description)")
        if state == .waiting { guide(.searching) }
        if case .switched(_, _, true) = status { motion.stopDeviceMotionUpdates(); subscribe() }
    }

    // MARK: - Helpers

    private func enter(_ s: State) {
        state = s
        stateStart = CACurrentMediaTime()
        stillFrames = 0
        nodSamples = []
        firstNod = nil
    }

    /// While Accessibility is missing only that warning is shown, so it isn't
    /// overwritten by calibration prompts.
    private func guide(_ g: Guide) {
        if !cfg.probeOnly && !trusted {
            guard case .noAccess = g else { return }
        }
        onGuide?(g)
    }

    private static func describe(_ s: CMAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "not determined (prompted on first use)"
        }
    }
}
