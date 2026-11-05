import AppKit
import ApplicationServices

/// Synthetic mouse output via CGEvent. Requires the Accessibility permission;
/// without it macOS silently drops the events.
enum Mouse {
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// Current cursor position in global CG coordinates (top-left origin).
    static func location() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Union of all active displays, used to clamp the cursor.
    static func desktopBounds() -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
    }

    static func move(to p: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Left click. `count` > 1 produces double/triple clicks.
    /// A short gap between down and up keeps picky apps happy.
    static func click(at p: CGPoint, count: Int) {
        func post(_ type: CGEventType) {
            let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            e?.post(tap: .cghidEventTap)
        }
        post(.leftMouseDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { post(.leftMouseUp) }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Checks trust and shows the system prompt if needed.
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
