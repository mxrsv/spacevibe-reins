import Foundation

/// The sections on the Settings rail, in rail order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance, limits, update

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .limits: "Limits"
        case .update: "Update"
        }
    }

    var icon: ContentGlyph {
        switch self {
        case .appearance: .palette
        case .limits: .gauge
        case .update: .refresh
        }
    }
}

extension ThemeSetting {
    var icon: ContentGlyph {
        switch self {
        case .system: .monitor
        case .light: .sun
        case .dark: .moon
        }
    }
}

/// Every sentence Settings shows that depends on state. Pure, so the tests pin it without a window.
enum SettingsWording {
    static let automaticChecks = "Check for updates automatically"
    static let automaticChecksDetail = "Once a day. Installing always takes a click."
    static let weeklyCountdown = "Weekly countdown"
    static let weeklyCountdownDetail = "When the countdown to a weekly reset starts. The 5-hour countdown always starts 1 h before."
    static let glanceWidget = "Session widget"
    static let glanceWidgetDetail = "Shows live sessions in a corner of the screen over every app."
    static let clis = "CLIs"
    static let cliNotInstalled = "Not installed"

    /// What VoiceOver reads for a CLI's row in the CLIs group: its name, and that it is not installed when it is not.
    static func cliSpoken(_ name: String, installed: Bool) -> String { installed ? name : "\(name), \(cliNotInstalled.lowercased())" }

    /// The status of the Update card: its glyph, or the warn mark when the check failed; nil when there is nothing to say
    /// beyond the time.
    struct StatusTag: Equatable {
        let text: String
        let glyph: ContentGlyph?
        var warns = false
    }

    static func tag(_ status: UpdateController.Status) -> StatusTag? {
        switch status {
        case .notChecked, .unavailable: nil
        case .checking: StatusTag(text: "Checking\u{2026}", glyph: .refresh)
        case .upToDate: StatusTag(text: "Up to date", glyph: .check)
        case .available(let version): StatusTag(text: "\(SpaceVibeMark.productName) \(version) is available", glyph: .download)
        case .failed: StatusTag(text: "Check failed", glyph: nil, warns: true)
        }
    }

    /// "Checked today at 14:02", "Checked yesterday at 09:15", "Checked Oct 29 at 14:02"; after a failed check, what went
    /// wrong (`Check Now` beside it is the way out); nil while checking or when this launch cannot update.
    static func lastCheck(_ status: UpdateController.Status, at date: Date?, now: Date, calendar: Calendar = .current) -> String? {
        switch status {
        case .checking, .unavailable: return nil
        case .failed: return "Could not read the update source."
        case .notChecked, .upToDate, .available: break
        }
        guard let date else { return "Not checked yet" }
        let time = formatted(date, "HH:mm", locale: "en_GB")
        if calendar.isDate(date, inSameDayAs: now) { return "Checked today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Checked yesterday at \(time)"
        }
        return "Checked \(formatted(date, "MMM d", locale: "en_US")) at \(time)"
    }

    /// "SpaceVibe 0.1.0", or "SpaceVibe" outside an app bundle.
    static func appName(version: String?) -> String {
        version.map { "\(SpaceVibeMark.productName) \($0)" } ?? SpaceVibeMark.productName
    }

    private static func formatted(_ date: Date, _ format: String, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
