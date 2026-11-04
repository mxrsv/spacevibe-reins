import Foundation
import Testing
@testable import Reins

/// Settings (spec `docs/specs/2026-11-04-reins-settings.md`): the stored Theme and Font size, the type scale, and the
/// Update wording. No test changes `TypeScale.shared`, which every other suite reads in parallel.
@MainActor
@Suite("Settings")
struct SettingsTests {
    private func throwawayDefaults() -> UserDefaults {
        UserDefaults(suiteName: "reins-tests-\(UUID().uuidString)")!
    }

    @Test("Theme and Font size are remembered; Dark and Default when nothing is saved")
    func remembers() {
        let defaults = throwawayDefaults()
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
        let defaults = throwawayDefaults()
        let shot = AppearanceStore(defaults: defaults, forced: .light)
        shot.theme = .dark
        shot.fontSize = .large
        #expect(defaults.string(forKey: AppearanceStore.defaultsKey) == nil)
        #expect(defaults.string(forKey: AppearanceStore.fontSizeKey) == nil)
    }

    @Test("the toggle sets the other appearance, fixed, which leaves System")
    func toggleLeavesSystem() {
        let store = AppearanceStore(defaults: throwawayDefaults())
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
            let role = ReinsType.role(size: base, step: choice.step, weight: .regular, lineBox: 20)
            #expect(role.size == base + choice.step)
            #expect(role.lineBox == 20)
        }
        #expect(ReinsType.role(size: 72, scales: false, step: choice.step, weight: .semibold, lineBox: 88).size == 72)
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
        (.available(version: "0.2.0"), "Reins 0.2.0 is available"),
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
        #expect(SettingsWording.appName(version: "0.1.0") == "Reins 0.1.0")
        #expect(SettingsWording.appName(version: nil) == "Reins")
    }
}
