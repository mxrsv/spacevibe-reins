import Darwin
import Testing
@testable import SpaceVibe

/// The host-app walk (GW-R6): nearest regular-app ancestor of a session's pid, or nil when there is none.
@Suite("Host app resolver", .fixtureCLIs)
struct HostAppResolverTests {
    /// An injected process table: `parents` maps a pid to its parent (a missing pid is a failed read), `apps` lists the
    /// pids that are regular apps, `paths` the executable of a pid, `bundleIDs` the bundle id of a bundle path. A regular
    /// app's bundle id is its `apps` value.
    struct FakeTable: HostProcessTable {
        var parents: [pid_t: pid_t]
        var apps: [pid_t: String] = [:]
        var paths: [pid_t: String] = [:]
        var bundleIDs: [String: String] = [:]

        func parent(of pid: pid_t) -> pid_t? { parents[pid] }

        func regularApp(at pid: pid_t) -> HostApp? {
            apps[pid].map { HostApp(pid: pid, bundleIdentifier: $0, name: nil) }
        }

        func executablePath(of pid: pid_t) -> String? { paths[pid] }

        func bundleIdentifier(ofBundleAt bundlePath: String) -> String? { bundleIDs[bundlePath] }

        func regularApp(withBundleIdentifier bundleIdentifier: String) -> HostApp? {
            apps.filter { $0.value == bundleIdentifier }.keys.min().flatMap(regularApp(at:))
        }
    }

    static let terminal = "com.example.terminal"

    @Test("the direct parent is the app")
    func directParent() {
        let table = FakeTable(parents: [500: 400, 400: 1], apps: [400: Self.terminal])
        #expect(HostAppResolver.hostApp(of: 500, in: table)?.pid == 400)
    }

    @Test("a deep chain reaches the terminal app through shell and login")
    func deepChain() {
        // claude (900) → zsh (800) → login (700) → terminal (600) → launchd.
        let table = FakeTable(parents: [900: 800, 800: 700, 700: 600, 600: 1], apps: [600: Self.terminal])
        let app = HostAppResolver.hostApp(of: 900, in: table)
        #expect(app == HostApp(pid: 600, bundleIdentifier: Self.terminal, name: nil))
    }

    @Test("the nearest app wins over an app further up")
    func nearestApp() {
        let table = FakeTable(parents: [900: 800, 800: 700, 700: 1], apps: [800: "com.example.editor", 700: Self.terminal])
        #expect(HostAppResolver.hostApp(of: 900, in: table)?.pid == 800)
    }

    @Test("a tmux-like chain that reaches launchd has no host app")
    func tmuxChain() {
        // claude (900) → zsh (800) → tmux server (700) → launchd (1). The terminal app holds only the tmux client.
        let table = FakeTable(parents: [900: 800, 800: 700, 700: 1, 600: 1], apps: [600: Self.terminal])
        #expect(HostAppResolver.hostApp(of: 900, in: table) == nil)
    }

    @Test("a loop in the parent chain stops the walk")
    func loop() {
        let table = FakeTable(parents: [900: 800, 800: 700, 700: 900])
        #expect(HostAppResolver.hostApp(of: 900, in: table) == nil)
    }

    @Test("a pid that is its own parent stops the walk")
    func selfParent() {
        let table = FakeTable(parents: [900: 900])
        #expect(HostAppResolver.hostApp(of: 900, in: table) == nil)
    }

    @Test("a failed parent read stops the walk")
    func failedRead() {
        // 800's parent cannot be read, so the app at 600 is never reached.
        let table = FakeTable(parents: [900: 800, 700: 600], apps: [600: Self.terminal])
        #expect(HostAppResolver.hostApp(of: 900, in: table) == nil)
    }

    @Test("the walk gives up after the max depth")
    func maxDepth() {
        // A chain 2...(depth + 2) going up, with the app one step past the cap.
        let depth = 5
        let top = pid_t(depth + 2)
        var parents: [pid_t: pid_t] = [:]
        for pid in pid_t(2)..<top { parents[pid] = pid + 1 }
        parents[top] = 1
        let table = FakeTable(parents: parents, apps: [top: Self.terminal])
        // Session at 2: the app at `top` is the (depth + 1)th pid examined.
        #expect(HostAppResolver.hostApp(of: 2, in: table, maxDepth: depth) == nil)
        // One more step allowed reaches it, so the cap is the only thing that stopped the walk.
        #expect(HostAppResolver.hostApp(of: 2, in: table, maxDepth: depth + 1)?.pid == top)
    }

    @Test("the default max depth is a positive constant")
    func defaultDepth() {
        #expect(HostAppResolver.maxDepth > 0)
    }

    @Test("a session pid that is itself a regular app is stale or reused, so there is no host app")
    func sessionIsApp() {
        // A CLI session is never a GUI app: the pid now belongs to another process. Its parent app is not used either.
        let table = FakeTable(parents: [900: 600, 600: 1], apps: [900: Self.terminal, 600: "com.example.editor"])
        #expect(HostAppResolver.hostApp(of: 900, in: table) == nil)
    }

    // MARK: Bundle id of a non-regular ancestor

    static let orca = "com.stablyai.orca"
    static let orcaAgents = "/Users/someone/Library/Application Support/orca/daemon-host/macos/terminal-host-abc/app.noindex/Orca Agents.app"

    @Test("an Orca-like chain maps the helper app to the running regular app with the same bundle id")
    func orcaChain() {
        // claude (900) → zsh (800) → login (700) → Orca Agents (600, LSUIElement, not regular) → launchd. Orca is 400.
        let table = FakeTable(
            parents: [900: 800, 800: 700, 700: 600, 600: 1, 400: 1],
            apps: [400: Self.orca],
            paths: [900: "/usr/local/bin/claude", 800: "/bin/zsh", 700: "/usr/bin/login",
                    600: Self.orcaAgents + "/Contents/MacOS/Orca Agents", 400: "/Applications/Orca.app/Contents/MacOS/Orca"],
            bundleIDs: [Self.orcaAgents: Self.orca, "/Applications/Orca.app": Self.orca]
        )
        #expect(HostAppResolver.hostApp(of: 900, in: table) == HostApp(pid: 400, bundleIdentifier: Self.orca, name: nil))
    }

    @Test("a helper app whose bundle id matches no running regular app keeps walking")
    func unmatchedHelperKeepsWalking() {
        // claude (900) → helper (800, bundle id of no running app) → terminal (600).
        let helper = "/Applications/Other.app"
        let table = FakeTable(
            parents: [900: 800, 800: 600, 600: 1],
            apps: [600: Self.terminal],
            paths: [800: helper + "/Contents/MacOS/Other Helper"],
            bundleIDs: [helper: "com.example.other"]
        )
        #expect(HostAppResolver.hostApp(of: 900, in: table)?.pid == 600)
        // With nothing above it, the walk ends at launchd with no host app.
        let alone = FakeTable(parents: [900: 800, 800: 1], paths: [800: helper + "/Contents/MacOS/Other Helper"],
                              bundleIDs: [helper: "com.example.other"])
        #expect(HostAppResolver.hostApp(of: 900, in: alone) == nil)
    }

    @Test("an executable outside any app bundle keeps walking")
    func pathOutsideBundleKeepsWalking() {
        // The tmux server's path is outside a bundle, so its bundle id is never asked, even if one would match.
        let table = FakeTable(
            parents: [900: 800, 800: 700, 700: 1, 600: 1],
            apps: [600: Self.terminal],
            paths: [800: "/bin/zsh", 700: "/opt/homebrew/bin/tmux"],
            bundleIDs: ["/opt/homebrew/bin/tmux": Self.terminal, "/opt/homebrew": Self.terminal]
        )
        #expect(HostAppResolver.hostApp(of: 900, in: table) == nil)
    }

    @Test("the enclosing bundle is the outermost .app with Contents on the path", arguments: [
        ("/Applications/Orca.app/Contents/MacOS/Orca", "/Applications/Orca.app"),
        ("/Applications/Orca.app/Contents/Frameworks/Orca Helper.app/Contents/MacOS/Orca Helper", "/Applications/Orca.app"),
        (orcaAgents + "/Contents/MacOS/Orca Agents", orcaAgents),
    ])
    func enclosingBundle(path: String, bundle: String) {
        #expect(HostAppResolver.enclosingAppBundle(of: path) == bundle)
    }

    @Test("no enclosing bundle outside one", arguments: [
        "/bin/zsh", "/usr/bin/login", "/opt/homebrew/bin/tmux", "/Users/someone/app.noindex/tool", "/Users/someone/.app/Contents/x",
        "/Users/someone/Thing.app", "relative/Thing.app/Contents/MacOS/Thing", "",
    ])
    func noEnclosingBundle(path: String) {
        #expect(HostAppResolver.enclosingAppBundle(of: path) == nil)
    }

    @Test("pid 1 and below have no host app")
    func launchdAndInvalid() {
        let table = FakeTable(parents: [1: 0, 0: 0], apps: [1: Self.terminal, 0: Self.terminal])
        #expect(HostAppResolver.hostApp(of: 1, in: table) == nil)
        #expect(HostAppResolver.hostApp(of: 0, in: table) == nil)
        #expect(HostAppResolver.hostApp(of: -1, in: table) == nil)
    }

    /// Reads only; activates nothing.
    @Test("the live table reads this process's parent pid")
    func liveParent() {
        let table = LiveHostProcessTable()
        #expect(table.parent(of: getpid()) == getppid())
        #expect(table.parent(of: -1) == nil)
        #expect(table.executablePath(of: getpid())?.hasPrefix("/") == true)
        #expect(table.executablePath(of: -1) == nil)
    }
}
