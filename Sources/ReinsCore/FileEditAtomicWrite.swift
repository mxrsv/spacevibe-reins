import Foundation

/// Writes bytes next to the target and renames over it, so a reader never sees half a file. Mirrors `atomicWrite` in
/// core/mutate.mjs. `validate` gets the bytes read back from the temp file; throwing aborts before the rename and the
/// temp file is removed, so the target is untouched.
enum AtomicWrite {
    /// - Parameter path: a real path (symlinks already resolved by the caller), so the target is written and a link to it stays a link.
    /// - Parameter beforeRename: runs right before the rename, after `validate`; throwing aborts and removes the temp
    ///   file. `FileEdit` uses it to refuse (409) when the target changed since it was read.
    ///
    /// The temp name is unique per call (pid and a random suffix), so two writers next to the same target never share
    /// or steal a temp file.
    static func write(
        to path: String, data: Data, mode: Int, validate: ((Data) throws -> Void)? = nil, beforeRename: (() throws -> Void)? = nil
    ) throws {
        let temp = "\(path).reins-\(getpid())-\(UUID().uuidString.lowercased().prefix(8)).tmp"
        do {
            try create(temp, data: data, mode: mode)
            if let validate {
                guard let written = FileManager.default.contents(atPath: temp) else {
                    throw ReinsError("Could not read back \(temp) to check it.", status: 500)
                }
                try validate(written)
            }
            try beforeRename?()
            guard rename(temp, path) == 0 else {
                throw ReinsError("Could not replace \(path) (\(errnoText())). Nothing was changed.", status: 500)
            }
        } catch {
            unlink(temp)
            throw error
        }
    }

    private static func create(_ temp: String, data: Data, mode: Int) throws {
        // O_EXCL: never write through a link or into a file somebody else made at that name.
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL, mode_t(mode))
        guard fd >= 0 else { throw ReinsError("Could not write next to \(temp) (\(errnoText())). Nothing was changed.", status: 500) }
        var failed = false
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Foundation.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    failed = true
                    return
                }
                offset += n
            }
        }
        // The umask may have trimmed the mode at creation; set it exactly.
        if !failed, fchmod(fd, mode_t(mode)) != 0 { failed = true }
        if !failed, fsync(fd) != 0 { failed = true }
        let reason = errnoText()
        close(fd)
        if failed { throw ReinsError("Could not write \(temp) (\(reason)). Nothing was changed.", status: 500) }
    }

    static func errnoText() -> String { String(cString: strerror(errno)) }
}
