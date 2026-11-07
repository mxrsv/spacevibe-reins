import Foundation

/// The sections on the Settings rail, in rail order.
enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance, update

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .update: "Update"
        }
    }

    var icon: SpaceVibeGlyph {
        switch self {
        case .appearance: .palette
        case .update: .update
        }
    }
}

extension ThemeSetting {
    var icon: SpaceVibeGlyph {
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
    /// The only language until a second one exists (spec, Interface: Language).
    static let language = "English"

    /// The status tag of the Update card; nil when there is nothing to say beyond the time.
    struct StatusTag: Equatable {
        let text: String
        let tone: TagTone
        let icon: SpaceVibeGlyph?
    }

    static func tag(_ status: UpdateController.Status) -> StatusTag? {
        switch status {
        case .notChecked, .unavailable: nil
        case .checking: StatusTag(text: "Checking\u{2026}", tone: .neutral, icon: .refresh)
        case .upToDate: StatusTag(text: "Up to date", tone: .success, icon: nil)
        case .available(let version): StatusTag(text: "SpaceVibe \(version) is available", tone: .neutral, icon: .download)
        case .failed: StatusTag(text: "Check failed", tone: .warn, icon: nil)
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
        version.map { "SpaceVibe \($0)" } ?? "SpaceVibe"
    }

    private static func formatted(_ date: Date, _ format: String, locale: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
