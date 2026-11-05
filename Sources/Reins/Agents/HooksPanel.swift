import ReinsCore
import SwiftUI

/// The words of the Hooks panel. Pure, so the tests pin them.
enum AgentsHookWording {
    static func title(_ hook: InventoryHook) -> String {
        hook.matcher.map { "\(hook.event) \u{00B7} \($0)" } ?? hook.event
    }

    /// Claude Code counts runs from its logs; Codex does not log them.
    static func runs(_ hook: InventoryHook, scanned: Bool) -> String {
        guard hook.cli == .claude else { return "not measurable" }
        guard scanned, let usage = hook.usage else { return "not counted yet" }
        return AgentsWording.plural(usage.runs, "run")
    }

    static let notMeasurableReason = "Codex does not log hook runs."

    /// What a copy to the other CLI should know: the other CLI names its tools differently, or it has no such event.
    static func copyWarning(_ hook: InventoryHook) -> String {
        let target: AgentKind = hook.cli == .claude ? .codex : .claude
        if !(AgentsWording.events[target] ?? []).contains(hook.event) {
            return "\(target.name) has no \(hook.event) event, so this hook will never run there."
        }
        return "\(target.name) names its tools differently, so a matcher such as \(hook.matcher ?? "Edit") may match nothing there. Reins writes the hook and never runs it."
    }
}

/// Hooks (spec, Interface: Hooks): each row the event and matcher, the command and its runs; Codex reads "not measurable";
/// a dead hook carries "script missing". Remove N dead, Add hook, and per row Copy to the other CLI and remove.
struct HooksPanel: View {
    @Bindable var model: AgentsModel
    let agent: AgentKind
    let hooks: [InventoryHook]
    @FocusState private var matcherFocused: Bool
    @FocusState private var commandFocused: Bool

    var body: some View {
        let removed = removedIDs
        let shown = hooks.filter { !removed.contains($0.id) }
        let dead = shown.filter { $0.dead && $0.removable }
        GroupedList {
            CardHeader("Hooks", count: shown.count + added.count, columns: {
                if !dead.isEmpty {
                    Button { removeDead(dead) } label: { ButtonLabel("Remove \(dead.count) dead", icon: .trash) }.buttonStyle(.reins(.danger))
                }
            })
            ForEach(shown, id: \.id) { hook in row(hook) }
            ForEach(added, id: \.self) { item in
                Row { RowText(item.title, subtitle: item.command, codeSubtitle: true) { Tag("new") } }
                    .lead { PageIcon(.hook, size: .row) }
            }
            if shown.isEmpty && added.isEmpty { EmptyRow("No hooks here.") }
        }
        GroupedList {
            CardHeader("Add hook")
            FormRow {
                HStack(spacing: Rhythm.tools) {
                    MenuPicker(label: "Event", options: (AgentsWording.events[agent] ?? []).map { MenuOption(value: $0, title: $0) },
                               selection: model.forms.hookEvent) { model.forms.hookEvent = $0 }
                    TextInputField(label: "Matcher", placeholder: "Edit|Write", text: $model.forms.hookMatcher, code: true, focused: $matcherFocused) {}
                }
                HStack(spacing: Rhythm.tools) {
                    TextInputField(label: "Command", placeholder: "prettier --write \"$FILE\"", text: $model.forms.hookCommand, code: true, focused: $commandFocused) { addHook() }
                    Button { addHook() } label: { ButtonLabel("Add hook", icon: .add) }
                        .buttonStyle(.reins(.normal))
                        .disabled(model.forms.hookCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Reins writes hooks and never runs them.").reinsText(.caption, tone: .tertiary)
            }
        }
    }

    private struct Added: Hashable {
        let title: String
        let command: String
    }

    private var added: [Added] {
        model.draft.items.compactMap { item in
            switch item.change {
            case .claude(.addHook(let event, let matcher, let command)), .codexHook(.add(let event, let matcher, let command)):
                return Added(title: matcher.map { "\(event) \u{00B7} \($0)" } ?? event, command: command)
            default:
                return nil
            }
        }
    }

    private var removedIDs: Set<String> {
        var out = Set<String>()
        for item in model.draft.items {
            switch item.change {
            case .claude(.removeHook(let event, let matcher, let command)), .codexHook(.remove(let event, let matcher, let command)):
                for hook in hooks where hook.event == event && hook.matcher == matcher && hook.command == command { out.insert(hook.id) }
            default:
                break
            }
        }
        return out
    }

    private func row(_ hook: InventoryHook) -> some View {
        Row(tall: true) {
            RowText(AgentsHookWording.title(hook), subtitle: hook.command, codeSubtitle: true) {
                if hook.dead { Tag("script missing", tone: .danger, icon: .scriptMissing) }
                if let errors = hook.usage?.errors, errors > 0 { Tag(AgentsWording.plural(errors, "error"), tone: .warn) }
                if !hook.removable { Tag("plugin: \(hook.owner)", icon: .lock) }
            }
        }
        .lead { PageIcon(.hook, size: .row) }
        .cells {
            if hook.cli == .codex {
                Tag("not measurable", icon: .warning).help(AgentsHookWording.notMeasurableReason)
            } else {
                Text(AgentsHookWording.runs(hook, scanned: model.usageScanned)).reinsText(.number, tone: .secondary)
            }
        }
        .actions {
            if hook.removable {
                RowActionButton(title: "Copy to \(agent.other.name)", icon: .copy) { model.pendingCopy = hook }
                RowActionButton(title: "Remove hook", icon: .trash, kind: .danger, iconOnly: true) { remove(hook) }
            }
        }
    }

    private func remove(_ hook: InventoryHook) {
        let change: DraftChange = agent == .claude
            ? .claude(.removeHook(event: hook.event, matcher: hook.matcher, command: hook.command))
            : .codexHook(.remove(event: hook.event, matcher: hook.matcher, command: hook.command))
        model.draft.add(.remove, "\(AgentsHookWording.title(hook)): \(hook.command)", tag: hook.dead ? "dead" : nil, tone: .danger, change)
    }

    private func removeDead(_ dead: [InventoryHook]) {
        for hook in dead { remove(hook) }
    }

    private func addHook() {
        let command = model.forms.hookCommand.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }
        let matcher = model.forms.hookMatcher.trimmingCharacters(in: .whitespaces)
        let event = model.forms.hookEvent
        let change: DraftChange = agent == .claude
            ? .claude(.addHook(event: event, matcher: matcher.isEmpty ? nil : matcher, command: command))
            : .codexHook(.add(event: event, matcher: matcher.isEmpty ? nil : matcher, command: command))
        model.draft.add(.add, "\(matcher.isEmpty ? event : "\(event) \u{00B7} \(matcher)"): \(command)", change)
        model.forms.hookCommand = ""
        model.forms.hookMatcher = ""
    }
}
