import Foundation

/// Every Loadout write: add, remove and copy skills, agents and hooks. Port of the item half of Node mutate (git b58269d).
///
/// Each call records one journal entry so `Journal.undo` can reverse it. Removed files go to the app trash, never away
/// for good; a removed link keeps its target text. Items are found again by `Inventory.read`, so an id that no longer
/// exists is a 404. Nothing here runs a hook or a command: hook commands are only copied as text.
///
/// The functions live in `Mutate*.swift`: `MutateItems` (skills, agents, remove, copy), `MutateHooks` (hooks and their
/// undo), `MutateHookEdit` (the pure JSON edits) and `MutateText` (text formats shared with the Node core).
public enum Mutate {
    /// Removes a skill, an agent or a hook. Plugin-owned and project-scoped items are read-only (403).
    public static func removeItem(roots: Roots, id: String) throws -> JournalEntry {
        try WriteLock.run { try removeItemLocked(roots: roots, id: id) }
    }

    private static func removeItemLocked(roots: Roots, id: String) throws -> JournalEntry {
        switch try find(roots, id: id) {
        case .item(let item):
            try requireRemovable(removable: item.removable, scope: item.scope)
            return try removeFile(roots: roots, item: item)
        case .hook(let hook):
            try requireRemovable(removable: hook.removable, scope: hook.scope)
            return try removeHook(roots: roots, hook: hook)
        }
    }

    /// Copies a skill, an agent or a hook to the other CLI. A plugin or project item may be copied; only removal is refused.
    /// A hook is copied into Claude Code when it knows the event, never into Codex: Codex loading a hook Reins wrote is
    /// unverified (spec, "To verify"), and the approved Loadout mock offers no such copy. The Node core throws a
    /// TypeError for every hook copy (it reads `name.split` before its hook branch), so there is nothing to mirror.
    public static func copyToOther(roots: Roots, id: String) throws -> JournalEntry {
        try WriteLock.run { try copyToOtherLocked(roots: roots, id: id) }
    }

    private static func copyToOtherLocked(roots: Roots, id: String) throws -> JournalEntry {
        switch try find(roots, id: id) {
        case .hook(let hook):
            let target = hook.cli.other
            try need(target == .claude, "Reins does not copy hooks into Codex.")
            try need(events(target).contains(hook.event), "\(label(target)) has no \(hook.event) event.")
            return try addHook(roots: roots, clis: [target], event: hook.event, matcher: hook.matcher, command: hook.command, timeout: hook.timeout)
        case .item(let item):
            return try copyItem(roots: roots, item: item)
        }
    }

    // MARK: Shared

    static let nameLimit = 64
    static let cliLabels: [InventoryCLI: String] = [.claude: "Claude Code", .codex: "Codex"]

    static func label(_ cli: InventoryCLI) -> String { cliLabels[cli] ?? cli.rawValue }

    static func labels(_ clis: [InventoryCLI]) -> String { clis.map(label).joined(separator: " and ") }

    static func events(_ cli: InventoryCLI) -> [String] { Inventory.events[cli.rawValue] ?? [] }

    static func cliRoots(_ roots: Roots, _ cli: InventoryCLI) -> CLIRoots { cli == .claude ? roots.claude : roots.codex }

    static func need(_ condition: Bool, _ message: String, _ status: Int = 400) throws {
        if !condition { throw ReinsError(message, status: status) }
    }

    /// `NAME_RE` of the Node core: `^[a-z0-9][a-z0-9-]{0,63}$`.
    static func validName(_ name: String) throws {
        let scalars = Array(name.unicodeScalars)
        func lowerOrDigit(_ s: Unicode.Scalar) -> Bool { ("a"..."z").contains(s) || ("0"..."9").contains(s) }
        let valid = (1...nameLimit).contains(scalars.count)
            && lowerOrDigit(scalars[0])
            && scalars.dropFirst().allSatisfy { lowerOrDigit($0) || $0 == "-" }
        try need(valid, "Use lowercase letters, numbers and dashes for the name.")
    }

    static func requireCLIs(_ clis: [InventoryCLI]) throws {
        try need(!clis.isEmpty, "Pick at least one CLI.")
    }

    enum Found {
        case item(InventoryItem)
        case hook(InventoryHook)
    }

    /// Looks the id up in a fresh inventory read (ids are stable hashes of what the item is).
    static func find(_ roots: Roots, id: String) throws -> Found {
        let snapshot = Inventory.read(roots: roots)
        if let item = snapshot.items.first(where: { $0.id == id }) { return .item(item) }
        if let hook = snapshot.hooks.first(where: { $0.id == id }) { return .hook(hook) }
        throw ReinsError("This item no longer exists. Refresh the list.", status: 404)
    }

    /// The Node core words every refusal as "belongs to a plugin"; a project item gets its own sentence (same 403).
    private static func requireRemovable(removable: Bool, scope: InventoryScope) throws {
        guard !removable else { return }
        if scope == .project {
            throw ReinsError("This one belongs to a project folder, so Reins only shows it. Change it in the project.", status: 403)
        }
        throw ReinsError("This one belongs to a plugin. Remove the plugin instead.", status: 403)
    }
}
