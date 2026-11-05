import CoreAudio
import Foundation

/// macOS only streams headphone motion while the AirPods are an active audio
/// output. With the buds sitting in the case this requires (1) Automatic Ear
/// Detection off and (2) the system output routed to them. This helper checks
/// and optionally fixes (2).
enum AudioRoute {
    struct Device { let id: AudioDeviceID; let name: String; let bluetooth: Bool; let hasOutput: Bool }

    enum Status: Equatable {
        case noBluetoothOutput(current: String)      // AirPods not offered as an output at all
        case active(name: String)                     // already routed to AirPods
        case switched(from: String, to: String, ok: Bool)
        case available(name: String, current: String) // present but not selected (routing disabled)

        var description: String {
            switch self {
            case .noBluetoothOutput(let cur):
                return "No Bluetooth output device (current: \(cur)). Is Automatic Ear Detection turned off?"
            case .active(let n): return "Output is \(n) ✔"
            case let .switched(f, t, ok): return "Switched output \(f) -> \(t): \(ok ? "ok" : "FAILED")"
            case let .available(n, cur): return "\(n) is available but output is \(cur) (routing disabled by --no-route)"
            }
        }
    }

    static func check(route: Bool) -> Status {
        let all = devices()
        let current = defaultOutput()
        let currentName = all.first { $0.id == current }?.name ?? "?"
        guard let bt = all.first(where: { $0.hasOutput && $0.bluetooth }) else {
            return .noBluetoothOutput(current: currentName)
        }
        if bt.id == current { return .active(name: bt.name) }
        guard route else { return .available(name: bt.name, current: currentName) }
        return .switched(from: currentName, to: bt.name, ok: setDefaultOutput(bt.id))
    }

    static func defaultOutputName() -> String {
        let id = defaultOutput()
        return devices().first { $0.id == id }?.name ?? "?"
    }

    // MARK: CoreAudio plumbing

    private static func address(_ sel: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func devices() -> [Device] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids)
        return ids.map { id in
            var na = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name)

            var ta = address(kAudioDevicePropertyTransportType)
            var transport: UInt32 = 0
            var ts = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &ta, 0, nil, &ts, &transport)

            var sa = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var streamsSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &streamsSize)

            return Device(id: id,
                          name: (name?.takeRetainedValue() as String?) ?? "?",
                          bluetooth: transport == kAudioDeviceTransportTypeBluetooth
                              || transport == kAudioDeviceTransportTypeBluetoothLE,
                          hasOutput: streamsSize > 0)
        }
    }

    private static func defaultOutput() -> AudioDeviceID {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &value) == noErr
    }
}
