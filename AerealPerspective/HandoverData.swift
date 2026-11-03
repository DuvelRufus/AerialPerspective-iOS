//
//  HandoverData.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-11-03.
//

import Foundation

// Plain data and pure logic for the internal handover export ("Överlämning").
// Foundation only: no networking, no UI framework, no views, no I/O. A later
// loader fills these types; a later renderer and the CSV encoder read them.
//
// The types carry only what the handover shows: team names, scores, open
// task titles with state/domain/created date, the active plan, and insight
// title/domain/risk level/suggested action. There is deliberately no switch
// that hides names or texts, and nothing below team level.

// MARK: - Document

struct HandoverData {
    let generatedAt: Date
    /// How many teams the user asked for. A team that failed to load is still
    /// in `teams` (as .failed), so a shortfall here means a team went missing.
    let requestedCount: Int
    /// Ordered by team name, see HandoverOrdering.
    let teams: [HandoverTeam]

    init(generatedAt: Date, requestedCount: Int, teams: [HandoverTeam]) {
        self.generatedAt = generatedAt
        self.requestedCount = requestedCount
        self.teams = teams.sorted { HandoverOrdering.teamPrecedes($0, $1) }
    }

    var loadedCount: Int {
        teams.filter { if case .loaded = $0.outcome { return true } else { return false } }.count
    }

    var failedCount: Int { teams.count - loadedCount }

    /// True only when every requested team is present AND loaded. The
    /// document and the CSV may claim completeness only when this holds.
    var isComplete: Bool { failedCount == 0 && teams.count == requestedCount }
}

struct HandoverTeam: Identifiable {
    let projectId: UUID
    let name: String
    /// The project template's display label per domain.
    let domainLabels: [Domain: String]
    let outcome: HandoverOutcome

    var id: UUID { projectId }

    func label(_ domain: Domain) -> String {
        domainLabels[domain] ?? domain.rawValue
    }
}

enum HandoverOutcome {
    case loaded(HandoverTeamData)
    /// The team's data could not be loaded. `reason` is a short Swedish
    /// sentence for the document, never a raw error dump.
    case failed(reason: String)
}

// MARK: - Team data

struct HandoverTeamData {
    /// Latest COMPLETED assessment; nil = none completed.
    let latest: HandoverScoreSet?
    /// The completed assessment before `latest`; nil with fewer than two.
    let previous: HandoverScoreSet?
    let completedCount: Int
    let incompleteCount: Int

    /// Version of the assessment the insights belong to (the latest completed).
    let insightsSourceVersion: Int?
    let insights: [HandoverInsight]

    /// The active plan; nil = no active plan (a state, not a failure).
    let plan: HandoverPlan?
    /// Open tasks not placed under a plan item.
    let otherActions: [HandoverOtherAction]
    /// Every open task once, in handover order. For the CSV and for counts.
    let openActions: [HandoverOpenEntry]
    let openCounts: HandoverOpenCounts
    /// Done tasks seen while linking. Their titles are not kept anywhere.
    let doneActionCount: Int

    /// Latest versus the previous COMPLETED assessment, never the first.
    var delta: HandoverDelta? {
        guard let latest, let previous else { return nil }
        return HandoverDelta.compute(latest: latest, previous: previous)
    }

    var scoresVersion: Int? { latest?.version }
    var planVersion: Int? { plan?.sourceVersion }

    /// The scores, insights and plan come from different assessments. The
    /// document says so, because PlanStore-style precedence (newest
    /// assessment with an active plan) can differ from the latest completed.
    var versionsDiffer: Bool {
        Set([scoresVersion, insightsSourceVersion, planVersion].compactMap { $0 }).count > 1
    }
}

// MARK: - Scores

struct HandoverScoreSet {
    let version: Int
    /// assessments.created_at; there is no completion timestamp.
    let date: Date
    let total: Int
    let domainScores: [Domain: Int]
    let levels: [Domain: ScoreLevel]

    /// nil = no data. A stored domain score of 0 only arises when nothing in
    /// the domain was scored, so it is shown as "ingen data".
    func score(for domain: Domain) -> Int? {
        guard let score = domainScores[domain], score > 0 else { return nil }
        return score
    }

    func level(for domain: Domain) -> ScoreLevel? {
        score(for: domain) == nil ? nil : levels[domain]
    }
}

extension HandoverScoreSet {
    /// From ScoringService output; total and levels are ScoringService's own.
    init(version: Int, date: Date, scores: [DomainScore]) {
        self.init(
            version: version,
            date: date,
            total: ScoringService.total(scores),
            domainScores: Dictionary(scores.map { ($0.domain, $0.score) }, uniquingKeysWith: { _, last in last }),
            levels: Dictionary(scores.map { ($0.domain, $0.level) }, uniquingKeysWith: { _, last in last })
        )
    }
}

struct HandoverDelta: Equatable {
    let fromVersion: Int
    let toVersion: Int
    /// nil when either total is 0 (no data on that side).
    let total: Int?
    /// Only domains where BOTH sides have data (score > 0).
    let perDomain: [Domain: Int]

    static func compute(latest: HandoverScoreSet, previous: HandoverScoreSet) -> HandoverDelta {
        var perDomain: [Domain: Int] = [:]
        for domain in Domain.allCases {
            if let now = latest.score(for: domain), let before = previous.score(for: domain) {
                perDomain[domain] = now - before
            }
        }
        let total: Int? = (latest.total > 0 && previous.total > 0) ? latest.total - previous.total : nil
        return HandoverDelta(
            fromVersion: previous.version,
            toVersion: latest.version,
            total: total,
            perDomain: perDomain
        )
    }
}

// MARK: - Insights

/// Title, domain, risk level and suggested action only. There is no body
/// text field on purpose.
struct HandoverInsight {
    let title: String?
    let domain: String?
    /// Raw insights.risk_level; String so an unexpected value cannot fail.
    let riskLevel: String?
    let suggestedAction: String?
}

// MARK: - Tasks

/// The open task states, in handover sort order (rawValue = rank).
enum HandoverActionState: Int, CaseIterable {
    case prio = 0, doing = 1, waiting = 2, open = 3

    var label: String {
        switch self {
        case .prio:    return "prio"
        case .doing:   return "pågår"
        case .waiting: return "väntar"
        case .open:    return "öppen"
        }
    }

    struct Classification: Equatable {
        /// nil = the task is done.
        let state: HandoverActionState?
        /// The DB value matched none of the five known states.
        let wasUnknown: Bool
    }

    /// Exact match like TaskState(rawValue:); an unknown value counts as open.
    static func classify(_ raw: String) -> Classification {
        switch raw {
        case "prio":    return Classification(state: .prio, wasUnknown: false)
        case "doing":   return Classification(state: .doing, wasUnknown: false)
        case "waiting": return Classification(state: .waiting, wasUnknown: false)
        case "open":    return Classification(state: .open, wasUnknown: false)
        case "done":    return Classification(state: nil, wasUnknown: false)
        default:        return Classification(state: .open, wasUnknown: true)
        }
    }
}

enum HandoverActionSource {
    case plan, insight, own

    var label: String {
        switch self {
        case .plan:    return "Plan"
        case .insight: return "Insikt"
        case .own:     return "Egen"
        }
    }
}

/// A row as the loader reads it from `actions`. Done rows are included
/// only so plan items can show "klar"; the linking step drops their titles.
struct HandoverActionRow {
    let id: UUID
    let title: String
    let domain: String
    let state: String
    let createdAt: Date
    let planActionId: UUID?
    let insightId: UUID?
}

/// An OPEN task. The type cannot hold a done task.
struct HandoverAction: Identifiable {
    let id: UUID
    let title: String
    /// Raw actions.domain; may match no Domain.
    let domain: String
    let state: HandoverActionState
    let stateWasUnknown: Bool
    let createdAt: Date
    let planActionId: UUID?
    let insightId: UUID?

    /// The plan link wins over the insight link, as ProjectAction.origin.
    var source: HandoverActionSource {
        if planActionId != nil { return .plan }
        if insightId != nil { return .insight }
        return .own
    }

    var domainKey: Domain? { Domain(caseInsensitive: domain) }
}

/// An open task listed outside the plan items.
struct HandoverOtherAction: Identifiable {
    let action: HandoverAction
    /// plan_action_id is set but names no item of the active plan (or there
    /// is no active plan). Listed anyway, never dropped.
    let orphanLink: Bool

    var id: UUID { action.id }
}

/// One open task with where it sits, for the CSV.
struct HandoverOpenEntry: Identifiable {
    let action: HandoverAction
    /// plan_actions.phase of the item it is attached to; nil otherwise.
    let planPhase: String?
    let orphanLink: Bool

    var id: UUID { action.id }
}

struct HandoverOpenCounts: Equatable {
    var prio = 0
    var doing = 0
    var waiting = 0
    var open = 0
    /// Tasks with an unknown state value; also counted in `open`.
    var unknownState = 0

    var total: Int { prio + doing + waiting + open }

    mutating func add(_ action: HandoverAction) {
        switch action.state {
        case .prio:    prio += 1
        case .doing:   doing += 1
        case .waiting: waiting += 1
        case .open:    open += 1
        }
        if action.stateWasUnknown { unknownState += 1 }
    }
}

// MARK: - Plan

/// A plan_actions row as the loader reads it.
struct HandoverPlanItemRow {
    let id: UUID
    let phase: String
    let text: String
    let domain: String?
    let sortOrder: Int
}

struct HandoverPlan {
    /// Version of the assessment the active plan belongs to.
    let sourceVersion: Int
    let summary: String
    let focusDay1_30: String
    let focusDay31_60: String
    let focusDay61_90: String
    /// Phase order, then sort_order.
    let items: [HandoverPlanItem]

    func focus(forPhase phase: String) -> String? {
        switch phase {
        case "day1_30":  return focusDay1_30
        case "day31_60": return focusDay31_60
        case "day61_90": return focusDay61_90
        default:         return nil
        }
    }
}

struct HandoverPlanItem: Identifiable {
    let id: UUID
    let phase: String
    let text: String
    let domain: String?
    let sortOrder: Int
    /// Open tasks created from this item, in handover order. Several allowed.
    let openActions: [HandoverAction]
    /// Done tasks linked to this item; only the count is kept.
    let doneActionCount: Int

    var phaseLabel: String { HandoverPhase.label(phase) }

    var status: HandoverPlanItemStatus {
        if let first = openActions.first { return .open(first.state) }
        if doneActionCount > 0 { return .done }
        return .notStarted
    }
}

enum HandoverPlanItemStatus: Equatable {
    /// No task exists for the item.
    case notStarted
    /// At least one open task; carries the most urgent state among them.
    case open(HandoverActionState)
    /// Tasks exist and every one is done. Never shown as "ej påbörjad".
    case done

    var label: String {
        switch self {
        case .notStarted:     return "ej påbörjad"
        case .open(let state): return state.label
        case .done:           return "klar"
        }
    }
}

/// Mirrors PlanView.phaseIndex / phaseLabel.
enum HandoverPhase {
    static func index(_ phase: String) -> Int {
        switch phase {
        case "day1_30":  return 0
        case "day31_60": return 1
        case "day61_90": return 2
        default:         return 3   // unknown phase sorts last instead of failing
        }
    }

    static func label(_ phase: String) -> String {
        switch phase {
        case "day1_30":  return "Dag 1–30"
        case "day31_60": return "Dag 31–60"
        case "day61_90": return "Dag 61–90"
        default:         return phase
        }
    }
}

// MARK: - Ordering

enum HandoverOrdering {
    /// State rank (prio, doing, waiting, open), then oldest created first,
    /// then id for a stable result. Deliberately not by domain score.
    static func actionPrecedes(_ a: HandoverAction, _ b: HandoverAction) -> Bool {
        if a.state != b.state { return a.state.rawValue < b.state.rawValue }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// Alphabetical by name, then id.
    static func teamPrecedes(_ a: HandoverTeam, _ b: HandoverTeam) -> Bool {
        switch a.name.localizedStandardCompare(b.name) {
        case .orderedAscending:  return true
        case .orderedDescending: return false
        case .orderedSame:       return a.projectId.uuidString < b.projectId.uuidString
        }
    }

    static func planRowPrecedes(_ a: HandoverPlanItemRow, _ b: HandoverPlanItemRow) -> Bool {
        let ai = HandoverPhase.index(a.phase)
        let bi = HandoverPhase.index(b.phase)
        if ai != bi { return ai < bi }
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        return a.id.uuidString < b.id.uuidString
    }
}

// MARK: - Linking

/// Places a team's tasks against its active plan, the same way PlanView
/// does: a task linked to a plan item belongs to that item and is not
/// listed a second time.
enum HandoverLinking {
    struct Result {
        let items: [HandoverPlanItem]
        let otherActions: [HandoverOtherAction]
        let openActions: [HandoverOpenEntry]
        let openCounts: HandoverOpenCounts
        let doneActionCount: Int
    }

    /// - A done task is counted (and counted on its plan item) but its
    ///   title is dropped here and appears in no output type.
    /// - An open task linked to an item of `planRows` is attached to that
    ///   item; several per item are allowed.
    /// - An open task whose plan_action_id names no item (or when
    ///   `planRows` is empty) goes to `otherActions` with orphanLink = true.
    /// - Every other open task goes to `otherActions` with orphanLink = false.
    /// - Nothing open is dropped: items' open tasks + otherActions ==
    ///   openActions == openCounts.total.
    static func link(planRows: [HandoverPlanItemRow], actionRows: [HandoverActionRow]) -> Result {
        let ordered = planRows.sorted { HandoverOrdering.planRowPrecedes($0, $1) }
        // First row wins if an id repeats.
        var indexById: [UUID: Int] = [:]
        for (i, row) in ordered.enumerated() where indexById[row.id] == nil {
            indexById[row.id] = i
        }

        var openByItem = [[HandoverAction]](repeating: [], count: ordered.count)
        var doneByItem = [Int](repeating: 0, count: ordered.count)
        var others: [HandoverOtherAction] = []
        var counts = HandoverOpenCounts()
        var doneTotal = 0

        for row in actionRows {
            let kind = HandoverActionState.classify(row.state)
            guard let state = kind.state else {
                doneTotal += 1
                if let planId = row.planActionId, let i = indexById[planId] {
                    doneByItem[i] += 1
                }
                continue   // the done task's title ends here
            }
            let action = HandoverAction(
                id: row.id,
                title: row.title,
                domain: row.domain,
                state: state,
                stateWasUnknown: kind.wasUnknown,
                createdAt: row.createdAt,
                planActionId: row.planActionId,
                insightId: row.insightId
            )
            counts.add(action)
            if let planId = row.planActionId {
                if let i = indexById[planId] {
                    openByItem[i].append(action)
                } else {
                    others.append(HandoverOtherAction(action: action, orphanLink: true))
                }
            } else {
                others.append(HandoverOtherAction(action: action, orphanLink: false))
            }
        }

        let items = ordered.enumerated().map { i, row in
            HandoverPlanItem(
                id: row.id,
                phase: row.phase,
                text: row.text,
                domain: row.domain,
                sortOrder: row.sortOrder,
                openActions: openByItem[i].sorted { HandoverOrdering.actionPrecedes($0, $1) },
                doneActionCount: doneByItem[i]
            )
        }
        let sortedOthers = others.sorted { HandoverOrdering.actionPrecedes($0.action, $1.action) }

        let entries = (
            items.flatMap { item in
                item.openActions.map { HandoverOpenEntry(action: $0, planPhase: item.phase, orphanLink: false) }
            }
            + sortedOthers.map { HandoverOpenEntry(action: $0.action, planPhase: nil, orphanLink: $0.orphanLink) }
        ).sorted { HandoverOrdering.actionPrecedes($0.action, $1.action) }

        return Result(
            items: items,
            otherActions: sortedOthers,
            openActions: entries,
            openCounts: counts,
            doneActionCount: doneTotal
        )
    }
}
