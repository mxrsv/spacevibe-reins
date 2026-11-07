import Foundation

/// What the sidebar's CLI status rows say, derived from the one CLI-level reading the shell holds: `limits.read`, which looks
/// at each CLI's folder and files (G9). The shell holds no direct "log is being read" flag, so:
///
/// - `notInstalled` (the CLI's folder is missing) is `not found`;
/// - `notMeasurable` (Gemini CLI keeps no limit on disk, and the app reads no Gemini log) is `no log`;
/// - `measured` and `notRecorded` (the folder is there and the app reads it) are `reading`;
/// - `unreadable` (a record the app cannot parse) and a CLI not read yet have no state in the mock, so they show none.
///
/// "reading" is therefore "the CLI's folder exists and the app can read it", not a live check that a log is open
/// (Hypothesis, unverified; the departure is named in the plan).
enum CLIStatusDerivation {
    static func state(of entry: CoreLimitsEntry?) -> SidebarCLIState? {
        guard let entry else { return nil }
        switch entry.state {
        case .measured, .notRecorded: return .reading
        case .notInstalled: return .notFound
        case .notMeasurable: return .noLog
        case .unreadable: return nil
        }
    }
}
