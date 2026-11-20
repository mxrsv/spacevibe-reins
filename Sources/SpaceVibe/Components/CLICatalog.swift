import Foundation
import Observation

/// The CLIs the app shows (MC27, MC-R4): the core's `clis.list`, joined to each CLI's look in `CLIRegistry`, minus the CLIs the
/// owner turned off in Settings. One lookup, `info(for:)`; every page asks it (through `cli.identity` and the lists below)
/// instead of naming a CLI, and every core result goes through its filter (`CLICatalogFilter.swift`) before a page reads
/// it, so an id the core did not list, or one that is off, appears nowhere and in no "missing in" comparison.
///
/// The app's catalog is `current`: what `AppEnvironment` built from the last `clis.list`, or empty before it lands. A test
/// that needs another catalog sets `CLICatalog.$scoped` for its task instead of changing the app's.
struct CLICatalog: Sendable {
    /// Every CLI `clis.list` returned, in the core's registry order, on or off. Settings lists these.
    let all: [CLIIdentity]
    /// The CLIs the owner turned off. An id the core does not list is ignored.
    let disabled: Set<CLIID>
    /// `all` minus `disabled`: the CLIs every page shows.
    let shown: [CLIIdentity]

    init(list: [CoreCLIInfo], looks: [CLIID: CLILook] = CLIRegistry.looks, disabled: Set<CLIID> = []) {
        all = list.map { CLIIdentity($0, look: looks[$0.id] ?? CLIRegistry.neutral) }
        self.disabled = disabled
        shown = all.filter { !disabled.contains($0.id) }
    }

    /// No CLI: before the first `clis.list`, nothing is shown.
    static let empty = CLICatalog(list: [])

    /// The CLI as a page shows it, or nil when it is unknown to the core or turned off: such an id is never shown.
    func info(for id: CLIID) -> CLIIdentity? { shown.first { $0.id == id } }

    func isShown(_ id: CLIID) -> Bool { info(for: id) != nil }

    /// Every listed CLI's name, look and facts, on or off: a page that belongs to one CLI by nature (Rules) and Settings still
    /// name a CLI that is off. An id the core did not list reads as `unlisted`; the filter keeps such an id off every page.
    func identity(_ id: CLIID) -> CLIIdentity { all.first { $0.id == id } ?? .unlisted(id) }

    /// Whether the owner has `id` on: true for every CLI not turned off, so a newly detected CLI is on (MC9).
    func isEnabled(_ id: CLIID) -> Bool { !disabled.contains(id) }

    /// The shown CLIs that have an inventory (Skills, Subagents, Hooks, the copy actions), in registry order.
    var inventoryCLIs: [CLIID] { shown.filter { $0.has(.inventory) }.map(\.id) }
    /// The shown CLIs with a Limits reading, in registry order.
    var limitsCLIs: [CLIID] { shown.filter { $0.has(.limits) }.map(\.id) }

    /// The shown CLIs an item of `kind` in `source` can be copied into (MC-R8): written (`full`), and reading the same copy
    /// format as `source` does for that kind. Nothing is converted, so a CLI with another format, or none, is not a target.
    func copyTargets(for kind: CoreKind, from source: CLIID) -> [CLIID] {
        guard let format = info(for: source)?.kind(kind)?.copyFormat else { return [] }
        return shown.filter { cli in
            guard cli.id != source, cli.has(.inventory), let info = cli.kind(kind) else { return false }
            return info.support == .full && info.copyFormat == format
        }.map(\.id)
    }

    /// The shown CLIs whose `kind` can be copied into `target`, in registry order: where a copy into `target` comes from.
    func copySources(for kind: CoreKind, to target: CLIID) -> [CLIID] {
        inventoryCLIs.filter { copyTargets(for: kind, from: $0).contains(target) }
    }
}

// MARK: The app's catalog

extension CLICatalog {
    /// A test's own catalog for its task (and the tasks it starts); nil in the app.
    @TaskLocal static var scoped: CLICatalog?

    /// The catalog every page reads. Reading it inside a view body or an `@Observable` model's derived value tracks it, so a
    /// page redraws when `clis.list` lands or a CLI is turned on or off.
    static var current: CLICatalog { scoped ?? CLICatalogStore.shared.catalog }
}

/// Holds the app's catalog. `AppEnvironment` writes it; any thread may read it. Observable by hand, because the macro's storage
/// is not safe to read off the main actor and the Loadout build reads the catalog on a background task.
final class CLICatalogStore: Observable, @unchecked Sendable {
    static let shared = CLICatalogStore()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var stored = CLICatalog.empty

    var catalog: CLICatalog {
        get {
            registrar.access(self, keyPath: \.catalog)
            return lock.withLock { stored }
        }
        set {
            registrar.withMutation(of: self, keyPath: \.catalog) { lock.withLock { stored = newValue } }
        }
    }
}
