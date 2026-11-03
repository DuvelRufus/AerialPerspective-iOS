//
//  HandoverCSV.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-11-03.
//

import Foundation

// CSV export of the open tasks in a handover ("Överlämning").
// Pure Foundation: no networking, no UI framework, no stores. Input is a
// HandoverData and nothing else, so nothing outside it (done-task titles,
// insight text, scores, respondents) can reach the file. Output is UTF-8
// Data; `write` puts it in a temporary folder of its own.
//
// File format:
// - UTF-8 with a BOM (EF BB BF) so Excel does not read å/ä/ö as Latin-1.
// - CRLF after every record, including the last: the file ends with exactly
//   one CRLF.
// - Every field is quoted and a double quote inside a field is doubled. Line
//   breaks inside a field are kept as they are, inside the quotes.
// - The delimiter is a semicolon by default. Excel with a Swedish regional
//   setting uses the comma as decimal separator and therefore ";" as list
//   separator, so a comma-separated file opens as a single column there.
//
// Formula injection: a spreadsheet may run a cell as a formula when its text
// starts with =, +, - or @ (or with a tab or carriage return). Any field whose
// first non-blank character is one of those, or which starts with a tab or a
// carriage return, gets an apostrophe in front. Trade-off: some spreadsheet
// programs show the apostrophe literally, so a title like "-5 dagar" appears
// as "'-5 dagar". We accept that over letting a task title run as a formula.
enum HandoverCSV {

    /// Semicolon: see the note on Swedish Excel above.
    static let defaultDelimiter = ";"

    /// Column order of the file.
    static let header = ["Team", "Titel", "Domän", "Status", "Skapad", "Källa", "Planfas"]

    /// The one row a team that failed to load gets.
    static let failedTeamTitle = "DATA SAKNAS – teamet kunde inte hämtas"

    /// Planfas for a task whose plan_action_id names no item of the active plan.
    static let orphanPhase = "ej i aktiv plan"

    /// Folder (inside the base directory) that holds the exported file. Only
    /// this folder is ever cleaned, never the folder the PDF report uses.
    static let folderName = "Handover"

    static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    // MARK: - Encoding

    /// The whole file: BOM, header, then one row per open task of every loaded
    /// team and one row per failed team. Dates are written in `timeZone`.
    static func encode(
        _ data: HandoverData,
        delimiter: String = HandoverCSV.defaultDelimiter,
        timeZone: TimeZone = .current
    ) -> Data {
        precondition(
            !delimiter.isEmpty && delimiter.unicodeScalars.allSatisfy { $0 != "\"" && $0 != "\r" && $0 != "\n" },
            "The delimiter must be non-empty and contain no quote or line break"
        )
        var text = ""
        for record in [header] + rows(data, timeZone: timeZone) {
            text += record.map { field($0) }.joined(separator: delimiter)
            text += "\r\n"
        }
        return byteOrderMark + Data(text.utf8)
    }

    /// The data rows as plain text, before quoting and formula protection.
    /// Team order is the document's. Within a team the order is that of
    /// HandoverOrdering.actionPrecedes: prio, pågår, väntar, öppen, oldest
    /// created first. `openActions` already holds that order; sorting again
    /// with the same comparator keeps the file right even if a HandoverTeamData
    /// was built with its entries in another order. Done tasks cannot appear:
    /// HandoverAction cannot represent one.
    static func rows(_ data: HandoverData, timeZone: TimeZone = .current) -> [[String]] {
        let dates = dateFormatter(timeZone: timeZone)
        var result: [[String]] = []
        for team in data.teams {
            switch team.outcome {
            case .failed:
                result.append([team.name, failedTeamTitle, "", "", "", "", ""])
            case .loaded(let teamData):
                let entries = teamData.openActions.sorted { HandoverOrdering.actionPrecedes($0.action, $1.action) }
                for entry in entries {
                    let action = entry.action
                    result.append([
                        team.name,
                        action.title,
                        domainLabel(action, team: team),
                        action.state.label,
                        dates.string(from: action.createdAt),
                        action.source.label,
                        planPhase(entry),
                    ])
                }
            }
        }
        return result
    }

    /// The team's own template label, the wording the PDF uses. A domain the
    /// label table lacks falls back to the raw domain key; a value that is no
    /// domain at all is written as stored.
    private static func domainLabel(_ action: HandoverAction, team: HandoverTeam) -> String {
        guard let key = action.domainKey else { return action.domain }
        return team.label(key)
    }

    private static func planPhase(_ entry: HandoverOpenEntry) -> String {
        if let phase = entry.planPhase { return HandoverPhase.label(phase) }
        if entry.orphanLink { return orphanPhase }
        return ""
    }

    // MARK: - Fields

    /// One field: formula protection first, then quoting.
    static func field(_ text: String) -> String {
        quote(protectedFromFormula(text))
    }

    /// Prefixes an apostrophe when a spreadsheet could take the text for a
    /// formula; see the file comment. Works on unicode scalars, not
    /// Characters: "\r\n" is one Character and "=" plus a combining mark is
    /// another, and neither would match a Character comparison.
    static func protectedFromFormula(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.first else { return text }
        if first == "\t" || first == "\r" { return "'" + text }
        let blanks = CharacterSet.whitespacesAndNewlines
        guard let firstVisible = scalars.first(where: { !blanks.contains($0) }) else { return text }
        switch firstVisible {
        case "=", "+", "-", "@": return "'" + text
        default:                  return text
        }
    }

    /// Wraps in quotes and doubles every quote inside. Scalar by scalar,
    /// because a string search treats a quote followed by a combining mark as
    /// one unit and would miss it.
    static func quote(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        out.append("\"")
        for scalar in text.unicodeScalars {
            if scalar == "\"" { out.append("\"") }
            out.append(scalar)
        }
        out.append("\"")
        return String(out)
    }

    // MARK: - Dates and file name

    /// yyyy-MM-dd in `timeZone`. Fixed gregorian calendar and POSIX locale, so
    /// the device's calendar setting (Buddhist, Japanese) cannot change the year.
    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// "Åtgärder-<yyyy-MM-dd>.csv", the date in `timeZone` (the local one by
    /// default, not UTC).
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        "Åtgärder-\(dateFormatter(timeZone: timeZone).string(from: date)).csv"
    }

    // MARK: - Writing

    /// Writes the file to `<baseDirectory>/Handover/Åtgärder-<date>.csv` and
    /// returns its URL. The name uses `data.generatedAt`. Afterwards every
    /// other item in the Handover folder is removed, so exporting twice (also
    /// on different days) leaves one file. The file is written first, so a
    /// failed write does not delete the previous export. Nothing outside the
    /// Handover folder is touched.
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
        try encode(data, timeZone: timeZone).write(to: url, options: .atomic)

        // File systems may hand a name back in another Unicode normalization.
        let keep = name.precomposedStringWithCanonicalMapping
        let items = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for item in items where item.lastPathComponent.precomposedStringWithCanonicalMapping != keep {
            try? fileManager.removeItem(at: item)
        }
        return url
    }
}
