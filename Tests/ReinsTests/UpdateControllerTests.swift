import Foundation
import Testing
@testable import Reins

@Suite("App updates")
struct UpdateControllerTests {
    private var validInfo: [String: Any] {
        ["SUFeedURL": "https://releases.example.com/appcast.xml",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()]
    }

    @Test("a feed must be HTTPS without credentials or a fragment; http only for 127.0.0.1", arguments: [
        "", "invalid", "https:///", "file:///tmp/appcast.xml", "http://example.com/appcast.xml",
        "http://localhost:8000/appcast.xml", "https://user:secret@example.com/appcast.xml",
        "https://example.com/appcast.xml#fragment",
    ])
    func rejectsSource(source: String) {
        let info = validInfo.merging(["SUFeedURL": source]) { _, new in new }
        #expect(UpdateController.configurationIssue(in: info) != nil)
    }

    @Test("an HTTPS feed and the local test feed are accepted", arguments: [
        "https://releases.example.com/appcast.xml", "http://127.0.0.1:8765/appcast.xml",
    ])
    func acceptsSource(source: String) {
        let info = validInfo.merging(["SUFeedURL": source]) { _, new in new }
        #expect(UpdateController.configurationIssue(in: info) == nil)
    }

    @Test("a build without a feed, or without a 32-byte key, does not run the updater")
    func requiresFeedAndKey() {
        #expect(UpdateController.configurationIssue(in: [:]) != nil)
        for key in ["", "invalid", Data(repeating: 1, count: 31).base64EncodedString()] {
            let info = validInfo.merging(["SUPublicEDKey": key]) { _, new in new }
            #expect(UpdateController.configurationIssue(in: info) != nil)
        }
    }

    @Test("only a normal launch outside REINS_TEST runs the updater")
    func launchModes() {
        #expect(UpdateController.runs(in: .normal, environment: [:]))
        #expect(!UpdateController.runs(in: .normal, environment: ["REINS_TEST": "1"]))
        #expect(!UpdateController.runs(in: .gallery, environment: [:]))
        #expect(!UpdateController.runs(in: .shots(directory: URL(fileURLWithPath: "/tmp")), environment: [:]))
    }

    @Test("the committed plist checks on its own, never installs on its own, and carries no feed")
    func shippedDefaults() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["SUEnableSystemProfiling"] as? Bool == false)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86400)
        #expect(info["SUFeedURL"] == nil)
        #expect(Data(base64Encoded: info["SUPublicEDKey"] as? String ?? "")?.count == 32)
    }

    @Test("the updater stays off in a test launch even when the bundle has a feed")
    @MainActor
    func startRespectsMode() {
        let updates = UpdateController(toasts: ToastCenter(announce: false))
        updates.start(mode: .normal, environment: ["REINS_TEST": "1"], info: validInfo)
        #expect(updates.isRunning == false)
    }
}

@Suite("Toast action")
@MainActor
struct ToastActionTests {
    @Test("running the action hides the toast and calls it once")
    func runsAction() {
        let toasts = ToastCenter(announce: false)
        var runs = 0
        toasts.show("Reins 0.2.0 is available", action: UpdateController.viewAction { runs += 1 })
        #expect(toasts.current?.action?.title == "View")
        toasts.runCurrentAction()
        #expect(runs == 1)
        #expect(toasts.current == nil)
    }

    @Test("undo keeps its label and a toast without undo has no action")
    func undoIsAnAction() {
        let toasts = ToastCenter(announce: false)
        toasts.show("Removed ponytail", undo: {})
        #expect(toasts.current?.action?.title == "Undo")
        toasts.show("Could not write settings.json", tone: .danger)
        #expect(toasts.current?.action == nil)
    }

    @Test("dismissing by id leaves a toast that replaced it")
    func dismissById() {
        let toasts = ToastCenter(announce: false)
        let first = toasts.show("Reins 0.2.0 is available", action: UpdateController.viewAction {})
        toasts.show("Removed ponytail", undo: {})
        toasts.dismiss(id: first)
        #expect(toasts.current?.message == "Removed ponytail")
        let second = toasts.show("Reins 0.2.0 is available", action: UpdateController.viewAction {})
        toasts.dismiss(id: second)
        #expect(toasts.current == nil)
    }
}
