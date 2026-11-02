import Foundation

/// One process-wide, re-entrant lock around every write Reins makes to config, the journal and the app trash.
///
/// The Node core was single-threaded, so a write never overlapped another. The app runs each write and each Undo on its
/// own thread; without this lock two of them read the same journal or settings file and the second write drops the first.
/// The lock lives in the engine, not in a screen, so every caller is covered. It is re-entrant because one operation
/// (`Mutate.addHook`) calls `FileEdit`, which calls `Journal`, inside one critical section.
///
/// It guards threads of this process only. Another process (a CLI, a hand edit) is caught by the re-check
/// `FileEdit.apply` makes just before the rename, which refuses with a 409 when the file changed since it was read.
enum WriteLock {
    private static let lock = NSRecursiveLock()

    static func run<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
