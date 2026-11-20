import Foundation
import Observation

/// Which CLIs the owner turned off in Settings > Appearance > CLIs (spec `docs/specs/2026-11-19-multi-cli.md`, MC3, MC9,
/// MC-R4), saved in the app's defaults domain the moment it changes. Only the CLIs turned off are stored, so a CLI the core
/// lists for the first time is on (MC9).
///
/// One instance per run (`shared`), read by `AppEnvironment`. Tests and screenshots make their own over a throwaway
/// `UserDefaults(suiteName:)`.
@MainActor
@Observable
final class CLIPreferences {
    static let disabledKey = "spacevibe.disabledCLIs"

    static let shared = CLIPreferences()

    @ObservationIgnored private let defaults: UserDefaults

    /// The CLIs turned off. Saved as a sorted list of ids.
    private(set) var disabled: Set<CLIID> {
        didSet { defaults.set(disabled.map(\.rawValue).sorted(), forKey: Self.disabledKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Setting a property in init does not fire didSet, so reading saves nothing. A value that is not a list of strings
        // (a hand edit) reads as every CLI on, never as an error.
        disabled = Set((defaults.stringArray(forKey: Self.disabledKey) ?? []).map(CLIID.init(rawValue:)))
    }

    func isOn(_ cli: CLIID) -> Bool { !disabled.contains(cli) }

    func set(_ cli: CLIID, on: Bool) {
        if on { disabled.remove(cli) } else { disabled.insert(cli) }
    }
}
