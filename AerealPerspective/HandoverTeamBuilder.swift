//
//  HandoverTeamBuilder.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-11-03.
//

import Foundation

// The pure half of the handover loader: no networking, no I/O, no stores.
// HandoverLoader reads rows from the backend and hands them to the functions
// here, so the rules (completeness, scores, plan precedence, template check,
// paging, failure categories) can be run without a backend.
//
// Scoring input (the per-assessment option picks) goes in and only scores come
// out: nothing in HandoverTeamData can hold it.

// MARK: - Failure categories

/// Why a team could not be loaded. `reason` is the short Swedish text the
/// document shows; the full error only goes to the console.
enum HandoverFailureKind: Equatable {
    case network
    case unexpectedResponse
    case templateMissing
    case noQuestions

    var reason: String {
        switch self {
        case .network:            return "nätverksfel"
        case .unexpectedResponse: return "oväntat svar"
        case .templateMissing:    return "mall saknas"
        case .noQuestions:        return "frågor saknas"
        }
    }

    /// nil = the error is a cancellation. The caller rethrows cancellation
    /// and never turns it into a failed team.
    static func classify(_ error: Error) -> HandoverFailureKind? {
        if error is CancellationError { return nil }
        if let failure = error as? HandoverTeamFailure { return failure.kind }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? nil : .network
        }
        // Decoding problems, read-consistency problems and anything the
        // server answered with an error are all "the response was not what
        // we expected".
        return .unexpectedResponse
    }
}

struct HandoverTeamFailure: Error {
    let kind: HandoverFailureKind
}

// MARK: - Reading rows safely

/// One page of a paged read. `total` is the server's exact row count for the
/// whole query (nil = the server did not say).
struct HandoverPage<Row> {
    let rows: [Row]
    let total: Int?
}

enum HandoverReadError: Error, Equatable, LocalizedError {
    /// The server did not report a total, so completeness cannot be shown.
    case totalUnknown
    /// A single (unpaged) query returned the server's row cap or more.
    case capped
    /// Received rows do not add up to the reported total, or the data
    /// changed or contradicted itself during the read.
    case inconsistent(String)

    var errorDescription: String? {
        "Svaret från servern var ofullständigt. Försök igen."
    }
}

enum HandoverPaging {
    /// PostgREST's default cap on rows per response.
    nonisolated static let pageSize = 1000

    /// For queries read in one request: exactly pageSize rows or more is an
    /// error (it may be a silent cap), and the rows must match the total.
    static func validateSingle(rowCount: Int, total: Int?) throws {
        if rowCount >= pageSize { throw HandoverReadError.capped }
        guard let total else { throw HandoverReadError.totalUnknown }
        if rowCount != total {
            throw HandoverReadError.inconsistent("received \(rowCount) of \(total) rows")
        }
    }

    /// Reads every row of an ordered query in windows [from, to] (inclusive,
    /// 0-based). Each window starts at the number of rows already collected,
    /// so windows never overlap and never leave a gap, even when the server
    /// returns fewer rows than asked for. This needs a TOTAL order on the
    /// query, or rows tied at a window edge can repeat or be skipped.
    /// Done when the collected count equals the server's total.
    static func collectAll<Row>(
        pageSize: Int = HandoverPaging.pageSize,
        fetchPage: (_ from: Int, _ to: Int) async throws -> HandoverPage<Row>
    ) async throws -> [Row] {
        precondition(pageSize > 0)
        var rows: [Row] = []
        var total: Int? = nil
        while true {
            try Task.checkCancellation()
            let from = rows.count
            let page = try await fetchPage(from, from + pageSize - 1)
            guard let pageTotal = page.total else { throw HandoverReadError.totalUnknown }
            if let known = total, known != pageTotal {
                throw HandoverReadError.inconsistent("total changed from \(known) to \(pageTotal) during the read")
            }
            total = pageTotal
            rows.append(contentsOf: page.rows)
            if rows.count == pageTotal { return rows }
            if rows.count > pageTotal {
                throw HandoverReadError.inconsistent("received \(rows.count) rows, total is \(pageTotal)")
            }
            if page.rows.isEmpty {
                throw HandoverReadError.inconsistent("empty window at \(from) of \(pageTotal)")
            }
        }
    }
}

// MARK: - Scoring input

/// One stored option pick, used only to score an assessment.
struct HandoverScoringRow {
    let assessmentId: UUID
    let questionId: UUID
    /// nil = unanswered; skipped, as the other loaders do.
    let optionId: UUID?
}

enum HandoverScoringIndex {
    /// assessmentId → [questionId: optionId]. The same pick twice is fine;
    /// two DIFFERENT picks for one question would make the score depend on
    /// read order, so that is an error, not a coin toss.
    static func build(_ rows: [HandoverScoringRow]) throws -> [UUID: [UUID: UUID]] {
        var result: [UUID: [UUID: UUID]] = [:]
        for row in rows {
            guard let optionId = row.optionId else { continue }
            if let existing = result[row.assessmentId]?[row.questionId], existing != optionId {
                throw HandoverReadError.inconsistent("conflicting duplicate scoring rows")
            }
            result[row.assessmentId, default: [:]][row.questionId] = optionId
        }
        return result
    }
}

// MARK: - Decoded rows

struct HandoverAssessmentRow {
    let id: UUID
    let version: Int
    /// assessments.created_at; there is no completion timestamp.
    let createdAt: Date
    /// Frozen at insert by a DB trigger; nil on rows that predate the column.
    let questionCount: Int?
}

/// A plans row.
struct HandoverPlanRow {
    let id: UUID
    let assessmentId: UUID
    let summary: String
    let focusDay1_30: String
    let focusDay31_60: String
    let focusDay61_90: String
    let isActive: Bool
    let createdAt: Date
}

// MARK: - Project list

struct HandoverProjectRow {
    let id: UUID
    let name: String
    let userId: UUID?
    let createdAt: Date
    let templateId: UUID?
}

struct HandoverProjectCandidate: Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date
    /// nil = the software template.
    let templateId: UUID?
    /// user_id is set and is not the signed-in user.
    let ownedBySomeoneElse: Bool

    /// Rows owned by someone else are listed but start unchecked.
    var isSelectedByDefault: Bool { !ownedBySomeoneElse }
}

enum HandoverProjects {
    /// Keeps the incoming order. A NULL owner counts as normal.
    static func candidates(rows: [HandoverProjectRow], currentUserId: UUID) -> [HandoverProjectCandidate] {
        rows.map { row in
            HandoverProjectCandidate(
                id: row.id,
                name: row.name,
                createdAt: row.createdAt,
                templateId: row.templateId,
                ownedBySomeoneElse: row.userId != nil && row.userId != currentUserId
            )
        }
    }
}

// MARK: - Team

enum HandoverTeamBuilder {
    /// Checked before any query for the team. `questionCount` is the number
    /// of definitions the store resolves for the project's template.
    /// - An explicit template id must be among the loaded templates, even if
    ///   the store still resolves definitions for it by their own template_id.
    /// - No definitions at all means scoring would silently give zeros.
    static func precheck(
        explicitTemplateId: UUID?,
        loadedTemplateIds: Set<UUID>,
        questionCount: Int
    ) -> HandoverFailureKind? {
        if let explicitTemplateId, !loadedTemplateIds.contains(explicitTemplateId) {
            return .templateMissing
        }
        if questionCount == 0 {
            // Without an explicit id the software template did not resolve.
            return explicitTemplateId == nil ? .templateMissing : .noQuestions
        }
        return nil
    }

    /// Completed assessments, oldest version first. Complete = at least as
    /// many picks as the assessment's frozen count, or the template's count
    /// on rows without one; a target of 0 never counts as complete.
    static func completedAssessments(
        _ assessments: [HandoverAssessmentRow],
        answers: [UUID: [UUID: UUID]],
        templateQuestionCount: Int
    ) -> [HandoverAssessmentRow] {
        assessments
            .filter { assessment in
                let target = assessment.questionCount ?? templateQuestionCount
                return target > 0 && (answers[assessment.id]?.count ?? 0) >= target
            }
            .sorted { a, b in
                a.version != b.version ? a.version < b.version : a.id.uuidString < b.id.uuidString
            }
    }

    /// The active plan of the NEWEST assessment (any status) that has one,
    /// the same precedence the Tasks view uses. Only rows with isActive count.
    static func selectPlan(
        assessments: [HandoverAssessmentRow],
        plans: [HandoverPlanRow]
    ) -> (plan: HandoverPlanRow, sourceVersion: Int)? {
        let newestFirst = assessments.sorted { a, b in
            a.version != b.version ? a.version > b.version : a.id.uuidString > b.id.uuidString
        }
        for assessment in newestFirst {
            let candidates = plans
                .filter { $0.isActive && $0.assessmentId == assessment.id }
                .sorted { a, b in
                    a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id.uuidString > b.id.uuidString
                }
            if let plan = candidates.first {
                return (plan, assessment.version)
            }
        }
        return nil
    }

    struct Input {
        let assessments: [HandoverAssessmentRow]
        let answersByAssessment: [UUID: [UUID: UUID]]
        /// The project's template definitions, as the store resolves them.
        let questions: [Question]
        let options: [AnswerOption]
        let activePlans: [HandoverPlanRow]
        /// plan_actions rows of the plan selectPlan picks; ignored if none.
        let planItemRows: [HandoverPlanItemRow]
        /// Every task of the project, any state.
        let actionRows: [HandoverActionRow]
        /// Insights of the latest completed assessment.
        let insights: [HandoverInsight]
    }

    static func build(_ input: Input) -> HandoverTeamData {
        let completed = completedAssessments(
            input.assessments,
            answers: input.answersByAssessment,
            templateQuestionCount: input.questions.count
        )

        // Only the two newest completed assessments are shown, so only they
        // are scored. Same ScoringService call as the result screen.
        func scoreSet(_ assessment: HandoverAssessmentRow) -> HandoverScoreSet {
            HandoverScoreSet(
                version: assessment.version,
                date: assessment.createdAt,
                scores: ScoringService.compute(
                    answers: input.answersByAssessment[assessment.id] ?? [:],
                    questions: input.questions,
                    options: input.options
                )
            )
        }
        let latest = completed.last.map { scoreSet($0) }
        let previous = completed.count >= 2 ? scoreSet(completed[completed.count - 2]) : nil

        let selected = selectPlan(assessments: input.assessments, plans: input.activePlans)
        let linked = HandoverLinking.link(
            planRows: selected == nil ? [] : input.planItemRows,
            actionRows: input.actionRows
        )
        let plan = selected.map { chosen in
            HandoverPlan(
                sourceVersion: chosen.sourceVersion,
                summary: chosen.plan.summary,
                focusDay1_30: chosen.plan.focusDay1_30,
                focusDay31_60: chosen.plan.focusDay31_60,
                focusDay61_90: chosen.plan.focusDay61_90,
                items: linked.items
            )
        }

        return HandoverTeamData(
            latest: latest,
            previous: previous,
            completedCount: completed.count,
            incompleteCount: input.assessments.count - completed.count,
            insightsSourceVersion: latest?.version,
            insights: latest == nil ? [] : input.insights,
            plan: plan,
            otherActions: linked.otherActions,
            openActions: linked.openActions,
            openCounts: linked.openCounts,
            doneActionCount: linked.doneActionCount
        )
    }
}
