import Foundation

/// One process-wide, re-entrant lock around every write Reins makes to config, the journal and the app trash, plus an
/// exclusive `flock` on `<data>/write.lock` so another Reins process (the Go core) is excluded too (plan X-lock).
///
/// The Node core was single-threaded, so a write never overlapped another. The app runs each write and each Undo on its
/// own thread; without this lock two of them read the same journal or settings file and the second write drops the first.
/// The lock lives in the engine, not in a screen, so every caller is covered. It is re-entrant because one operation
/// (`Mutate.addHook`) calls `FileEdit`, which calls `Journal`, inside one critical section.
///
/// Only the outermost depth takes the `flock`; a nested depth runs under the lock already held. It is the same file, mode
/// 0600 in a 0700 folder, and the same call (`flock(LOCK_EX)`) as Go's `fsx.WithWriteLock` (core/internal/fsx/write-lock.go). If the lock cannot be taken the body does not run (fail closed).
///
/// A tool that bypasses both lockers (a hand edit) is caught by the re-check `FileEdit.apply` makes just before the
/// rename, which refuses with a 409 when the file changed since it was read.
enum WriteLock {
    static let fileName = "write.lock"
    static let lockFailedMessage = "Could not lock the Reins data folder, so nothing was changed."

    private static let lock = NSRecursiveLock()
    /// Both are touched only by the thread that holds `lock`.
    private static var depth = 0
    private static var descriptor: Int32 = -1

    static func run<T>(_ roots: Roots, _ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        if depth == 0 { descriptor = try acquire(roots.data) }
        depth += 1
        defer {
            depth -= 1
            if depth == 0 { release() }
        }
        return try body()
    }

    private static func acquire(_ folder: URL) throws -> Int32 {
        let failure = ReinsError(lockFailedMessage, status: 500)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw failure
        }
        let fd = open(folder.appendingPathComponent(fileName).path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure }
        while flock(fd, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            close(fd)
            throw failure
        }
        return fd
    }

    /// Closing the descriptor drops the lock; the explicit unlock keeps the order plain.
    private static func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
