import Foundation
import Testing
@testable import SpaceVibe

/// Settings (spec `docs/specs/2026-11-04-reins-settings.md`): the stored Theme and Font size, the type scale, and the
/// Update wording. No test changes `TypeScale.shared`, which every other suite reads in parallel.
@MainActor
@Suite("Settings", .fixtureCLIs)
struct SettingsTests {
    /// A fresh suite and its name; each test removes it with `defer`. The name is an absolute path, so the suite's plist
    /// lives in the temporary folder: a plain name leaves a file in `~/Library/Preferences` even after the removal.
    private func throwawayDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("spacevibe-tests-\(UUID().uuidString)").path
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Theme and Font size are remembered; Dark and Default when nothing is saved")
    func remembers() {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppearanceStore(defaults: defaults)
        #expect(first.theme == .dark && first.fontSize == .standard)
        first.theme = .system
        first.fontSize = .large
        let second = AppearanceStore(defaults: defaults)
        #expect(second.theme == .system && second.fontSize == .large)
        // The value saved before System existed still reads.
        defaults.set("light", forKey: AppearanceStore.defaultsKey)
        #expect(AppearanceStore(defaults: defaults).theme == .light)
    }

    @Test("a forced store (screenshots) saves nothing")
    func forcedSavesNothing() {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let shot = AppearanceStore(defaults: defaults, forced: .light)
        shot.theme = .dark
        shot.fontSize = .large
        #expect(defaults.string(forKey: AppearanceStore.defaultsKey) == nil)
        #expect(defaults.string(forKey: AppearanceStore.fontSizeKey) == nil)
    }

    @Test("the toggle sets the other appearance, fixed, which leaves System")
    func toggleLeavesSystem() {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppearanceStore(defaults: defaults)
        store.theme = .system
        let showing = store.choice
        store.toggle()
        #expect(store.theme == ThemeSetting(showing.toggled))
        store.toggle()
        #expect(store.theme == ThemeSetting(showing))
    }

    @Test("a step moves the 12, 14 and 16 roles by 1 pt and leaves figure and display", arguments: FontSizeChoice.allCases)
    func typeScale(choice: FontSizeChoice) {
        for base: CGFloat in [12, 14, 16] {
            let role = SpaceVibeType.role(size: base, step: choice.step, weight: .regular, lineBox: 20)
            #expect(role.size == base + choice.step)
            #expect(role.lineBox == 20)
        }
        #expect(SpaceVibeType.role(size: 72, scales: false, step: choice.step, weight: .semibold, lineBox: 88).size == 72)
    }

    @Test("a measured text width grows at Large and never shrinks at Small")
    func widths() {
        let scale = TypeScale()
        #expect(scale.width(52, at: 14) == 52)
        scale.step = FontSizeChoice.large.step
        #expect(scale.width(52, at: 14) == 56)
        #expect(scale.width(128, at: 12) == 139)
        scale.step = FontSizeChoice.small.step
        #expect(scale.width(52, at: 14) == 52)
    }

    @Test("each Update state has its tag", arguments: [
        (UpdateController.Status.notChecked, nil as String?),
        (.checking, "Checking\u{2026}"),
        (.upToDate, "Up to date"),
        (.available(version: "0.2.0"), "SpaceVibe 0.2.0 is available"),
        (.failed, "Check failed"),
        (.unavailable("No feed."), nil),
    ])
    func tags(status: UpdateController.Status, text: String?) {
        #expect(SettingsWording.tag(status)?.text == text)
    }

    @Test("the last check reads today, yesterday or a date; a failure says what failed; nothing while checking or unavailable")
    func lastCheck() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15, minute: 30)))
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9, minute: 14)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 22, minute: 5)))
        let older = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 8, minute: 0)))
        func line(_ date: Date?, _ status: UpdateController.Status = .upToDate) -> String? {
            SettingsWording.lastCheck(status, at: date, now: now, calendar: calendar)
        }
        // The formatter writes local time; only the day words and the shape are pinned here.
        #expect(line(earlier)?.hasPrefix("Checked today at ") == true)
        #expect(line(yesterday)?.hasPrefix("Checked yesterday at ") == true)
        #expect(line(older)?.hasPrefix("Checked Oct 29 at ") == true)
        #expect(line(nil, .notChecked) == "Not checked yet")
        #expect(line(earlier, .checking) == nil)
        #expect(line(earlier, .unavailable("No feed.")) == nil)
        #expect(line(earlier, .failed) == "Could not read the update source.")
    }

    @Test("the app name carries the version when the bundle has one")
    func appName() {
        #expect(SettingsWording.appName(version: "0.1.0") == "SpaceVibe 0.1.0")
        #expect(SettingsWording.appName(version: nil) == "SpaceVibe")
    }

    // MARK: CLIs (MC-R4, MC9)

    /// A core that answers `clis.list` with `list` and refuses everything else.
    private final class ListingCore: UnservedCore, @unchecked Sendable {
        let list: [CoreCLIInfo]
        init(_ list: [CoreCLIInfo]) { self.list = list }
        override func clisList() async throws -> CoreCLIsList { CoreCLIsList(clis: list) }
    }

    @Test("every CLI is on until turned off, including one listed for the first time; the choice is saved and read back")
    func cliPreferences() {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CLIPreferences(defaults: defaults)
        #expect(first.disabled.isEmpty && first.isOn(.claude) && first.isOn(CLIID("a-cli-never-seen")))
        first.set(.codex, on: false)
        #expect(!first.isOn(.codex) && defaults.stringArray(forKey: CLIPreferences.disabledKey) == ["codex"])
        let second = CLIPreferences(defaults: defaults)
        #expect(!second.isOn(.codex) && second.isOn(.claude))
        second.set(.codex, on: true)
        #expect(CLIPreferences(defaults: defaults).isOn(.codex) && defaults.stringArray(forKey: CLIPreferences.disabledKey) == [])
        // A hand edit that is not a list reads as every CLI on.
        defaults.set("codex", forKey: CLIPreferences.disabledKey)
        #expect(CLIPreferences(defaults: defaults).disabled.isEmpty)
    }

    @Test("the CLIs group lists every CLI of clis.list in order; turning one off hides it from the catalog every page reads")
    func cliGroupAndFilter() async throws {
        let (defaults, suite) = throwawayDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let newCLI = CLICatalogTests.twin("newcli", label: "New CLI")
        let env = AppEnvironment(catalogStore: CLICatalogStore(), cliPreferences: CLIPreferences(defaults: defaults),
                                 makeCoreClient: { ListingCore(CLICatalogFixture.list + [newCLI]) })
        #expect(env.catalog.all.isEmpty, "nothing before clis.list lands")
        #expect(await env.loadCLIs())
        #expect(env.catalog.all.map(\.id) == [.claude, .codex, .gemini, CLIID("newcli")])
        #expect(env.catalog.all.map(\.installed) == [true, true, false, true])
        #expect(env.catalog.all.allSatisfy { env.catalog.isEnabled($0.id) }, "a newly listed CLI is on")
        #expect(SettingsWording.cliSpoken("Gemini CLI", installed: false) == "Gemini CLI, not installed")
        #expect(SettingsWording.cliSpoken("Codex", installed: true) == "Codex")

        env.setCLI(.codex, on: false)
        #expect(!env.catalog.isEnabled(.codex) && env.catalog.info(for: .codex) == nil)
        #expect(env.catalog.inventoryCLIs == [.claude, CLIID("newcli")])
        #expect(env.catalog.all.count == 4, "Settings still lists it, to turn it back on")
        #expect(defaults.stringArray(forKey: CLIPreferences.disabledKey) == ["codex"])
        let rows = SkillRowsFixture.snapshot([("both", SkillRowsFixture.counted(1), SkillRowsFixture.counted(2), "user", nil)])
        #expect(env.catalog.shown(rows).items.map(\.cli) == [.claude])
        env.setCLI(.codex, on: true)
        #expect(env.catalog.inventoryCLIs == [.claude, .codex, CLIID("newcli")])
    }

    @Test("a failed clis.list keeps the last list and says why")
    func cliListFailure() async {
        let env = AppEnvironment(catalogStore: CLICatalogStore(), cliPreferences: CLIPreferences(defaults: throwawayDefaults().defaults), makeCoreClient: { UnservedCore() })
        #expect(await env.loadCLIs() == false)
        #expect(env.cliList == nil && env.cliListFailure == "not served by this fake")
    }
}
