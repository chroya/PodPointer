import CoreMotion
import Foundation
import simd

/// The pitch ("nod") axis expressed in the earbud's sensor frame.
/// Because the bud sits in a fixed slot inside the case, this only has to be
/// learned once per bud (left / right stream independently).
struct PitchCalibration: Codable {
    var axis: SIMD3<Double>
    var sign: Double     // +1 when the first calibration nod ("tilt back") maps to cursor-up
}

enum CalibrationStore {
    static let url = Config.supportDir.appendingPathComponent("calibration.json")

    static func load() -> [Int: PitchCalibration] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: PitchCalibration].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    static func save(_ all: [Int: PitchCalibration]) {
        let raw = Dictionary(uniqueKeysWithValues: all.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(raw) { try? data.write(to: url) }
    }
}

extension CMDeviceMotion.SensorLocation {
    var label: String {
        switch self {
        case .headphoneLeft: return "left bud"
        case .headphoneRight: return "right bud"
        default: return "default"
        }
    }
}
