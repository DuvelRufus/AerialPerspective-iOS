//
//  HandoverMarkdown.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-11-03.
//

import Foundation

// Markdown export of a handover ("Överlämning"): an overview table, one
// section per team with scores and open tasks, the teams that could not be
// loaded, and a short "Om dokumentet". Pure Foundation: no networking, no UI
// framework, no stores. Input is a HandoverData and nothing else, so done
// tasks, insight texts, plan texts, answers and respondents cannot reach the
// file. Insights and plan texts are deliberately not part of this version.
//
// The text is meant to be pasted into GitHub issues and similar tools, so
// every text that comes from the data (team name, task title, domain label,
// phase) goes through `escaped`:
//
// - Markdown-significant characters get a backslash: \ ` * _ [ ] ~, plus "|"
//   in table cells, a leading "-" or "+", the "." or ")" of a leading
//   "1." / "1)", and a "#" at the start or after a space (a "#" there would
//   start a heading, or be taken for a closing sequence in a heading).
// - < > & become &lt; &gt; &amp;, so a title cannot inject HTML.
// - Line breaks (and tabs and other control characters) become one space and
//   the text is trimmed. The original line breaks of a title are therefore
//   NOT recoverable from the file; "Om dokumentet" says so.
// - Mentions and issue references: see `autolinkPattern`.
//
// The file is UTF-8 without BOM, LF line endings, ends with one LF.
enum HandoverMarkdown {

    /// Same temporary folder as HandoverCSV. Each writer removes the other
    /// entries in it, so only the latest export (of either kind) is kept.
    static let folderName = "Handover"

    // MARK: - Encoding

    static func encode(_ data: HandoverData, timeZone: TimeZone = .current) -> String {
        let dates = DateFormats(timeZone: timeZone)
        var blocks: [String] = []

        // a. Header
        blocks.append("# Överlämning")
        blocks.append("Intern. Innehåller projektnamn och åtgärdstexter. Ej anonymiserad.")
        blocks.append("Skapad: \(dates.dateTime(data.generatedAt))")
        blocks.append(completenessLine(data))

        // b. Overview
        blocks.append("## Översikt")
        blocks.append(overviewTable(data, dates: dates))

        // c. One section per loaded team
        for team in data.teams {
            if case .loaded(let teamData) = team.outcome {
                blocks.append(contentsOf: teamSection(team, teamData, dates: dates))
            }
        }

        // d. Teams that failed
        let failed = data.teams.compactMap { team -> String? in
            if case .failed(let reason) = team.outcome {
                return "- \(escaped(team.name)): \(escaped(reason))"
            }
            return nil
        }
        if !failed.isEmpty {
            blocks.append("## Team som inte kunde hämtas")
            blocks.append(failed.joined(separator: "\n"))
        }

        // e. About
        blocks.append("## Om dokumentet")
        blocks.append(aboutList())

        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func completenessLine(_ data: HandoverData) -> String {
        if data.isComplete {
            return "Fullständig: \(data.loadedCount) av \(data.requestedCount) team hämtade."
        }
        let missing = data.requestedCount - data.loadedCount
        let names = data.teams.compactMap { team -> String? in
            if case .failed = team.outcome { return escaped(team.name) }
            return nil
        }
        let list = names.isEmpty ? "" : " " + names.joined(separator: ", ")
        return "OFULLSTÄNDIG: \(missing) av \(data.requestedCount) team saknas:\(list)"
    }

    // MARK: Overview

    private static func overviewTable(_ data: HandoverData, dates: DateFormats) -> String {
        var lines = [
            "| Team | Total | Förändring | Poäng (version, datum) | Öppna (prio / pågår / väntar / öppen) | Ej slutförda assessments |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for team in data.teams {
            let name = escaped(team.name, inTable: true)
            switch team.outcome {
            case .failed:
                lines.append("| \(name) | Data saknas | – | – | – | – |")
            case .loaded(let d):
                let total = d.latest.flatMap { $0.total > 0 ? String($0.total) : nil } ?? "ingen data"
                let change = d.delta?.total.map { signed($0) } ?? "–"
                let score = d.latest.map { "v\($0.version), \(dates.date($0.date))" } ?? "Inget slutfört"
                let c = d.openCounts
                lines.append("| \(name) | \(total) | \(change) | \(score) | \(c.prio) / \(c.doing) / \(c.waiting) / \(c.open) | \(d.incompleteCount) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Team section

    private static func teamSection(_ team: HandoverTeam, _ d: HandoverTeamData, dates: DateFormats) -> [String] {
        var blocks: [String] = ["## \(escaped(team.name))"]

        let score = d.latest.map { "poäng v\($0.version) (\(dates.date($0.date)))" } ?? "poäng saknas"
        let insights = d.insightsSourceVersion.map { "insikter v\($0)" } ?? "insikter saknas"
        let plan = d.planVersion.map { "plan v\($0)" } ?? "ingen aktiv plan"
        blocks.append("Underlag: \(score), \(insights), \(plan)")
        if d.versionsDiffer {
            blocks.append("Obs: underlagen kommer från olika versioner. Poäng och insikter hör till den senaste slutförda assessmenten, planen till den nyaste assessment som har en aktiv plan.")
        }
        blocks.append("Assessments: \(d.completedCount) slutförda, \(d.incompleteCount) ej slutförda.")

        if let latest = d.latest {
            blocks.append(scoreTable(team, latest: latest, delta: d.delta))
            if let previous = d.previous {
                blocks.append("Förändring avser v\(latest.version) jämfört med v\(previous.version), den föregående slutförda assessmenten.")
            } else {
                blocks.append("Förändring saknas: det finns ingen tidigare slutförd assessment att jämföra med.")
            }
        } else {
            blocks.append("Ingen slutförd assessment ännu, därför finns inga poäng.")
        }

        blocks.append("### Öppna åtgärder")
        blocks.append(contentsOf: openActionBlocks(team, d, dates: dates))
        return blocks
    }

    private static func scoreTable(_ team: HandoverTeam, latest: HandoverScoreSet, delta: HandoverDelta?) -> String {
        var lines = ["| Domän | Poäng | Förändring | Nivå |", "| --- | --- | --- | --- |"]
        for domain in Domain.allCases {
            let label = escaped(team.label(domain), inTable: true)
            let score = latest.score(for: domain).map(String.init) ?? "ingen data"
            let change = delta?.perDomain[domain].map { signed($0) } ?? "–"
            let level = latest.level(for: domain).map { levelWord($0) } ?? "–"
            lines.append("| \(label) | \(score) | \(change) | \(level) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Same words as the result screen.
    private static func levelWord(_ level: ScoreLevel) -> String {
        switch level {
        case .risk:   return "Risk"
        case .note:   return "Bevaka"
        case .strong: return "Starkt"
        }
    }

    /// "+3", "0", "-7".
    private static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }

    // MARK: Open tasks

    /// Prio, Pågår, Väntar, Öppen, each only when it has tasks. The order
    /// inside a status is HandoverOrdering.actionPrecedes (oldest created
    /// first); `openActions` already holds it and sorting again with the same
    /// comparator keeps the file right if a HandoverTeamData was built in
    /// another order. Done tasks cannot appear: HandoverAction cannot hold one.
    private static func openActionBlocks(_ team: HandoverTeam, _ d: HandoverTeamData, dates: DateFormats) -> [String] {
        let entries = d.openActions.sorted { HandoverOrdering.actionPrecedes($0.action, $1.action) }
        if entries.isEmpty { return ["Inga öppna åtgärder."] }

        var blocks: [String] = []
        for state in HandoverActionState.allCases {
            let items = entries.filter { $0.action.state == state }.map { entry -> String in
                let action = entry.action
                var details = [domainLabel(action, team: team), "skapad \(dates.date(action.createdAt))"]
                if let phase = entry.planPhase {
                    details.append(escaped(HandoverPhase.label(phase)))
                } else if entry.orphanLink {
                    details.append("ej i aktiv plan")
                }
                return "- [ ] \(titleText(action.title)) (\(details.joined(separator: ", ")))"
            }
            if items.isEmpty { continue }
            blocks.append("#### \(statusHeading(state))")
            blocks.append(items.joined(separator: "\n"))
        }
        return blocks
    }

    private static func statusHeading(_ state: HandoverActionState) -> String {
        switch state {
        case .prio:    return "Prio"
        case .doing:   return "Pågår"
        case .waiting: return "Väntar"
        case .open:    return "Öppen"
        }
    }

    /// The team's own template label; a domain the table lacks falls back to
    /// the raw key, and a value that is no domain is written as stored.
    private static func domainLabel(_ action: HandoverAction, team: HandoverTeam) -> String {
        let raw = action.domainKey.map { team.label($0) } ?? action.domain
        let text = escaped(raw)
        return text.isEmpty ? "ingen domän" : text
    }

    private static func titleText(_ title: String) -> String {
        let text = escaped(title)
        return text.isEmpty ? "(utan titel)" : text
    }

    // MARK: About

    private static func aboutList() -> String {
        [
            "- Förändring: senaste slutförda assessment jämfört med den slutförda assessment som kommer närmast före. Saknas någon av dem, eller saknar något av dem data, visas \"–\".",
            "- \"ingen data\": poängen är 0, alltså har inget i området besvarats och poängsatts.",
            "- En åtgärd med okänd status räknas som öppen.",
            "- Underlag per team: poäng och insikternas version hör till den senaste slutförda assessmenten; planens version hör till den nyaste assessment som har en aktiv plan. Versionerna anges per team, och en extra rad visar när de skiljer sig åt.",
            "- Ingår inte: kontakter, anteckningar, länkar, svar, insiktstexter, plantexter och avklarade åtgärder. Insikter och plan finns bara som versionsnummer.",
            "- Radbrytningar och tabbar i åtgärdstitlar och namn har ersatts med ett blanksteg och texten är trimmad. Den ursprungliga titeln kan därför inte återskapas ur filen.",
            "- Markdown-tecken i titlar och namn är skyddade med bakstreck eller HTML-tecken (&lt; &gt; &amp;) så att listor och tabeller inte kan brytas. Omnämnanden (`@namn`) och ärendereferenser (`#123`) står i kodformat så att de inte blir länkar eller notiser när texten klistras in.",
            "- En åtgärd som saknar titel visas som (utan titel).",
        ].joined(separator: "\n")
    }

    // MARK: - Escaping

    /// @name, @org/team, #123, owner/repo#123 and GH-123: the forms GitHub
    /// turns into a mention (a notification to a real person) or an issue
    /// reference when text is pasted into an issue or comment. Preceded by a
    /// letter, digit or underscore it is not one (an e-mail address, "C#1"),
    /// which is why the lookbehind is there.
    ///
    /// Technique: such a token is written as an inline code span, `@name`.
    /// GitHub does not link inside code, the token stays one unbroken piece
    /// of text (no zero-width characters, so a search for "@name" in the file
    /// or in the rendered page still finds it), and it needs no characters
    /// that a backslash or an entity would have to hide. Backslash escapes
    /// and entities were rejected: GitHub looks for mentions in the rendered
    /// text, where both have already turned back into a plain "@name".
    /// Verified in a GitHub issue body on 2026-11-03: task list items render as
    /// checkboxes, @mentions and #refs in code spans stay plain code, &lt; &gt;
    /// &amp; render as visible text, and \| in a table cell is one cell with "|".
    private static let autolinkPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])(?:@[A-Za-z0-9][A-Za-z0-9_-]*(?:/[A-Za-z0-9_.-]+)?|(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+|GH-[0-9]+)"#
    )

    /// Text from the data, made safe to put in a list item, heading or (with
    /// `inTable`) a table cell. See the file comment.
    static func escaped(_ text: String, inTable: Bool = false) -> String {
        let flat = singleLine(text)

        // Split into plain runs and protected tokens.
        var segments: [(text: String, isToken: Bool)] = []
        var cursor = flat.startIndex
        let whole = NSRange(flat.startIndex..., in: flat)
        for match in autolinkPattern.matches(in: flat, range: whole) {
            guard let range = Range(match.range, in: flat) else { continue }
            if range.lowerBound > cursor { segments.append((String(flat[cursor..<range.lowerBound]), false)) }
            segments.append((String(flat[range]), true))
            cursor = range.upperBound
        }
        if cursor < flat.endIndex { segments.append((String(flat[cursor...]), false)) }

        var out = String.UnicodeScalarView()
        var previous: Unicode.Scalar? = nil   // last raw scalar written so far
        for (index, segment) in segments.enumerated() {
            if segment.isToken {
                out.append(contentsOf: "`".unicodeScalars)
                out.append(contentsOf: segment.text.unicodeScalars)
                out.append(contentsOf: "`".unicodeScalars)
                previous = segment.text.unicodeScalars.last
                continue
            }
            let scalars = Array(segment.text.unicodeScalars)
            // "1." / "1)" at the very start would make an ordered list.
            var markerAt: Int? = nil
            if index == 0 {
                var digits = 0
                while digits < scalars.count, digits < 9, ("0"..."9").contains(scalars[digits]) { digits += 1 }
                if digits > 0, digits < scalars.count, scalars[digits] == "." || scalars[digits] == ")" {
                    markerAt = digits
                }
            }
            for (i, scalar) in scalars.enumerated() {
                let atStart = previous == nil
                switch scalar {
                case "\\", "`", "*", "_", "[", "]", "~":
                    out.append("\\"); out.append(scalar)
                case "<": out.append(contentsOf: "&lt;".unicodeScalars)
                case ">": out.append(contentsOf: "&gt;".unicodeScalars)
                case "&": out.append(contentsOf: "&amp;".unicodeScalars)
                case "|":
                    if inTable { out.append("\\") }
                    out.append(scalar)
                case "-", "+":
                    if atStart { out.append("\\") }
                    out.append(scalar)
                case "#":
                    if atStart || previous == " " { out.append("\\") }
                    out.append(scalar)
                case ".", ")":
                    if i == markerAt { out.append("\\") }
                    out.append(scalar)
                default:
                    out.append(scalar)
                }
                previous = scalar
            }
        }
        return String(out)
    }

    /// Line breaks, tabs and other control characters become one space (a run
    /// of them becomes a single space); leading and trailing spaces go.
    static func singleLine(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var inBreakRun = false
        for scalar in text.unicodeScalars {
            let isBreak = scalar.properties.generalCategory == .control
                || scalar == "\u{2028}" || scalar == "\u{2029}"
            if isBreak {
                if !inBreakRun { out.append(" ") }
                inBreakRun = true
            } else {
                inBreakRun = false
                out.append(scalar)
            }
        }
        var result = String(out)
        while result.first == " " { result.removeFirst() }
        while result.last == " " { result.removeLast() }
        return result
    }

    // MARK: - Dates and file name

    private struct DateFormats {
        private let dayFormatter: DateFormatter
        private let minuteFormatter: DateFormatter
        private let stampFormatter: DateFormatter

        init(timeZone: TimeZone) {
            func make(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                // Fixed gregorian calendar and POSIX locale: the device's
                // calendar setting must not change the year or the digits.
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = format
                return formatter
            }
            dayFormatter = make("yyyy-MM-dd")
            minuteFormatter = make("yyyy-MM-dd HH:mm")
            stampFormatter = make("yyyy-MM-dd-HHmm")
        }

        func date(_ value: Date) -> String { dayFormatter.string(from: value) }
        func dateTime(_ value: Date) -> String { minuteFormatter.string(from: value) }
        /// Date and time for file names: no colon, no space.
        func fileStamp(_ value: Date) -> String { stampFormatter.string(from: value) }
    }

    /// "Överlämning-<yyyy-MM-dd>-<HHmm>.md", date and time in `timeZone` (the
    /// local one by default, not UTC). Same Date and zone as the "Skapad" line,
    /// so the name and the document always agree; two exports in different
    /// minutes get different names.
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        "Överlämning-\(DateFormats(timeZone: timeZone).fileStamp(date)).md"
    }

    // MARK: - Writing

    /// Writes the document to `<baseDirectory>/Handover/Överlämning-<yyyy-MM-dd>-<HHmm>.md`
    /// and returns its URL (the name uses `data.generatedAt`). UTF-8, no BOM,
    /// LF, complete file protection. The file is written first, then every
    /// other item in the Handover folder is removed, so exporting twice (also
    /// on different days) leaves one file and a failed write does not delete
    /// the previous export. Nothing outside the Handover folder is touched.
    @discardableResult
    static func write(
        _ data: HandoverData,
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        timeZone: TimeZone = .current
    ) throws -> URL {
        let fileManager = FileManager.default
        let folder = baseDirectory.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let name = fileName(for: data.generatedAt, timeZone: timeZone)
        let url = folder.appendingPathComponent(name, isDirectory: false)
        try Data(encode(data, timeZone: timeZone).utf8).write(to: url, options: [.atomic, .completeFileProtection])

        // macOS stores the name decomposed (Ö as O + diaeresis), so compare
        // by canonical equivalence, not by bytes.
        let keep = name.precomposedStringWithCanonicalMapping
        let items = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for item in items where item.lastPathComponent.precomposedStringWithCanonicalMapping != keep {
            try? fileManager.removeItem(at: item)
        }
        return url
    }
}
