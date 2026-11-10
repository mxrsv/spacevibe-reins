import AppKit
import SwiftUI

/// The v5 Rules shots (`SPACEVIBE_UI_V5=1 SPACEVIBE_SHOT_SCREEN=rules`): the real tab on the synthetic home and the states the fixture
/// cannot hold, dark and light. `SPACEVIBE_FIXTURE_CODEX=unrestricted|both` (read by `scripts/fixture-home.mjs`) rewrites the Codex
/// config; those runs write under their own name (`rules-unrestricted-*`, `rules-both-*`) and shoot only what the variant changes.
/// The default run first prints and checks the V5-A20 trace (every count, stance and Codex fact against what the fixture writes), then:
/// - the real home: `rules-page`, `-filtered`, `-detail`, `-detail-menu` (the verdict menu inside the detail), `-menu-filter`, `-toast`
///   (after a real whole-family write of Read, undone and compared byte for byte), `-removed` (a real Remove, undone likewise), `-invalid` (the
///   settings file corrupted for these shots, restored after);
/// - from in-memory rules: `-sample` (a family open in Codex and denied here by a wide rule, a redundant rule, 38 rules), `-sample-menu` (the
///   family's verdict menu), `-sample-detail`, `-sample-toast`, `-healthy`, `-many` (60), `-none`, `-no-codex`, `-codex-profile` (Codex's
///   permissions come from a profile), `-nothing-matches`, `-loading`, `-narrow`, `-short`.
@MainActor
enum RulesTabShots {
    /// What `scripts/fixture-home.mjs` writes into the global `settings.json`, in file order, and the two Codex configs it can write.
    private static let fixture: [(verdict: CoreVerdict, rule: String)] = [
        (.allow, "Read(*)"), (.allow, "Bash(git status:*)"), (.allow, "Bash(git diff:*)"), (.allow, "Bash(pnpm run:*)"), (.allow, "Bash(node:*)"),
        (.allow, "WebFetch(domain:github.com)"), (.ask, "Bash(git push:*)"), (.ask, "Bash(vercel:*)"),
        (.deny, "Bash(rm -rf:*)"), (.deny, "Read(.env*)"), (.deny, "Edit(~/.ssh/**)"),
    ]

    private enum Variant: String {
        case standard, unrestricted, both
        var prefix: String { self == .standard ? "rules" : "rules-\(rawValue)" }
    }

    static func run(into directory: URL) throws {
        let variant = Variant(rawValue: ProcessInfo.processInfo.environment["SPACEVIBE_FIXTURE_CODEX"] ?? "") ?? .standard
        let env = AppEnvironment.shared
        let page = AgentsPage(env: env)
        page.select(.rules)
        page.start()
        Task { await env.limits.readOnce() }
        try ShotHarness.wait("the rules, the inventory and the CLI reading", seconds: ShotHarness.settleSeconds) {
            page.rules.isSettled && page.loadout.isSettled && env.limits.readAt != nil
        }
        let model = page.rules
        let settings = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? "").appendingPathComponent("settings.json")
        let original = try Data(contentsOf: settings)
        try check(model, variant: variant)

        func shoot(_ name: String, _ choice: AppearanceChoice, toasts: ToastCenter? = nil, page shown: AgentsPage? = nil,
                   store: OpenStateStore = OpenStateStore(), size: CGSize? = nil, limits: LimitsModel? = nil, _ configure: () -> Void = {}) throws {
            configure()
            let size = size ?? ShotRenderer.size
            let used = shown ?? page
            let tabs = TabRegistry.makeTabs(isV5: true).map { $0 is AgentsPage ? used : $0 }
            let shell = ShellModel(tabs: tabs, appearance: AppearanceStore(forced: choice), isV5: true)
            let view = ShellView()
                .environment(limits ?? env.limits)
                .spaceVibeRoot(shell: shell, toasts: toasts ?? ToastCenter(announce: false), env: env)
                .environment(\.openStateStore, store)
                .frame(width: size.width, height: size.height)
            try ShotRenderer.write(view, name: "\(variant.prefix)-\(name)", choice: choice, to: directory)
        }
        func reset() {
            model.filter.clear()
            model.currentID = nil
            model.detailID = nil
            model.isFilterOpen = false
            model.verdictMenu = nil
        }

        let family: RuleFamily = variant == .unrestricted ? .edit : .bash
        let detailRule = model.page.rules.first { $0.rule == (variant == .unrestricted ? "Edit(~/.ssh/**)" : "Bash(git push:*)") }
        let detailStore = OpenStateStore()
        detailStore.setOpen(true, page: RulesModel.page, id: family.id)

        for choice in [AppearanceChoice.dark, .light] {
            func snap(_ name: String, toasts: ToastCenter? = nil, page shown: AgentsPage? = nil, store: OpenStateStore = OpenStateStore(), size: CGSize? = nil,
                      limits: LimitsModel? = nil, _ configure: () -> Void = {}) throws {
                try shoot(name, choice, toasts: toasts, page: shown, store: store, size: size, limits: limits, configure)
            }
            reset()
            try snap("page")
            if variant == .both { continue }
            if variant == .unrestricted {
                // The fixture denies Edit by a path rule only, which is no mismatch (C1): the page and the rule's detail. The family menu
                // and its write are shot from the in-memory sample, which holds a wide Edit/Write deny.
                try snap("detail", store: detailStore) { if let detailRule { model.open(detailRule) } }
                reset()
                continue
            }
            try snap("filtered") { model.toggleFilter("ask") }
            reset()
            try snap("detail", store: detailStore) { if let detailRule { model.open(detailRule) } }
            try snap("detail-menu", store: detailStore) { if let detailRule { model.verdictMenu = .rule(detailRule.id) } }
            reset()
            try snap("menu-filter") { model.isFilterOpen = true }
            reset()
        }
        if variant == .both { return }

        if variant == .unrestricted { return }

        // A real change of a whole family on the synthetic home, then Undo, compared byte for byte. Read holds the one wide rule the
        // fixture writes (`Read(*)`) and a path rule (`Read(.env*)`), so the path rule is kept (C1).
        try writeFamily(model, env: env, family: .read, to: .ask, settings: settings, original: original) { choice, toasts in
            try shoot("toast", choice, toasts: toasts, store: detailStore)
        }

        // A real Remove of a rule, then Undo.
        reset()
        guard let removable = model.page.rules.first(where: { $0.rule == "Read(.env*)" }) else { throw ShotHarness.Failure("no Read(.env*) rule") }
        model.removeRule(removable)
        try ShotHarness.wait("the remove's toast") { env.toasts.current?.action != nil }
        try ShotHarness.check(env.toasts.current?.message == RulesTabWording.removed(removable.rule), "the toast says \"\(env.toasts.current?.message ?? "nothing")\"")
        try ShotHarness.wait("the re-read after the remove") { model.isSettled && !model.page.rules.contains { $0.id == removable.id } }
        for choice in [AppearanceChoice.dark, .light] { try shoot("removed", choice, toasts: env.toasts, store: detailStore) }
        env.toasts.runCurrentAction()
        try ShotHarness.wait("Undo and its re-read") {
            env.toasts.current?.message == RulesTabWording.undone && model.isSettled && model.page.rules.contains { $0.id == removable.id }
        }
        try ShotHarness.check(try Data(contentsOf: settings) == original, "Undo put settings.json back byte for byte")
        env.toasts.dismiss()
        reset()

        try inMemory(env: env, page: page, model: model, shoot: shoot)

        // A settings file that does not parse, for these shots only: the core's own sentence, no rules, Retry.
        try Data("{ \"permissions\": ".utf8).write(to: settings)
        model.refresh()
        try ShotHarness.wait("the invalid read") { if case .invalid = model.page.state { model.isSettled } else { false } }
        try ShotHarness.check(model.page.answer.showsRetry && model.page.layout.bands.isEmpty, "an invalid file hides the rules and offers Retry")
        print("trace: invalid file, state \(model.page.state), Answer \"\(model.page.answer.sentence ?? "nil")\" detail \"\(model.page.answer.detail ?? "nil")\"")
        for choice in [AppearanceChoice.dark, .light] { try shoot("invalid", choice) }
        try original.write(to: settings)
        model.retry()
        try ShotHarness.wait("the re-read after restoring the file") { model.page.state == .ready && model.isSettled }
        try ShotHarness.check(try Data(contentsOf: settings) == original, "the settings file is back byte for byte")
        page.loadout.reload()
        try ShotHarness.wait("the inventory after restoring the file") { page.loadout.isSettled }
        reset()
    }

    /// A whole-family write from `model.set` (wide rules only), one toast, shot, then Undo and the bytes compared.
    private static func writeFamily(_ model: RulesModel, env: AppEnvironment, family: RuleFamily, to verdict: CoreVerdict, settings: URL, original: Data,
                               shoot: (AppearanceChoice, ToastCenter) throws -> Void) throws {
        let members = model.page.rules.filter { RuleFamily.of(tool: $0.tool) == family }
        let changing = members.filter { $0.isWide && $0.verdict != verdict }.count
        let kept = members.filter { !$0.isWide && $0.verdict != verdict }
        model.set(family, to: verdict)
        try ShotHarness.wait("the family write's toast") { env.toasts.current?.action != nil }
        let expected = RulesTabWording.familyChanged(family, to: verdict, count: changing, kept: kept.count)
        try ShotHarness.check(env.toasts.current?.message == expected, "the toast says \"\(env.toasts.current?.message ?? "nothing")\", expected \"\(expected)\"")
        try ShotHarness.wait("the re-read after the write") { model.isSettled && model.page.rules.filter { RuleFamily.of(tool: $0.tool) == family && $0.isWide }.allSatisfy { $0.verdict == verdict } }
        for rule in kept {
            try ShotHarness.check(model.page.rules.first { $0.id == rule.id } != nil, "the path rule \(rule.rule) kept its verdict \(rule.verdict.rawValue)")
        }
        print("trace: \(family.title) to \(verdict.rawValue): \(changing) rules changed, one toast, \"\(env.toasts.current?.message ?? "")\"")
        for choice in [AppearanceChoice.dark, .light] { try shoot(choice, env.toasts) }
        env.toasts.runCurrentAction()
        try ShotHarness.wait("Undo and its re-read") { env.toasts.current?.message == RulesTabWording.undone && model.isSettled }
        try ShotHarness.check(try Data(contentsOf: settings) == original, "one Undo put \(changing) wide rules back: settings.json is the same byte for byte")
        env.toasts.dismiss()
    }

    /// The states the synthetic home cannot hold, drawn from in-memory snapshots.
    private static func inMemory(env: AppEnvironment, page real: AgentsPage, model: RulesModel,
                                 shoot: (String, AppearanceChoice, ToastCenter?, AgentsPage?, OpenStateStore, CGSize?, LimitsModel?, () -> Void) throws -> Void) throws {
        func synthetic(_ snapshot: RulesSnapshot?, installed: Bool = true) -> (AgentsPage, LimitsModel?) {
            let models = RulesModel(env: env, snapshot: snapshot)
            let limits = installed ? nil : LimitsModel(env: env, results: [entry(.claude, installed: true), entry(.codex, installed: false)])
            if let limits { models.limitsResults = { limits.results } }
            let page = AgentsPage(env: env, loadout: real.loadout, rules: models)
            page.select(.rules)
            return (page, limits)
        }
        let full = RulesSynthetic.codex(sandbox: "danger-full-access")
        // The sample's Edit deny is a path rule, which is no mismatch (C1): a wide `Write` deny makes Edit/Write the flagged family.
        let flagged = RulesSynthetic.sample + [RulesSynthetic.rule("Write", .deny)]
        let (sample, _) = synthetic(RulesSynthetic.snapshot(flagged, codex: full))
        // Healthy: Codex has full access, so Edit/Write is compared, and no wide rule denies it here (the ssh path rule does not count; nor is anything redundant).
        let (healthy, _) = synthetic(RulesSynthetic.snapshot(RulesSynthetic.healthy, codex: full))
        let (many, _) = synthetic(RulesSynthetic.snapshot(RulesSynthetic.many, codex: full))
        let (none, _) = synthetic(RulesSynthetic.snapshot([]))
        let (loading, _) = synthetic(nil)
        let (noCodex, noCodexLimits) = synthetic(RulesSynthetic.snapshot(RulesSynthetic.sample), installed: false)
        let (profile, _) = synthetic(RulesSynthetic.snapshot(RulesSynthetic.sample, codex: RulesSynthetic.codex(sandbox: nil, model: .profiles, profile: "work")))
        let (allAllowed, _) = synthetic(RulesSynthetic.snapshot(RulesSynthetic.sample.filter { $0.verdict == .allow }))
        let redundant = RedundantRules.of(RulesSynthetic.sample)
        try ShotHarness.check(redundant.map(\.rule.rule) == ["Bash(git push --force:*)"] && sample.rules.page.answer.sentence == "Edit/Write: open in Codex, denied in Claude Code.",
                              "the sample has one redundant rule and one family that disagrees")
        let sshRule = RulesSynthetic.rule("Edit(~/.ssh/**)", .deny)
        let editOpen = OpenStateStore()
        editOpen.setOpen(true, page: RulesModel.page, id: RuleFamily.edit.id)
        let allOpen = OpenStateStore()
        for family in RuleFamily.allCases { allOpen.setOpen(true, page: RulesModel.page, id: family.id) }
        let toast = ToastCenter(announce: false)
        toast.show(RulesTabWording.familyChanged(.edit, to: .allow, count: 1, kept: 1), undo: {})

        for choice in [AppearanceChoice.dark, .light] {
            func snap(_ name: String, toasts: ToastCenter? = nil, page: AgentsPage? = nil, store: OpenStateStore = OpenStateStore(), size: CGSize? = nil,
                      limits: LimitsModel? = nil, _ configure: @escaping () -> Void = {}) throws {
                try shoot(name, choice, toasts, page, store, size, limits, configure)
            }
            sample.rules.verdictMenu = nil
            sample.rules.detailID = nil
            try snap("sample", page: sample)
            try snap("sample-all-open", page: sample, store: allOpen)
            try snap("sample-menu", page: sample) { sample.rules.verdictMenu = .family(.edit) }
            sample.rules.verdictMenu = nil
            try snap("sample-detail", page: sample, store: editOpen) { sample.rules.open(sshRule) }
            sample.rules.detailID = nil
            try snap("sample-toast", toasts: toast, page: sample)
            try snap("healthy", page: healthy)
            try snap("many", page: many)
            try snap("none", page: none)
            try snap("no-codex", page: noCodex, limits: noCodexLimits)
            try snap("codex-profile", page: profile)
            try snap("nothing-matches", page: allAllowed) { allAllowed.rules.filter.toggle(.verdict, "deny") }
            allAllowed.rules.filter.clear()
            try snap("loading", page: loading)
            // V5-A22: a window below 700 pt of canvas (the halves stack), and one shorter than the cards.
            try snap("narrow", page: sample, size: CGSize(width: 960, height: 600))
            try snap("short", page: sample, size: CGSize(width: 1062, height: 685))
            try snap("many-short", page: many, size: CGSize(width: 1062, height: 685))
        }
    }

    private static func entry(_ cli: CoreCLI, installed: Bool) -> CoreLimitsEntry {
        CoreLimitsEntry(cli: CoreLimitsCLI(cli), state: installed ? .measured : .notInstalled, plan: nil, source: nil,
                        at: installed ? Date().timeIntervalSince1970 : nil, windows: [])
    }

    // MARK: The V5-A20 trace

    /// Per rule and per band: what `scripts/fixture-home.mjs` writes, the row the page shows, then the Answer, the Codex facts and the
    /// count. They must agree.
    private static func check(_ model: RulesModel, variant: Variant) throws {
        let page = model.page
        let sandbox = variant == .unrestricted ? "danger-full-access" : "workspace-write"
        try ShotHarness.check(page.state == .ready, "the page is ready (state \(page.state))")
        for entry in fixture {
            guard let rule = page.rules.first(where: { $0.rule == entry.rule }) else { throw ShotHarness.Failure("no row for \(entry.rule)") }
            print("trace: \(entry.rule): fixture \(entry.verdict.rawValue), row \(rule.verdict.rawValue), family \(RuleFamily.of(tool: rule.tool).title), cell \"\(RulesWording.title(rule.verdict))\"")
            try ShotHarness.check(rule.verdict == entry.verdict, "\(entry.rule) is \(entry.verdict.rawValue)")
        }
        try ShotHarness.check(page.rules.count == fixture.count && model.badge == fixture.count, "the tab's count (\(model.badge ?? -1)) is the rows listed (\(page.rules.count)) is the rules written (\(fixture.count))")
        let bands = page.layout.bands.map { "\($0.family.title) \($0.rules.count) [\($0.stance.summary)] codex \($0.fact?.text ?? "empty")" }
        print("trace: bands \(bands.joined(separator: " | "))")
        for band in page.layout.bands {
            let written = fixture.filter { RuleFamily.of(tool: RulesSynthetic.rule($0.rule, $0.verdict).tool) == band.family }
            try ShotHarness.check(band.rules.count == written.count, "\(band.family.title) lists \(written.count) rules")
            guard variant != .both else { continue }
            try ShotHarness.check(band.fact?.text == (band.family == .bash || band.family == .edit ? "Sandbox: \(sandbox)" : nil), "\(band.family.title)'s Codex cell reads the config's sandbox_mode (\(sandbox))")
        }
        print("trace: Answer \"\(page.answer.sentence ?? "nil")\", family \(page.answer.family?.family.title ?? "none"), Codex note \"\(page.reading.note ?? "none")\"")
        switch variant {
        case .standard:
            try ShotHarness.check(page.answer.sentence == "Codex's sandbox is workspace-write, so it opens or closes no tool outright." && !page.layout.hasComparison && page.layout.redundant.isEmpty,
                                  "the default fixture's workspace sandbox is neither open nor off for any family, so nothing is compared")
            try ShotHarness.check(page.reading.note == "Codex is read only here. Approval policy on-request, from ~/.codex/config.toml.", "the note reads approval_policy")
        case .unrestricted:
            try ShotHarness.check(page.answer.sentence == "No tool is open in one CLI and denied in the other." && page.layout.hasComparison,
                                  "Edit(~/.ssh/**) is a path rule: Edit/Write is compared with Codex's full access and is no mismatch (C1)")
            try ShotHarness.check(page.layout.mismatches.isEmpty && page.layout.bands.allSatisfy { !$0.holdsProblem }, "no family is flagged")
            try ShotHarness.check(page.reading.note == "Codex is read only here. Approval policy never, from ~/.codex/config.toml.", "the note reads approval_policy never")
        case .both:
            try ShotHarness.check(page.answer.sentence == "Nothing to compare: Codex has two permission models set.", "two models: nothing is compared")
            try ShotHarness.check(page.layout.bands.allSatisfy { $0.fact == nil }, "two models: no Codex cell")
        }
    }
}
