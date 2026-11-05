import Foundation

/// Minimal two-language localisation for user-facing text (HUD + menu).
/// Logs stay in English so bug reports are readable by everyone.
enum L10n {
    static var chinese: Bool = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

    static func configure(override lang: String?) {
        guard let lang else { return }
        chinese = lang.lowercased().hasPrefix("zh")
    }
}

/// Pick the English or Chinese variant.
func L(_ en: String, _ zh: String) -> String { L10n.chinese ? zh : en }
