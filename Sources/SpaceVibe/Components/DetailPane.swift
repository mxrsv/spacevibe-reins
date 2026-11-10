import SwiftUI

/// The Skills detail pane (V5-R33): padding 32 40 40, at most 640 wide, its sections 24 apart, scrolling inside the panel.
/// Compose it from `PaneHead`, a description, `VerdictBox`, `PaneSection` with `SessionMeters` or `FileList`, the actions and a
/// `PopoverNote`; the page chooses the parts and their text, this block lays them out.
struct DetailPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        SpaceVibeScrollView {
            VStack(alignment: .leading, spacing: Metrics.DetailPane.spacing) { content }
                .padding(Metrics.DetailPane.insets)
                .frame(maxWidth: Metrics.DetailPane.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Skill details")
    }
}

/// The pane's head: a 48 tile holding the category glyph in its colour, the name (20/28 600) with the plugin tag, the meta
/// line, and the logo strip at the right.
struct PaneHead<Strip: View>: View {
    let name: String
    let glyph: any GlyphSource
    let tone: TabTone
    /// "plugin: neon" when a plugin owns the item.
    var pluginTag: String?
    /// "Skill", "Global": the meta line's parts, with a 2 pt dot between them.
    let meta: [String]
    @ViewBuilder var strip: Strip

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.DetailPane.headSpacing) {
            SpaceVibeIcon(source: glyph, size: .large, ink: tone.fill)
                .frame(width: Metrics.DetailPane.headTile, height: Metrics.DetailPane.headTile)
                .blockSurface(Palette.bgRaise, edge: Palette.hair2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.DetailPane.metaAbove) {
                HStack(spacing: Metrics.DetailPane.nameSpacing) {
                    Text(name).spaceVibeText(.heading, tone: .primary).lineLimit(1).truncationMode(.tail).lineBox(.heading)
                    if let pluginTag { PaneTag(pluginTag) }
                }
                HStack(spacing: Metrics.DetailPane.metaSpacing) {
                    ForEach(Array(meta.enumerated()), id: \.offset) { index, part in
                        if index > 0 { Circle().fill(Palette.fg4).frame(width: Metrics.DetailPane.metaDot, height: Metrics.DetailPane.metaDot) }
                        Text(part).spaceVibeText(.meta, tone: .tertiary).lineLimit(1).lineBox(.meta)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            strip.padding(.top, Metrics.Radius.edge * 2)
        }
    }
}

/// The plugin tag beside a name: the lock, "plugin: neon", 20 high with a `hair2` edge.
private struct PaneTag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.Radius.small, style: Metrics.Radius.cornerStyle)
        HStack(spacing: Metrics.DetailPane.tagSpacing) {
            SpaceVibeIcon(content: .lock, size: .small, ink: Palette.fg3)
            Text(text).spaceVibeText(.small, tone: .secondary).lineLimit(1)
        }
        .padding(.horizontal, Metrics.DetailPane.tagPadding)
        .frame(height: Metrics.DetailPane.tagHeight)
        .overlay(shape.strokeBorder(Palette.hair2, lineWidth: Metrics.Radius.edge))
        .accessibilityElement(children: .combine)
    }
}

/// A pane section: its label (11/16 500 `fg3`) 8 above its content.
struct PaneSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.DetailPane.sectionLabelSpacing) {
            Text(title).spaceVibeText(.smallLabel, tone: .tertiary).accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// "Sessions by CLI": a card (`bgRaise`, `hair` edge) with one column per detected CLI, a hairline between columns. Each shows
/// the CLI, its count with the unit "sessions" (28/32), a bar in the CLI's identity colour and when it last ran; a CLI without
/// the skill shows a dash, a dashed line and "<CLI> does not have this skill." An unknown count is a dash, never a zero.
struct SessionMeters: View {
    let meters: [SessionMeter]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(meters.enumerated()), id: \.element.cli) { index, meter in
                if index > 0 { Rectangle().fill(Palette.hair).frame(width: Metrics.Radius.edge).accessibilityHidden(true) }
                MeterColumn(meter: meter)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Metrics.Radius.edge)
        .blockSurface(Palette.bgRaise)
        .accessibilityElement(children: .contain)
    }
}

/// One CLI's column in the pane's "Sessions by CLI" card.
struct SessionMeter: Equatable {
    let cli: CoreCLI
    /// A word at the right of the column's head ("Not in Codex").
    let status: String?
    /// The count; nil draws the dash.
    let figure: Int?
    /// 0 to 1 over the busiest skill; nil draws the dashed line.
    let share: Double?
    let caption: String
    /// The part of the caption read in `fg2`: "Last ran" then "2 days ago".
    let emphasis: String?

    /// "1 session", "N sessions"; nil without a count.
    var sessionsLabel: String? { figure.map { "\($0) \($0 == 1 ? "session" : "sessions")" } }
}

private struct MeterColumn: View {
    let meter: SessionMeter

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.DetailPane.meterSpacing) {
            HStack(spacing: Metrics.DetailPane.meterHeadSpacing) {
                CLIMark(meter.cli, size: .control)
                Text(meter.cli.label).spaceVibeText(.meta, tone: .secondary)
                Spacer(minLength: 0)
                if let status = meter.status { Text(status).spaceVibeText(.small, tone: .tertiary).lineLimit(1).fixedSize() }
            }
            figure
            BarCell(share: meter.share, tone: meter.cli == .claude ? .claude : .codex)
                .frame(height: Metrics.DetailPane.meterBarHeight)
                .padding(.vertical, meter.share == nil ? Metrics.DetailPane.meterDashInset : 0)
            caption
        }
        .padding(Metrics.DetailPane.meterPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var figure: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.DetailPane.meterUnitGap) {
            if let count = meter.figure {
                Text("\(count)").spaceVibeText(.answer, tone: .primary)
                Text(count == 1 ? "session" : "sessions").spaceVibeText(.meta, tone: .tertiary)
            } else {
                Text("\u{2014}").spaceVibeText(.answer).foregroundStyle(Palette.fg4)
            }
        }
        .lineLimit(1)
        .lineBox(.answer)
    }

    private var caption: some View {
        let text = meter.emphasis.map { Text("\(meter.caption) ") .spaceVibeText(.meta, tone: .tertiary) + Text($0).spaceVibeText(.meta, tone: .secondary) }
            ?? Text(meter.caption).spaceVibeText(.meta, tone: .tertiary)
        return text.fixedSize(horizontal: false, vertical: true).lineBox(.meta)
    }

    private var spoken: String {
        let figure = meter.sessionsLabel ?? "no count"
        return [meter.cli.label, meter.status, figure, meter.caption, meter.emphasis].compactMap { $0 }.joined(separator: ", ")
    }
}

/// "Lives in": one row per file (32 high, 12 at the sides): the CLI's logo, then the path in `fg2`, cut at its end.
struct FileList: View {
    struct Entry: Identifiable {
        let cli: CoreCLI
        let path: String
        var id: CoreCLI { cli }
    }

    let files: [Entry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                HStack(spacing: Metrics.DetailPane.fileSpacing) {
                    CLIMark(file.cli, size: .glyph)
                    Text(file.path).spaceVibeText(.meta, tone: .secondary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metrics.DetailPane.filePadding)
                .frame(height: Metrics.DetailPane.fileRowHeight)
                .overlay(alignment: .top) {
                    if index > 0 { Rectangle().fill(Palette.hair).frame(height: Metrics.Radius.edge).accessibilityHidden(true) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(file.cli.label), \(file.path)")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle))
        .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.block, style: Metrics.Radius.cornerStyle)
            .strokeBorder(Palette.hair, lineWidth: Metrics.Radius.edge).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
    }
}
