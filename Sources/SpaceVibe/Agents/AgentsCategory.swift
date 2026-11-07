import Foundation

/// The four tabs of the Agents page, in order (V5-R20): the title, the glyph and the colour each takes while active.
enum AgentsCategory: String, CaseIterable, Identifiable {
    case skills, subagents, hooks, rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .skills: "Skills"
        case .subagents: "Subagents"
        case .hooks: "Hooks"
        case .rules: "Rules"
        }
    }

    var glyph: any GlyphSource {
        switch self {
        case .skills: CategoryGlyph.skill
        case .subagents: CategoryGlyph.subagent
        case .hooks: CategoryGlyph.hook
        case .rules: ContentGlyph.rule
        }
    }

    var tone: TabTone {
        switch self {
        case .skills: .skill
        case .subagents: .subagent
        case .hooks: .hook
        case .rules: .rule
        }
    }
}
