/// A CLI's name and look, read from `CLICatalog.current` (MC-R1, MC27). Views write `cli.label` or `cli.identity.tone`; the
/// facts live in the core's `clis.list` and the look in `CLIRegistry` only.
extension CLIID {
    var identity: CLIIdentity { CLICatalog.current.identity(self) }
    /// The CLI's name as the app writes it (GLOSSARY).
    var label: String { identity.label }
}
