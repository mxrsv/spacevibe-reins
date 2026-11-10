import SwiftUI

/// Which row is current in a list (V5-R36 `j`/`k`): the one picked while it is still listed, else the first listed.
enum CurrentRow {
    static func resolve(_ picked: String?, in rows: [String]) -> String? {
        picked.flatMap { rows.contains($0) ? $0 : nil } ?? rows.first
    }

    /// One row down (`by: 1`) or up (`by: -1`), stopping at the first and the last.
    static func step(_ picked: String?, by step: Int, in rows: [String]) -> String? {
        guard let current = resolve(picked, in: rows), let index = rows.firstIndex(of: current) else { return nil }
        return rows[min(max(index + step, 0), rows.count - 1)]
    }

    /// Where the key goes when `removed` rows leave the list: `current` while its resolved row stays, else the first row after it
    /// that stays, else the last one before it, else nil. A removal never hands the key to the first row (the most-used one), so
    /// the next `r` does not remove it.
    static func neighbour(of removed: Set<String>, current: String?, in rows: [String]) -> String? {
        guard let resolved = resolve(current, in: rows), removed.contains(resolved), let index = rows.firstIndex(of: resolved) else {
            return current
        }
        return rows[(index + 1)...].first { !removed.contains($0) } ?? rows[..<index].last { !removed.contains($0) }
    }
}

/// A key with no button on screen: the page's plain keys, run while the page is active (the shell disables hidden tabs).
/// A page mounts its keys only while the palette is closed (V5-R36).
struct HiddenKey: View {
    let shortcut: KeyboardShortcut
    let action: () -> Void

    init(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) { EmptyView() }
            .keyboardShortcut(shortcut)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
