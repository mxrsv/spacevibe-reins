import Observation
import SwiftUI

/// Dark is the default; the sidebar toggle overrides it and the choice is remembered.
enum AppearanceChoice: String {
    case dark, light

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var toggled: AppearanceChoice { self == .dark ? .light : .dark }
}

@MainActor
@Observable
final class AppearanceStore {
    static let defaultsKey = "reins.appearance"

    private let defaults: UserDefaults

    var choice: AppearanceChoice {
        didSet { defaults.set(choice.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard, forced: AppearanceChoice? = nil) {
        self.defaults = defaults
        // `forced` is for screenshots. Setting a property in init does not fire didSet, so nothing is saved.
        self.choice = forced ?? defaults.string(forKey: Self.defaultsKey).flatMap(AppearanceChoice.init) ?? .dark
    }

    func toggle() { choice = choice.toggled }
}
