//
//  ProjectReportView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-10-06.
//

import SwiftUI
import Charts

// MARK: - Layout

/// Fixed A4 geometry, in PDF points. No GeometryReader anywhere: every
/// page is a fixed frame and every block a fixed width, so a block's
/// measured height is the height it renders at.
enum ReportLayout {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40
    static let contentWidth: CGFloat = pageSize.width - 2 * margin
    static let headerHeight: CGFloat = 28
    static let headerGap: CGFloat = 14
    static let footerHeight: CGFloat = 14
    static let footerGap: CGFloat = 10
    static let blockSpacing: CGFloat = 10
    /// What a page's blocks may fill.
    static let bodyHeight: CGFloat = pageSize.height - 2 * margin
        - headerHeight - 0.5 - headerGap - footerGap - footerHeight
}

/// One unit of page content. Pages break only between blocks;
/// keepWithNext holds a heading together with what follows it.
struct ReportBlock {
    let view: AnyView
    var keepWithNext = false

    init<V: View>(keepWithNext: Bool = false, @ViewBuilder _ content: () -> V) {
        self.view = AnyView(content())
        self.keepWithNext = keepWithNext
    }
}

/// A report part that starts on a new page and may run over several.
struct ReportSection {
    let title: String
    let blocks: [ReportBlock]
}

// MARK: - Formatting

enum ReportFormat {
    static let locale = Locale(identifier: "sv_SE")
    static let noData = "ingen data"

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func delta(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(-value)" }
        return "0"
    }

    static func deltaColor(_ value: Int) -> Color {
        if value > 0 { return ReportPalette.strong }
        if value < 0 { return ReportPalette.risk }
        return ReportPalette.textTertiary
    }

    static func levelWord(_ level: ScoreLevel) -> String {
        switch level {
        case .risk:   return "Risk"
        case .note:   return "Bevaka"
        case .strong: return "Starkt"
        }
    }

    /// "ca" marks a date set by hand afterwards.
    static func completion(_ action: DoneAction) -> String {
        guard let completedAt = action.completedAt else { return "datum saknas" }
        return (action.completedAtManual ? "ca " : "") + date(completedAt)
    }

    static func period(_ period: ReportPeriod?) -> String {
        guard let period else { return "–" }
        switch (period.fromVersion, period.toVersion) {
        case let (from?, to?): return "mellan v\(from) och v\(to)"
        case let (nil, to?):   return "före v\(to)"
        case let (from?, nil): return "efter v\(from)"
        case (nil, nil):       return "ingen assessment"
        }
    }
}

// MARK: - Page

struct ReportPageView: View {
    let sectionTitle: String
    let continued: Bool
    let projectName: String
    let generatedAt: Date
    let pageNumber: Int
    let pageCount: Int
    let blocks: [AnyView]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(continued ? "\(sectionTitle) (forts.)" : sectionTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ReportPalette.textPrimary)
                Spacer()
                Text(projectName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ReportPalette.textSecondary)
            }
            .frame(height: ReportLayout.headerHeight, alignment: .bottom)

            Rectangle()
                .fill(ReportPalette.hairline)
                .frame(height: 0.5)
                .padding(.bottom, ReportLayout.headerGap)

            VStack(alignment: .leading, spacing: ReportLayout.blockSpacing) {
                ForEach(blocks.indices, id: \.self) { i in
                    ReportBlockFrame { blocks[i] }
                }
            }
            .frame(width: ReportLayout.contentWidth, height: ReportLayout.bodyHeight, alignment: .topLeading)
            .clipped()
            .padding(.bottom, ReportLayout.footerGap)

            HStack {
                Text("Projektrapport · skapad \(ReportFormat.date(generatedAt))")
                Spacer()
                Text("Sida \(pageNumber) av \(pageCount)")
            }
            .font(.system(size: 8))
            .foregroundStyle(ReportPalette.textTertiary)
            .frame(height: ReportLayout.footerHeight)
        }
        .padding(ReportLayout.margin)
        .frame(width: ReportLayout.pageSize.width, height: ReportLayout.pageSize.height)
        .background(ReportPalette.background)
        .environment(\.colorScheme, .light)
        .environment(\.locale, ReportFormat.locale)
    }
}

/// The exact frame a block is measured in and rendered in.
struct ReportBlockFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: ReportLayout.contentWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .light)
            .environment(\.locale, ReportFormat.locale)
    }
}

// MARK: - Content

/// Turns ProjectReportData into the four report sections. Domain labels
/// come from data.templateLabelsPerDomain (questionStore.domainLabel).
struct ProjectReportContent {
    let data: ProjectReportData

    var sections: [ReportSection] {
        [summarySection, developmentSection, establishedSection, methodSection]
    }

    private func label(_ domain: Domain) -> String {
        data.templateLabelsPerDomain[domain] ?? domain.rawValue
    }

    private var first: AssessmentPoint? { data.series.first }
    private var latest: AssessmentPoint? { data.series.last }
    private var hasDelta: Bool { data.series.count >= 2 }

    /// nil = no data. Option scores are 10/35/65/90, so a domain score of 0
    /// only arises when no question in the domain was answered — shown as
    /// "ingen data", never as a 0. ScoringService itself is unchanged.
    private func domainScore(_ point: AssessmentPoint?, _ domain: Domain) -> Int? {
        guard let score = point?.domainScores[domain], score > 0 else { return nil }
        return score
    }

    /// The loader's delta, but nil when either side has no data.
    private func domainDelta(_ delta: ScoreDelta?, from: AssessmentPoint?, to: AssessmentPoint?, _ domain: Domain) -> Int? {
        guard domainScore(from, domain) != nil, domainScore(to, domain) != nil else { return nil }
        return delta?.perDomain[domain]
    }

    // MARK: 1. Sammanfattning

    private var summarySection: ReportSection {
        var blocks: [ReportBlock] = []
        blocks.append(ReportBlock {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJEKTRAPPORT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(ReportPalette.accent)
                Text(data.projectName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(ReportPalette.textPrimary)
                Text("Skapad \(ReportFormat.date(data.generatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(ReportPalette.textSecondary)
            }
        })
        if let notice = seriesNotice {
            blocks.append(ReportBlock { NoticeBox(text: notice) })
        }
        blocks.append(ReportBlock { radarBlock })
        blocks.append(ReportBlock { keyFigures })
        blocks.append(ReportBlock { domainSummaryTable })
        return ReportSection(title: "Sammanfattning", blocks: blocks)
    }

    /// Shown when the series can't carry a development (fewer than two).
    private var seriesNotice: String? {
        switch data.series.count {
        case 0:
            return "Projektet har ännu ingen slutförd assessment. Poäng, jämförelser och delta saknas i rapporten."
        case 1:
            return "Projektet har bara en slutförd assessment. Rapporten visar den ena mätningen; delta och utveckling över tid kräver minst två."
        default:
            return nil
        }
    }

    @ViewBuilder
    private var radarBlock: some View {
        if let first, let latest {
            HStack(alignment: .top, spacing: 0) {
                if hasDelta {
                    radarColumn(point: first, heading: "Första", color: ReportPalette.radarFirst)
                    radarColumn(point: latest, heading: "Senaste", color: ReportPalette.radarLatest)
                } else {
                    Spacer(minLength: 0)
                    radarColumn(point: latest, heading: "Enda slutförda", color: ReportPalette.radarLatest)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: ReportLayout.contentWidth)
        } else {
            NoDataBox(text: "Radar: \(ReportFormat.noData)")
        }
    }

    private func radarColumn(point: AssessmentPoint, heading: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(heading) · v\(point.version) · \(ReportFormat.date(point.date))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ReportPalette.textPrimary)
            RadarChart(
                scores: Domain.allCases.map { domain in
                    let score = point.domainScores[domain] ?? 0
                    return DomainScore(domain: domain, score: score, level: ScoringService.level(for: score))
                },
                label: { domainScore(point, $0) == nil ? "\(label($0))\n\(ReportFormat.noData)" : label($0) },
                labelColor: ReportPalette.textSecondary,
                gridColor: ReportPalette.radarGrid,
                fillColor: color,
                flatFillOpacity: 0.18
            )
            .frame(width: 236, height: 220)
            Text("Totalt \(point.total)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(width: ReportLayout.contentWidth / 2)
    }

    private var keyFigures: some View {
        let counts = allActionCounts
        let openCount = counts.open + counts.prio + counts.doing + counts.waiting
        return HStack(spacing: 8) {
            FigureTile(
                title: "Slutförda assessments",
                value: "\(data.series.count)",
                detail: incompleteDetail
            )
            if let latest {
                FigureTile(
                    title: "Totalpoäng",
                    value: "\(latest.total)",
                    detail: data.firstToLatestDelta.map { "\(ReportFormat.delta($0.total)) sedan v\(first?.version ?? 0)" }
                        ?? "ingen delta",
                    valueColor: ReportPalette.level(ScoringService.level(for: latest.total))
                )
            } else {
                FigureTile(title: "Totalpoäng", value: "–", detail: ReportFormat.noData)
            }
            FigureTile(title: "Klara uppgifter", value: "\(counts.done)", detail: nil)
            FigureTile(title: "Öppna uppgifter", value: "\(openCount)", detail: nil)
        }
    }

    /// Started but not completed; nothing shown when there are none.
    private var incompleteDetail: String? {
        switch data.incompleteAssessmentCount {
        case 0:  return nil
        case 1:  return "1 påbörjad assessment ingår inte"
        case let n: return "\(n) påbörjade assessments ingår inte"
        }
    }

    private var allActionCounts: ActionCounts {
        (Array(data.actionsPerDomain.values) + [data.unknownDomainActions]).reduce(into: ActionCounts()) { sum, c in
            sum.open += c.open
            sum.prio += c.prio
            sum.doing += c.doing
            sum.waiting += c.waiting
            sum.done += c.done
        }
    }

    private var domainSummaryTable: some View {
        // Without delta the two dropped columns go to the domain column.
        let domainWidth: CGFloat = ReportLayout.contentWidth - (hasDelta ? 4 : 2) * 85
        return VStack(spacing: 0) {
            TableRow(height: 22, background: ReportPalette.surface) {
                cell("Domän", width: domainWidth, alignment: .leading, weight: .semibold)
                if hasDelta {
                    cell("Första", width: 85, weight: .semibold)
                }
                cell(hasDelta ? "Senaste" : "Poäng", width: 85, weight: .semibold)
                if hasDelta {
                    cell("Förändring", width: 85, weight: .semibold)
                }
                cell("Nivå", width: 85, weight: .semibold)
            }
            ForEach(Domain.allCases, id: \.self) { domain in
                TableRow(height: 20) {
                    cell(label(domain), width: domainWidth, alignment: .leading)
                    if hasDelta {
                        scoreCell(domainScore(first, domain), width: 85)
                    }
                    scoreCell(domainScore(latest, domain), width: 85)
                    if hasDelta {
                        deltaCell(domainDelta(data.firstToLatestDelta, from: first, to: latest, domain), width: 85)
                    }
                    if domainScore(latest, domain) != nil, let level = latest?.levels[domain] {
                        cell(ReportFormat.levelWord(level), width: 85, weight: .semibold, color: ReportPalette.level(level))
                    } else {
                        cell(ReportFormat.noData, width: 85, size: 8, color: ReportPalette.textTertiary)
                    }
                }
            }
        }
        .overlay(Rectangle().strokeBorder(ReportPalette.hairline, lineWidth: 0.5))
    }

    // MARK: 2. Utveckling

    private var developmentSection: ReportSection {
        var blocks: [ReportBlock] = []
        if let notice = seriesNotice {
            blocks.append(ReportBlock { NoticeBox(text: notice) })
        }
        blocks.append(ReportBlock(keepWithNext: true) {
            SubHeading(text: "Poäng per assessment", detail: hasDelta ? "Δ = förändring mot föregående slutförda assessment" : nil)
        })
        if data.series.isEmpty {
            blocks.append(ReportBlock { NoDataBox(text: "Tabell: \(ReportFormat.noData)") })
        } else {
            // Chunked so a long series breaks across pages with its header
            // repeated; 10 versions + 9 deltas fit well within a page.
            let chunkSize = 10
            for start in stride(from: 0, to: data.series.count, by: chunkSize) {
                let range = start..<min(start + chunkSize, data.series.count)
                blocks.append(ReportBlock { scoreTable(range) })
            }
        }
        blocks.append(ReportBlock(keepWithNext: true) {
            SubHeading(text: "Trend", detail: "Totalpoäng och domäner, 0–100")
        })
        if data.series.isEmpty {
            blocks.append(ReportBlock { NoDataBox(text: "Diagram: \(ReportFormat.noData)") })
        } else {
            blocks.append(ReportBlock { trendChart })
        }
        return ReportSection(title: "Utveckling", blocks: blocks)
    }

    private static let tableLabelWidth: CGFloat = 95
    private static var tableColumnWidth: CGFloat {
        (ReportLayout.contentWidth - tableLabelWidth) / CGFloat(Domain.allCases.count + 1)
    }

    private func scoreTable(_ range: Range<Int>) -> some View {
        let w = Self.tableColumnWidth
        return VStack(spacing: 0) {
            TableRow(height: 30, background: ReportPalette.surface) {
                cell("Assessment", width: Self.tableLabelWidth, alignment: .leading, weight: .semibold)
                ForEach(Domain.allCases, id: \.self) { domain in
                    cell(label(domain), width: w, weight: .semibold, size: 8, lines: 2)
                }
                cell("Totalt", width: w, weight: .bold, size: 8)
            }
            ForEach(Array(range), id: \.self) { i in
                let point = data.series[i]
                if i > 0, let pair = data.adjacentDeltas.first(where: { $0.toVersion == point.version }) {
                    let previous = data.series[i - 1]
                    TableRow(height: 16, background: ReportPalette.surface.opacity(0.6)) {
                        cell("Δ v\(pair.fromVersion)→v\(pair.toVersion)", width: Self.tableLabelWidth, alignment: .leading,
                             size: 8, color: ReportPalette.textTertiary)
                        ForEach(Domain.allCases, id: \.self) { domain in
                            deltaCell(domainDelta(pair.delta, from: previous, to: point, domain), width: w, size: 8)
                        }
                        deltaCell(pair.delta.total, width: w, size: 8, weight: .bold)
                    }
                }
                TableRow(height: 24) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("v\(point.version)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ReportPalette.textPrimary)
                        Text(ReportFormat.date(point.date))
                            .font(.system(size: 7.5))
                            .foregroundStyle(ReportPalette.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: Self.tableLabelWidth, alignment: .leading)
                    ForEach(Domain.allCases, id: \.self) { domain in
                        scoreCell(domainScore(point, domain), width: w)
                    }
                    scoreCell(point.total, width: w, weight: .bold)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(ReportPalette.hairline, lineWidth: 0.5))
    }

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let series: String
        let version: String
        let score: Int
        let isTotal: Bool
    }

    private static let totalSeriesName = "Totalt"

    private var trendPoints: [TrendPoint] {
        data.series.flatMap { point in
            [TrendPoint(series: Self.totalSeriesName, version: "v\(point.version)", score: point.total, isTotal: true)]
                + Domain.allCases.compactMap { domain in
                    domainScore(point, domain).map {
                        TrendPoint(series: label(domain), version: "v\(point.version)", score: $0, isTotal: false)
                    }
                }
        }
    }

    private var trendChart: some View {
        let names = [Self.totalSeriesName] + Domain.allCases.map(label)
        let colors = [ReportPalette.textPrimary] + ReportPalette.series
        return Chart(trendPoints) { p in
            LineMark(
                x: .value("Assessment", p.version),
                y: .value("Poäng", p.score),
                series: .value("Serie", p.series)
            )
            .foregroundStyle(by: .value("Serie", p.series))
            .lineStyle(StrokeStyle(lineWidth: p.isTotal ? 2.5 : 1.2, dash: p.isTotal ? [] : [4, 2]))
            PointMark(
                x: .value("Assessment", p.version),
                y: .value("Poäng", p.score)
            )
            .foregroundStyle(by: .value("Serie", p.series))
            .symbolSize(p.isTotal ? 36 : 14)
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 34, 66, 100]) { _ in
                AxisGridLine().foregroundStyle(ReportPalette.hairline)
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(ReportPalette.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(ReportPalette.textSecondary)
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
        .frame(width: ReportLayout.contentWidth, height: 300)
    }

    // MARK: 3. Etablerat per domän

    private var establishedSection: ReportSection {
        var blocks: [ReportBlock] = []
        let insightsHeading = latest.map { "Senaste insikter (v\($0.version))" } ?? "Senaste insikter"
        for domain in Domain.allCases {
            let counts = data.actionsPerDomain[domain] ?? ActionCounts()
            let done = data.doneActions.filter { Domain(caseInsensitive: $0.domain) == domain }
            let insights = data.latestInsights.filter { $0.domain.flatMap { Domain(caseInsensitive: $0) } == domain }
            blocks += domainBlocks(
                title: label(domain),
                counts: counts,
                done: done,
                insights: insights,
                insightsHeading: insightsHeading
            )
        }
        // Rows whose domain string matches no Domain — kept, not dropped.
        let unknownDone = data.doneActions.filter { Domain(caseInsensitive: $0.domain) == nil }
        let unknownInsights = data.latestInsights.filter { $0.domain.flatMap { Domain(caseInsensitive: $0) } == nil }
        let unknown = data.unknownDomainActions
        if unknown.done + unknown.open + unknown.prio + unknown.doing + unknown.waiting > 0 || !unknownInsights.isEmpty {
            blocks += domainBlocks(
                title: "Okänd domän",
                counts: unknown,
                done: unknownDone,
                insights: unknownInsights,
                insightsHeading: insightsHeading
            )
        }
        return ReportSection(title: "Etablerat per domän", blocks: blocks)
    }

    private func domainBlocks(
        title: String,
        counts: ActionCounts,
        done: [DoneAction],
        insights: [InsightSummary],
        insightsHeading: String
    ) -> [ReportBlock] {
        let openCount = counts.open + counts.prio + counts.doing + counts.waiting
        let isEmpty = counts.done == 0 && openCount == 0 && insights.isEmpty
        var blocks: [ReportBlock] = []
        // The heading always has a next block ("ingen data" at least).
        blocks.append(ReportBlock(keepWithNext: true) {
            VStack(alignment: .leading, spacing: 3) {
                Rectangle().fill(ReportPalette.hairline).frame(height: 1).padding(.bottom, 6)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ReportPalette.textPrimary)
                Text(countsLine(counts, openCount: openCount))
                    .font(.system(size: 9))
                    .foregroundStyle(ReportPalette.textSecondary)
            }
        })
        if isEmpty {
            blocks.append(ReportBlock { NoDataBox(text: ReportFormat.noData) })
            return blocks
        }

        if done.isEmpty {
            blocks.append(ReportBlock { MutedLine(text: "Inga klara uppgifter.") })
        } else {
            blocks.append(ReportBlock(keepWithNext: true) {
                HStack(spacing: 8) {
                    columnHeading("Klar uppgift").frame(maxWidth: .infinity, alignment: .leading)
                    columnHeading("Klar").frame(width: 82, alignment: .leading)
                    columnHeading("Period").frame(width: 112, alignment: .leading)
                }
            })
            for action in done {
                blocks.append(ReportBlock {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(action.title)
                            .font(.system(size: 9))
                            .foregroundStyle(ReportPalette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ReportFormat.completion(action))
                            .font(.system(size: 8.5))
                            .foregroundStyle(action.completedAt == nil ? ReportPalette.textTertiary : ReportPalette.textSecondary)
                            .frame(width: 82, alignment: .leading)
                        Text(ReportFormat.period(action.period))
                            .font(.system(size: 8.5))
                            .foregroundStyle(ReportPalette.textSecondary)
                            .frame(width: 112, alignment: .leading)
                    }
                })
            }
        }

        blocks.append(ReportBlock(keepWithNext: !insights.isEmpty) { columnHeading(insightsHeading).padding(.top, 2) })
        if insights.isEmpty {
            blocks.append(ReportBlock { MutedLine(text: "Inga insikter.") })
        } else if data.textsHidden {
            // No titles in the data — a count stands in for the list.
            let countText = insights.count == 1 ? "1 insikt" : "\(insights.count) insikter"
            blocks.append(ReportBlock {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(ReportPalette.accent)
                    Text(countText)
                        .foregroundStyle(ReportPalette.textPrimary)
                }
                .font(.system(size: 9))
            })
        } else {
            for insight in insights {
                blocks.append(ReportBlock {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(ReportPalette.accent)
                        Text(insight.title ?? "(utan titel)")
                            .foregroundStyle(ReportPalette.textPrimary)
                    }
                    .font(.system(size: 9))
                })
            }
        }
        return blocks
    }

    private func countsLine(_ counts: ActionCounts, openCount: Int) -> String {
        var parts = ["Klara \(counts.done)", "Öppna \(openCount)"]
        var openDetail: [String] = []
        if counts.prio > 0 { openDetail.append("prio \(counts.prio)") }
        if counts.doing > 0 { openDetail.append("pågår \(counts.doing)") }
        if counts.waiting > 0 { openDetail.append("väntar \(counts.waiting)") }
        if !openDetail.isEmpty { parts[1] += " (varav \(openDetail.joined(separator: ", ")))" }
        return parts.joined(separator: " · ")
    }

    // MARK: 4. Metod

    private var methodSection: ReportSection {
        var items: [(String, String)] = [
            ("Underlag",
             "Rapporten bygger på projektets assessments, svar, uppgifter och insikter. Endast slutförda assessments ingår: alla frågor i assessmentens frågeuppsättning besvarade."
                + (data.textsHidden
                    ? " Uppgifternas och insikternas texter ingår inte: en klar uppgift visas med sitt ursprung (planuppgift, insiktsuppgift eller egen uppgift), insikter som antal per domän."
                    : "")),
            ("Poäng",
             "Varje svarsalternativ har en poäng: 10, 35, 65 eller 90. Poäng 0 betyder ingen data och räknas inte in. Domänpoängen är det avrundade medelvärdet av besvarade frågor i domänen; totalpoängen är det avrundade medelvärdet av domänpoängen. Samma beräkning som resultatvyn i appen."),
            ("Nivåer",
             "Starkt: 66 eller mer. Bevaka: 34–65. Risk: under 34."),
            ("Delta",
             "Förändringen mellan två intilliggande slutförda assessments (v1→v2 osv.). Ett par kan spänna över en ej slutförd assessment; versionsnumren visar det. Med färre än två slutförda assessments visas ingen delta."),
            ("Datum",
             "En assessments datum är när den skapades. En uppgifts klardatum sätts automatiskt när den markeras klar. \"ca\" betyder att datumet satts i efterhand och är ungefärligt; \"datum saknas\" att inget datum finns."),
            ("Period",
             "Mellan vilka assessments en uppgift blev klar, utifrån assessmentdatumen: \"före v1\" före den första, \"efter vN\" efter den senaste."),
            ("Insikter",
             data.textsHidden
                ? "AI-genererade insikter från den senaste slutförda assessmenten, endast antal per domän."
                : "AI-genererade insikter från den senaste slutförda assessmenten, endast titlar, grupperade per domän."),
        ]
        var hidden: [String] = []
        if data.nameHidden { hidden.append("Projektnamnet är dolt.") }
        if data.textsHidden { hidden.append("Uppgifts- och insiktstexter är dolda.") }
        if !hidden.isEmpty {
            items.insert(("Anonymisering", hidden.joined(separator: " ")), at: 1)
        }
        let blocks = items.map { heading, body in
            ReportBlock {
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ReportPalette.textPrimary)
                    Text(body)
                        .font(.system(size: 9.5))
                        .foregroundStyle(ReportPalette.textSecondary)
                        .lineSpacing(2)
                }
            }
        }
        return ReportSection(title: "Metod", blocks: blocks)
    }

    // MARK: Table cells

    private func cell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .center,
        weight: Font.Weight = .regular,
        size: CGFloat = 9,
        lines: Int = 1,
        color: Color = ReportPalette.textPrimary
    ) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .lineLimit(lines)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
            .padding(.horizontal, alignment == .leading ? 6 : 2)
            .frame(width: width, alignment: alignment)
    }

    private func scoreCell(_ score: Int?, width: CGFloat, weight: Font.Weight = .semibold) -> some View {
        Group {
            if let score {
                cell("\(score)", width: width, weight: weight,
                     color: ReportPalette.level(ScoringService.level(for: score)))
            } else {
                cell(ReportFormat.noData, width: width, size: 8, color: ReportPalette.textTertiary)
            }
        }
    }

    private func deltaCell(_ value: Int?, width: CGFloat, size: CGFloat = 9, weight: Font.Weight = .regular) -> some View {
        Group {
            if let value {
                cell(ReportFormat.delta(value), width: width, weight: weight, size: size, color: ReportFormat.deltaColor(value))
            } else {
                cell(ReportFormat.noData, width: width, size: 8, color: ReportPalette.textTertiary)
            }
        }
    }

    private func columnHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 7.5, weight: .semibold))
            .tracking(1)
            .foregroundStyle(ReportPalette.textTertiary)
    }
}

// MARK: - Small pieces

private struct TableRow<Content: View>: View {
    let height: CGFloat
    var background: Color = .clear
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .frame(width: ReportLayout.contentWidth, height: height, alignment: .leading)
            .background(background)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ReportPalette.hairline).frame(height: 0.5)
            }
    }
}

private struct SubHeading: View {
    let text: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ReportPalette.textPrimary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(ReportPalette.textTertiary)
            }
        }
    }
}

private struct FigureTile: View {
    let title: String
    let value: String
    let detail: String?
    var valueColor: Color = ReportPalette.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 7, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(ReportPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
            Text(detail ?? " ")
                .font(.system(size: 8))
                .foregroundStyle(ReportPalette.textSecondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(ReportPalette.surface)
    }
}

private struct NoticeBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle().fill(ReportPalette.note).frame(width: 3)
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ReportPalette.textPrimary)
                .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(ReportPalette.surface)
    }
}

private struct NoDataBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(ReportPalette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(ReportPalette.surface)
    }
}

private struct MutedLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(ReportPalette.textTertiary)
    }
}
