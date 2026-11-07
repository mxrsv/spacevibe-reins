/// The CLI the shared components and the Loadout and Rules screens name. It is the core's own type, so a CLI read from a
/// DTO needs no conversion. A module-level declaration shadows the `InventoryCLI` that `ReinsCore` exports, which keeps
/// `InventoryCLI.claude` in the files that still import the engine compiling against the DTO type.
typealias InventoryCLI = CoreCLI
