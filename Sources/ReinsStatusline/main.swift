import Foundation
import ReinsCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Claude starts this helper. The GUI never launches a recorded command or a hook.
func report(_ message: String) { try? FileHandle.standardError.write(contentsOf: Data("Reins: \(message)\n".utf8)) }

/// Inherit Claude's process group: cancelling the status-line group also cancels the delegate.
/// Foundation Process starts a separate group on macOS, which would leave the original command running.
func delegate(_ command: String, pipe: Pipe) throws -> pid_t {
    var actions: posix_spawn_file_actions_t?
    var attributes: posix_spawnattr_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawnattr_init(&attributes)
    defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
    posix_spawn_file_actions_adddup2(&actions, pipe.fileHandleForReading.fileDescriptor, STDIN_FILENO)
    posix_spawn_file_actions_addclose(&actions, pipe.fileHandleForReading.fileDescriptor)
    posix_spawn_file_actions_addclose(&actions, pipe.fileHandleForWriting.fileDescriptor)
    var defaults = sigset_t()
    sigemptyset(&defaults)
    sigaddset(&defaults, SIGPIPE)
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF))
    let strings: [String] = ["sh", "-c", command]
    let args = strings.map { $0.withCString { strdup($0) } }
    let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)".withCString { strdup($0) } }
    defer { (args + environment).forEach { free($0) } }
    var argv = args + [nil]
    var envp = environment + [nil]
    var child: pid_t = 0
    let result = posix_spawn(&child, "/bin/sh", &actions, &attributes, &argv, &envp)
    guard result == 0 else { throw ReinsError("Original status line could not start.", status: 500) }
    return child
}

func capture(_ arguments: [String]) throws -> Int32 {
    guard arguments.count == 4 else { throw ReinsError("Invalid capture arguments.", status: 400) }
    signal(SIGPIPE, SIG_IGN)
    let original = arguments[3]
    let pipe = Pipe()
    var child: pid_t = 0
    if !original.isEmpty {
        do { child = try delegate(original, pipe: pipe) } catch { report("Original status line could not start.") }
    }
    try? pipe.fileHandleForReading.close()
    var input = Data()
    var oversized = false
    var canWrite = child > 0
    while let chunk = try FileHandle.standardInput.read(upToCount: 64 * 1024), !chunk.isEmpty {
        if canWrite {
            do { try pipe.fileHandleForWriting.write(contentsOf: chunk) } catch { canWrite = false }
        }
        if !oversized, input.count + chunk.count <= LimitsClaudeStatusline.maxInputBytes { input.append(chunk) }
        else { oversized = true; input.removeAll(keepingCapacity: false) }
    }
    try? pipe.fileHandleForWriting.close()
    do {
        if oversized { throw ReinsError("Status line input exceeded its size limit.", status: 400) }
        var environment = ProcessInfo.processInfo.environment
        environment[ReinsCore.env("HOME")] = arguments[1]
        let roots = try Roots.resolve(env: environment)
        guard roots.claude.root.standardizedFileURL.path == URL(fileURLWithPath: arguments[2]).standardizedFileURL.path else {
            throw ReinsError("Claude config folder changed; capture skipped.", status: 409)
        }
        try LimitsClaudeStatusline.capture(input, roots: roots)
    } catch { report("Quota capture failed; the original status line is unchanged.") }
    if child > 0 {
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 { if errno != EINTR { return 1 } }
        return status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    }
    return original.isEmpty ? 0 : 1
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    switch arguments.first {
    case "--capture": exit(try capture(arguments))
    case "--install" where arguments.count == 1:
        let roots = try Roots.resolve()
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        if let entry = try StatuslineSetup.install(roots, binary: binary) {
            print("Claude limit capture enabled. Undo settings with:")
            print("\(StatuslineSetup.quote(StatuslineSetup.executable(roots).path)) --undo \(StatuslineSetup.quote(entry.id))")
        } else { print("Claude limit capture is already enabled.") }
    case "--undo" where arguments.count == 2:
        _ = try Journal.undo(Roots.resolve(), id: arguments[1])
        print("Settings restored. The inactive collector binary was kept.")
    default:
        report("Usage: ReinsStatusline --install | --undo <journal-id>")
        exit(2)
    }
} catch {
    report((error as? ReinsError)?.message ?? "The operation failed; no input or error payload is logged.")
    exit(1)
}
