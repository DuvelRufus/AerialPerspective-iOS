//
//  ProjectReportLoader.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-10-06.
//

import Foundation
import Supabase

enum ProjectReportError: LocalizedError {
    /// The project's template resolved to no questions — scoring would
    /// silently produce all-zero domains, so the report refuses instead.
    case questionsUnresolved

    var errorDescription: String? {
        switch self {
        case .questionsUnresolved:
            return "Frågorna kunde inte laddas. Kontrollera din anslutning och försök igen."
        }
    }
}

/// Read-only: fetches ONE project's assessments, answers, actions and
/// latest insights and derives ProjectReportData. Unlike
/// AssessmentScoresLoader it never touches other projects' rows.
enum ProjectReportLoader {
    private struct InsightRow: Decodable {
        let title: String?
        let domain: String?
    }

    @MainActor
    static func load(
        project: Project,
        questionStore: QuestionStore,
        anonymized: Bool = false,
        anonymizedName: String = "Team A",
        hideTexts: Bool = false
    ) async throws -> ProjectReportData {
        if questionStore.questions.isEmpty || !questionStore.templatesLoaded {
            await questionStore.fetch()
        }
        // Same inputs as ResultView.recomputeCurrentScores, so the report's
        // numbers can't drift from the result screen's.
        let questions = questionStore.questions(for: project)
        let options = questionStore.options
        guard !questions.isEmpty else { throw ProjectReportError.questionsUnresolved }

        let assessments: [Assessment] = try await supabase
            .from("assessments")
            .select("id, project_id, version, created_at, question_count")
            .eq("project_id", value: project.id)
            .order("version", ascending: true)
            .execute()
            .value

        let answersByAssessment = try await fetchAnswers(assessmentIds: assessments.map(\.id))

        // Mirrors AssessmentListView.isComplete: the frozen count, else the
        // template's count on rows predating question_count; > 0 so an
        // empty assessment can't count as complete.
        let completed = assessments.filter { assessment in
            let target = assessment.questionCount ?? questions.count
            return target > 0 && (answersByAssessment[assessment.id]?.count ?? 0) >= target
        }

        let scoresByVersion = completed.map { assessment in
            ScoringService.compute(
                answers: answersByAssessment[assessment.id] ?? [:],
                questions: questions,
                options: options
            )
        }
        let series = zip(completed, scoresByVersion).map { assessment, scores in
            AssessmentPoint(
                version: assessment.version,
                date: assessment.createdAt,
                total: ScoringService.total(scores),
                domainScores: Dictionary(uniqueKeysWithValues: scores.map { ($0.domain, $0.score) }),
                levels: Dictionary(uniqueKeysWithValues: scores.map { ($0.domain, $0.level) })
            )
        }

        var firstToLatestDelta: ScoreDelta? = nil
        if scoresByVersion.count >= 2, let first = scoresByVersion.first, let latest = scoresByVersion.last {
            firstToLatestDelta = ScoreDelta(
                perDomain: ScoringService.delta(current: latest, previous: first),
                total: ScoringService.total(latest) - ScoringService.total(first)
            )
        }

        let adjacentDeltas = zip(completed.indices.dropLast(), completed.indices.dropFirst()).map { i, j in
            AdjacentDelta(
                fromVersion: completed[i].version,
                toVersion: completed[j].version,
                delta: ScoreDelta(
                    perDomain: ScoringService.delta(current: scoresByVersion[j], previous: scoresByVersion[i]),
                    total: ScoringService.total(scoresByVersion[j]) - ScoringService.total(scoresByVersion[i])
                )
            )
        }

        let actions: [ProjectAction] = try await supabase
            .from("actions")
            .select()
            .eq("project_id", value: project.id)
            .order("created_at", ascending: false)
            .execute()
            .value

        var actionsPerDomain: [Domain: ActionCounts] = [:]
        var unknownDomainActions = ActionCounts()
        for action in actions {
            if let domain = Domain(caseInsensitive: action.domain) {
                count(action, into: &actionsPerDomain[domain, default: ActionCounts()])
            } else {
                count(action, into: &unknownDomainActions)
            }
        }

        let done = actions
            .filter(\.isDone)
            .map { action in
                DoneAction(
                    // With hideTexts the real title never enters the data.
                    title: hideTexts ? placeholderTitle(action.origin) : action.title,
                    origin: action.origin,
                    domain: action.domain,
                    completedAt: action.completedAt,
                    completedAtManual: action.completedAtManual,
                    period: action.completedAt.map { period(for: $0, in: series) }
                )
            }
        // Dated newest completion first; undated after, keeping the fetch's
        // created_at desc order.
        let doneActions = done
            .filter { $0.completedAt != nil }
            .sorted { $0.completedAt! > $1.completedAt! }
            + done.filter { $0.completedAt == nil }

        var latestInsights: [InsightSummary] = []
        if let latest = completed.last {
            // Title + domain only — the report never carries body text.
            // With hideTexts not even the title is fetched.
            let rows: [InsightRow] = try await supabase
                .from("insights")
                .select(hideTexts ? "domain" : "title, domain")
                .eq("assessment_id", value: latest.id)
                .order("created_at", ascending: true)
                .execute()
                .value
            latestInsights = rows.map { InsightSummary(title: hideTexts ? nil : $0.title, domain: $0.domain) }
        }

        return ProjectReportData(
            projectName: anonymized ? anonymizedName : project.name,
            nameHidden: anonymized,
            textsHidden: hideTexts,
            templateLabelsPerDomain: Dictionary(
                uniqueKeysWithValues: Domain.allCases.map { ($0, questionStore.domainLabel($0, project: project)) }
            ),
            generatedAt: Date(),
            series: series,
            incompleteAssessmentCount: assessments.count - completed.count,
            firstToLatestDelta: firstToLatestDelta,
            adjacentDeltas: adjacentDeltas,
            actionsPerDomain: actionsPerDomain,
            unknownDomainActions: unknownDomainActions,
            doneActions: doneActions,
            latestInsights: latestInsights
        )
    }

    /// assessmentId → [questionId: answerOptionId] for the given
    /// assessments only, paged past PostgREST's silent 1000-row cap.
    @MainActor
    private static func fetchAnswers(assessmentIds: [UUID]) async throws -> [UUID: [UUID: UUID]] {
        guard !assessmentIds.isEmpty else { return [:] }
        let ids = assessmentIds.map(\.uuidString)
        var result: [UUID: [UUID: UUID]] = [:]
        // Ordered so page windows stay disjoint; a short page marks the end.
        let pageSize = 1000
        var offset = 0
        while true {
            let page: [Answer] = try await supabase
                .from("answers")
                .select()
                .in("assessment_id", values: ids)
                .order("id", ascending: true)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            for row in page {
                guard let optionId = row.answerOptionId else { continue }
                result[row.assessmentId, default: [:]][row.questionId] = optionId
            }
            if page.count < pageSize { break }
            offset += pageSize
        }
        return result
    }

    private static func count(_ action: ProjectAction, into counts: inout ActionCounts) {
        switch action.taskState {
        case .open: counts.open += 1
        case .prio: counts.prio += 1
        case .doing: counts.doing += 1
        case .waiting: counts.waiting += 1
        case .done:
            counts.done += 1
            if action.completedAt != nil {
                counts.doneWithDate += 1
                if action.completedAtManual { counts.doneWithManualDate += 1 }
            } else {
                counts.doneWithoutDate += 1
            }
        }
    }

    /// Stands in for a task title when texts are hidden.
    private static func placeholderTitle(_ origin: ActionOrigin) -> String {
        switch origin {
        case .plan:    return "Planuppgift"
        case .insight: return "Insiktsuppgift"
        case .own:     return "Egen uppgift"
        }
    }

    /// The span between the last assessment dated at/before `date` and the
    /// next one. An empty series yields (nil, nil).
    private static func period(for date: Date, in series: [AssessmentPoint]) -> ReportPeriod {
        let before = series.last { $0.date <= date }
        let after = series.first { $0.date > date }
        return ReportPeriod(fromVersion: before?.version, toVersion: after?.version)
    }
}
