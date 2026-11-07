import Foundation

// Skills and agents: add from a form, remove, copy between the CLIs.
extension Mutate {
    /// Writes `<skills>/<name>/SKILL.md` in each CLI. Refuses a name that exists in any of them before writing anything.
    public static func addSkill(
        roots: Roots,
        clis: [InventoryCLI],
        name: String,
        description: String,
        body: String = ""
    ) throws -> JournalEntry {
        try WriteLock.run(roots) { try addSkillLocked(roots: roots, clis: clis, name: name, description: description, body: body) }
    }

    private static func addSkillLocked(
        roots: Roots, clis: [InventoryCLI], name: String, description: String, body: String
    ) throws -> JournalEntry {
        try Journal.prepareMutation(roots)
        try validName(name)
        try need(!ActivityText.trim(description).isEmpty, "Say when the agent should use this skill.")
        try requireCLIs(clis)
        let text = MutateText.skillText(name: name, description: description, body: body)
        let ops = try createAll(roots, clis: clis) { cli in
            let dir = path(cliRoots(roots, cli).skills, name)
            try need(!Trash.pathExists(dir), "\(label(cli)) already has a skill named \(name).", 409)
            return (dir, { try makeFolder(dir); try createFile(path(dir, "SKILL.md"), text: text) })
        }
        return try Journal.recordMutation(roots, label: "Added skill \(name) to \(labels(clis))", ops: ops)
    }

    /// Writes `<agents>/<name>.md` (Claude Code) or `<name>.toml` (Codex) in each CLI.
    public static func addAgent(
        roots: Roots,
        clis: [InventoryCLI],
        name: String,
        description: String,
        instructions: String = ""
    ) throws -> JournalEntry {
        try WriteLock.run(roots) { try addAgentLocked(roots: roots, clis: clis, name: name, description: description, instructions: instructions) }
    }

    private static func addAgentLocked(
        roots: Roots, clis: [InventoryCLI], name: String, description: String, instructions: String
    ) throws -> JournalEntry {
        try Journal.prepareMutation(roots)
        try validName(name)
        try need(!ActivityText.trim(description).isEmpty, "Say when this agent should be used.")
        try requireCLIs(clis)
        let ops = try createAll(roots, clis: clis) { cli in
            try writeAgentPlan(roots, cli: cli, name: name, description: description, instructions: instructions)
        }
        return try Journal.recordMutation(roots, label: "Added agent \(name) to \(labels(clis))", ops: ops)
    }

    static func removeFile(roots: Roots, item: InventoryItem) throws -> JournalEntry {
        try Journal.prepareMutation(roots)
        let cli = cliRoots(roots, item.cli)
        let base = item.kind == .skill ? cli.skills : cli.agents
        try need(
            InventoryFileIO.normalize(item.path).hasPrefix(InventoryFileIO.normalize(base.path) + "/"),
            "Refusing a path outside the CLI folder.", 403
        )
        // The check above is lexical. The item's parent must also be the CLI folder itself once links are followed, so a
        // link in the middle of the path cannot send the removal to some other folder. The CLI folder may be a link
        // (a dotfiles setup); the item itself may be one too, which is why only its parent is resolved.
        try need(
            Roots.resolvedPath((InventoryFileIO.normalize(item.path) as NSString).deletingLastPathComponent) == Roots.resolvedPath(base.path),
            "Refusing a path outside the CLI folder.", 403
        )
        let op = try Trash.remove(roots, path: item.path)
        return try Journal.recordMutation(roots, label: "Removed \(item.kind.rawValue) \(item.name) from \(label(item.cli))", ops: [op])
    }

    static func copyItem(roots: Roots, item: InventoryItem) throws -> JournalEntry {
        let target = item.cli.other
        let name = Inventory.bare(item.name)
        try Journal.prepareMutation(roots)
        try validName(name)
        if item.kind == .skill {
            let dir = path(cliRoots(roots, target).skills, name)
            try need(!Trash.pathExists(dir), "\(label(target)) already has a skill named \(name).", 409)
            let source = InventoryFileIO.realPath(item.path)
            let ops = try createAll(roots, clis: [target]) { _ in (dir, { try copyFolder(from: source, to: dir) }) }
            return try Journal.recordMutation(roots, label: "Copied skill \(name) to \(label(target))", ops: ops)
        }
        guard let data = FileManager.default.contents(atPath: item.path) else {
            throw ReinsError("Could not read \(item.path). Nothing was changed.", status: 409)
        }
        let fields = MutateText.agentFields(isTOML: item.path.hasSuffix(".toml"), text: String(decoding: data, as: UTF8.self))
        let ops = try createAll(roots, clis: [target]) { cli in
            try writeAgentPlan(roots, cli: cli, name: name, description: fields.description, instructions: fields.instructions)
        }
        return try Journal.recordMutation(roots, label: "Copied agent \(name) to \(label(target))", ops: ops)
    }

    // MARK: Creating

    /// Where a new agent goes and how it is written. Throws 409 when the file exists.
    private static func writeAgentPlan(
        _ roots: Roots, cli: InventoryCLI, name: String, description: String, instructions: String
    ) throws -> (String, () throws -> Void) {
        let file = path(cliRoots(roots, cli).agents, "\(name).\(cli == .claude ? "md" : "toml")")
        try need(!Trash.pathExists(file), "\(label(cli)) already has an agent named \(name).", 409)
        let text = MutateText.agentText(cli: cli, name: name, description: description, instructions: instructions)
        return (file, { try createFile(file, text: text) })
    }

    /// For each CLI: `plan` checks that the new path is free and returns it with the write to run. Every check runs
    /// before the first write, and a failed write sends what was created to the trash, so nothing is left unrecorded.
    private static func createAll(
        _ roots: Roots, clis: [InventoryCLI], plan: (InventoryCLI) throws -> (path: String, write: () throws -> Void)
    ) throws -> [JournalOp] {
        let plans = try clis.map { try plan($0) }
        var ops: [JournalOp] = []
        do {
            for item in plans {
                ops.append(.created(path: item.path))
                try item.write()
            }
        } catch {
            try Journal.rollbackMutation(roots, ops: ops)
            throw error
        }
        return ops
    }

    // MARK: Files

    static func path(_ base: URL, _ name: String) -> String { path(base.path, name) }
    static func path(_ base: String, _ name: String) -> String { (base as NSString).appendingPathComponent(name) }

    private static func makeFolder(_ path: String) throws {
        do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) } catch {
            throw ReinsError("Could not create \(path).", status: 500)
        }
    }

    /// Creates a new file and fails if the path exists (O_EXCL), with the permissions a plain write gets.
    private static func createFile(_ path: String, text: String) throws {
        try makeFolder((path as NSString).deletingLastPathComponent)
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
        guard fd >= 0 else {
            throw ReinsError(errno == EEXIST ? "\(path) already exists." : "Could not write \(path).", status: errno == EEXIST ? 409 : 500)
        }
        defer { close(fd) }
        var failed = false
        Array(text.utf8).withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    failed = true
                    return
                }
                offset += n
            }
        }
        if failed { throw ReinsError("Could not write \(path).", status: 500) }
    }

    /// Copies a skill folder. A link inside it is copied as a link (never followed) and `.git` is left out.
    private static func copyFolder(from source: String, to destination: String) throws {
        let fm = FileManager.default
        var info = stat()
        guard lstat(source, &info) == 0 else { throw ReinsError("Could not read \(source). Nothing was changed.", status: 409) }
        do {
            switch info.st_mode & S_IFMT {
            case S_IFLNK:
                try fm.createSymbolicLink(atPath: destination, withDestinationPath: try fm.destinationOfSymbolicLink(atPath: source))
            case S_IFDIR:
                try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
                for name in try fm.contentsOfDirectory(atPath: source).sorted() where name != ".git" {
                    try copyFolder(from: path(source, name), to: path(destination, name))
                }
            default:
                try fm.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.copyItem(atPath: source, toPath: destination)
                // A copy is a new item: keep the source's content but not its age, so the new cell reads "not counted yet".
                try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: destination)
            }
        } catch let error as ReinsError {
            throw error
        } catch {
            throw ReinsError("Could not copy \(source) (\((error as NSError).localizedFailureReason ?? "the copy failed")).", status: 500)
        }
    }
}
