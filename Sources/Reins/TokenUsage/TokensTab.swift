import ReinsCore
import SwiftUI

/// Registers Tokens with the shell: sidebar item (`⌘4` by its place in `TabRegistry`), key hints, palette entries and the screen.
@MainActor
final class TokensTab: ReinsTab {
    static let tabID = "tokens"

    let id = TokensTab.tabID
    let title = "Tokens"
    let systemImage = "cylinder.split.1x2"
    let model: TokensModel

    init(env: AppEnvironment? = nil) { model = TokensModel(env: env ?? .shared) }

    init(model: TokensModel) { self.model = model }

    var hints: [KeyHint] {
        var hints = [KeyHint(keys: "\u{2190} \u{2192}", label: TokensFormat.periodTitle(model.period))]
        if model.selectedID != nil { hints.append(KeyHint(keys: "\u{21A9}", label: "Token kinds")) }
        if model.hasScope { hints.append(KeyHint(keys: "Esc", label: "Clear scope")) }
        return hints
    }

    var paletteActions: [PaletteEntry] {
        let model = self.model
        var entries: [PaletteEntry] = TokenPeriod.allCases.map { period in
            PaletteEntry(id: "tokens.period.\(period.rawValue)", title: "Show tokens by \(TokensFormat.periodTitle(period).lowercased())",
                         subtitle: model.period == period ? "Current period" : nil, systemImage: "calendar", keywords: ["period", "tokens"]) {
                model.period = period
            }
        }
        entries += TokenMeasure.allCases.map { measure in
            PaletteEntry(id: "tokens.measure.\(measure.rawValue)", title: "Measure: \(TokensFormat.measureTitle(measure))",
                         subtitle: model.measure == measure ? "Current measure" : nil, systemImage: "chart.bar", keywords: ["measure", "cost", "tokens"]) {
                model.measure = measure
            }
        }
        if model.hasScope {
            entries.append(PaletteEntry(id: "tokens.clear", title: "Clear scope", systemImage: "xmark.circle", keywords: ["scope", "day", "model", "project"]) {
                model.clearScope()
            })
        }
        entries.append(PaletteEntry(id: "tokens.rescan", title: "Rescan token history", systemImage: "arrow.clockwise", keywords: ["refresh", "tokens", "cost"]) {
            model.rescan()
        })
        return entries
    }

    var content: AnyView { AnyView(TokensScreen(model: model)) }
}
