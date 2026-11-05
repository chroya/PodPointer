import Foundation
import simd

/// Detects a finger tap on the case from the earbud's user-acceleration stream (~50 Hz).
///
/// A tap looks like: quiet  ->  sharp onset  ->  peak within 2 frames  ->  fast decay.
/// Waving the case produces large but *smooth* acceleration, usually while rotating,
/// so it fails the "quiet before" and "fast decay" checks.
///
/// Decisions are delayed by 3 frames (~60 ms) so the decay can be observed. The onset
/// frame and the peak frame are evaluated separately because taps on a hand-held case
/// often show a double-hump waveform.
///
/// Defaults come from real hand-held measurements:
///   taps:    peak 0.24–1.07 g, jerk 0.25–1.05, decays to 0.03–0.25 g, rotation before ≤ 1.3 rad/s
///   waving:  rotation 2.2–3.1 rad/s
struct TapDetector {
    struct Params {
        var threshold = 0.20      // g      minimum peak |a|
        var jerk = 0.20           // g/frame minimum frame-to-frame change of the acceleration vector
        var decay = 0.7           // peak must fall below this fraction two frames later
        var quietAccel = 0.35     // g      mean |a| allowed in the ~160 ms before the onset
        var quietRotation = 1.8   // rad/s  mean |ω| allowed in the ~160 ms before the onset
        var refractory = 0.22     // s      minimum time between taps
    }

    struct Measurement: CustomStringConvertible {
        let peak, jerk, after, quietAccel, quietRotation: Double
        var description: String {
            String(format: "|a|=%.2f jerk=%.2f after=%.2f quietA=%.2f quietW=%.2f",
                   peak, jerk, after, quietAccel, quietRotation)
        }
    }

    enum Result {
        case none
        /// `latency` = how long ago the onset happened (seconds).
        case tap(Measurement, latency: Double)
        case rejected(Measurement, reasons: [String])
    }

    var params: Params
    private let window = 15
    private let frameDuration = 0.02
    private var mag: [Double] = []
    private var rot: [Double] = []
    private var vec: [SIMD3<Double>] = []
    private var lastTap = -Double.infinity

    init(params: Params) { self.params = params }

    mutating func feed(acceleration a: SIMD3<Double>, rotationMagnitude w: Double, at now: Double) -> Result {
        mag.append(simd_length(a)); rot.append(w); vec.append(a)
        if mag.count > window { mag.removeFirst(); rot.removeFirst(); vec.removeFirst() }
        guard mag.count == window, now - lastTap > params.refractory else { return .none }

        let k = window - 4                                         // onset candidate
        let isOnset = mag[k] > mag[k - 1] && mag[k - 1] <= mag[k - 2]
        let p = mag[k + 1] > mag[k] ? k + 1 : k                   // peak frame
        let peak = mag[p]
        let jerk = max(simd_length(vec[k] - vec[k - 1]), simd_length(vec[k + 1] - vec[k]))

        // Cheap pre-filter so we only evaluate (and log) plausible candidates.
        guard isOnset, peak > params.threshold * 0.8, jerk > params.jerk * 0.8 else { return .none }

        let before = 2..<(k - 1)                                   // ~40–200 ms before the onset
        let m = Measurement(
            peak: peak, jerk: jerk, after: mag[p + 2],
            quietAccel: before.map { mag[$0] }.reduce(0, +) / Double(before.count),
            quietRotation: before.map { rot[$0] }.reduce(0, +) / Double(before.count))

        var reasons: [String] = []
        if m.peak <= params.threshold { reasons.append(String(format: "peak %.2f<=%.2f", m.peak, params.threshold)) }
        if m.jerk <= params.jerk { reasons.append(String(format: "jerk %.2f<=%.2f", m.jerk, params.jerk)) }
        if m.after >= m.peak * params.decay { reasons.append(String(format: "no decay %.2f", m.after)) }
        if m.quietAccel >= params.quietAccel { reasons.append(String(format: "moving a=%.2f", m.quietAccel)) }
        if m.quietRotation >= params.quietRotation { reasons.append(String(format: "rotating w=%.2f", m.quietRotation)) }

        guard reasons.isEmpty else { return .rejected(m, reasons: reasons) }
        lastTap = now
        return .tap(m, latency: Double(window - 1 - k) * frameDuration)
    }
}
