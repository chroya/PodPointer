// Minimal, dependency-free tests for TapDetector. Run with scripts/test.sh.
// Waveforms are modelled on values logged from real hand-held use (~50 Hz).

import Foundation
import simd

typealias Frame = (a: Double, w: Double)   // |user acceleration| in g, |rotation rate| in rad/s

func countTaps(_ frames: [Frame], params: TapDetector.Params = .init()) -> Int {
    var detector = TapDetector(params: params)
    var t = 100.0, taps = 0
    for f in frames {
        if case .tap = detector.feed(acceleration: SIMD3(f.a, 0, 0), rotationMagnitude: f.w, at: t) { taps += 1 }
        t += 0.02
    }
    return taps
}

let quiet = [Frame](repeating: (0.02, 0.05), count: 15)
var failures = 0

func check(_ name: String, _ frames: [Frame], expect: Int) {
    let got = countTaps(frames)
    let ok = got == expect
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name): expected \(expect), got \(got)")
}

check("sharp tap", quiet + [(0.05, 0.1), (0.45, 0.3), (0.30, 0.3), (0.08, 0.2), (0.03, 0.1)] + quiet, expect: 1)
// logged: |a|=0.24 jerk=0.25 after=0.05
check("soft tap (0.24 g)", quiet + [(0.24, 0.2), (0.05, 0.1), (0.03, 0.1)] + quiet, expect: 1)
check("double-hump tap", quiet + [(0.31, 0.2), (0.44, 0.3), (0.12, 0.2), (0.05, 0.1), (0.03, 0.1)] + quiet, expect: 1)
check("two taps 0.5 s apart",
      quiet + [(0.05, 0.1), (0.6, 0.3), (0.1, 0.2)] + [Frame](repeating: (0.02, 0.05), count: 22)
            + [(0.05, 0.1), (0.6, 0.3), (0.1, 0.2)] + quiet, expect: 2)

var waving: [Frame] = []
for i in 0..<60 { waving.append((0.5 + 0.4 * sin(Double(i) / 3), 2.6)) }
check("waving the case", quiet + waving + quiet, expect: 0)

var slowMove: [Frame] = []
for i in 0..<40 { slowMove.append((0.15 + 0.1 * sin(Double(i) / 4), 0.8)) }
check("smooth pointing movement", quiet + slowMove + quiet, expect: 0)

check("too weak (0.12 g)", quiet + [(0.03, 0.1), (0.12, 0.1), (0.04, 0.1)] + quiet, expect: 0)

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) failed.")
exit(failures == 0 ? 0 : 1)
