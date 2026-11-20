import Foundation
import Testing
@testable import SpaceVibe

/// No secret-looking string from `config.toml` reaches the Rules page (AGENTS.md S-R3): a value shows only when it reads as a
/// plain word.
@Suite("Codex config wording", .fixtureCLIs)
struct CodexWordingTests {
    @Test("a plain mode word shows as written; a URL, a token or other free text shows as hidden text")
    func words() {
        for word in ["on-request", "workspace-write", "danger-full-access", "dev", "never"] {
            #expect(CodexWording.word(word) == word, "\(word)")
        }
        let canary = "http://user:CANARY-sk-live-0123456789@proxy.example.com:8080"
        for text in [canary, "My Token 1234", "sk-0123456789", "", String(repeating: "a", count: 25)] {
            #expect(CodexWording.word(text) == CodexWording.hiddenText, "\(text)")
        }
    }

    @Test("approval_policy reads as written, 'granular' for the table form, nil when unset")
    func approval() {
        #expect(CodexWording.approval(RulesSynthetic.codex(approval: "on-failure")) == "on-failure")
        #expect(CodexWording.approval(RulesSynthetic.codex(approval: nil)) == nil)
        var granular = RulesSynthetic.codex()
        granular.approvalPolicy = .granular([])
        #expect(CodexWording.approval(granular) == "granular")
    }
}
