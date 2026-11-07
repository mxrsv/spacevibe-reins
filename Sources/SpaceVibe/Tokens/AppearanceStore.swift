import AppKit
import Observation
import SwiftUI

/// An appearance that is shown: dark or light. Screenshots force one; the sidebar toggle switches to the other one.
enum AppearanceChoice: String {
    case dark, light

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var toggled: AppearanceChoice { self == .dark ? .light : .dark }
}

/// Settings > Appearance > Theme: follow macOS, or fix one appearance. Dark is the default.
enum ThemeSetting: String, CaseIterable {
    case system, light, dark

    init(_ choice: AppearanceChoice) { self = choice == .dark ? .dark : .light }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Nil for System.
    var fixed: AppearanceChoice? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The remembered Theme and Font size. The app's own store (`live`) also applies them: the theme to `NSApp.appearance`
/// (nil follows macOS; `.preferredColorScheme` does not return to the system appearance once it has been set) and the
/// font size to `TypeScale`. Screenshot and test stores apply nothing, so they never touch the window or another test.
@MainActor
@Observable
final class AppearanceStore {
    static let defaultsKey = "spacevibe.appearance"
    static let fontSizeKey = "spacevibe.fontSize"

    private let defaults: UserDefaults
    private let live: Bool
    /// A forced store (screenshots) saves nothing, even when a shot changes it.
    private let persists: Bool

    var theme: ThemeSetting {
        didSet {
            if persists { defaults.set(theme.rawValue, forKey: Self.defaultsKey) }
            applyTheme()
        }
    }

    var fontSize: FontSizeChoice {
        didSet {
            if persists { defaults.set(fontSize.rawValue, forKey: Self.fontSizeKey) }
            applyFontSize()
        }
    }

    init(defaults: UserDefaults = .standard, forced: AppearanceChoice? = nil, live: Bool = false) {
        self.defaults = defaults
        self.live = live
        persists = forced == nil
        // `forced` is for screenshots. Setting a property in init does not fire didSet, so nothing is saved.
        theme = forced.map(ThemeSetting.init) ?? defaults.string(forKey: Self.defaultsKey).flatMap(ThemeSetting.init) ?? .dark
        fontSize = forced == nil ? defaults.string(forKey: Self.fontSizeKey).flatMap(FontSizeChoice.init) ?? .standard : .standard
        applyTheme()
        applyFontSize()
    }

    /// The appearance showing now: the fixed one, or with System the one macOS has.
    var choice: AppearanceChoice { theme.fixed ?? Self.systemAppearance() }

    /// Switches to the other appearance, fixed (the sidebar toggle, the palette and the View menu).
    func toggle() { theme = ThemeSetting(choice.toggled) }

    private func applyTheme() {
        guard live else { return }
        NSApplication.shared.appearance = theme.fixed.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
    }

    private func applyFontSize() {
        guard live else { return }
        TypeScale.shared.step = fontSize.step
    }

    /// What macOS shows when nothing overrides it.
    private static func systemAppearance() -> AppearanceChoice {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }
}
