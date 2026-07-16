//
//  OpenActionsStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-16.
//

import Foundation
import Supabase

/// One row in the global Tasks lens: an open action plus the context the
/// lens renders per row but the action itself doesn't carry.
struct OpenActionRow: Identifiable {
    let action: ProjectAction
    let teamName: String
    /// Current score of the action's domain (latest completed assessment);
    /// nil = unresolvable domain or no completed assessment, sorts last.
    let urgency: Int?

    var id: UUID { action.id }
}

@MainActor
@Observable
class OpenActionsStore {
    var prio: [OpenActionRow] = []
    var open: [OpenActionRow] = []
    var waiting: [OpenActionRow] = []
    var isLoading = false
    var error: Error? = nil

    private struct AssessmentRef: Decodable {
        let id: UUID
        let projectId: UUID
        let version: Int

        enum CodingKeys: String, CodingKey {
            case id, version
            case projectId = "project_id"
        }
    }

    /// Fixed query count regardless of team count — no N+1: one query for
    /// ALL open actions (state != 'done', the source-of-truth column; the
    /// legacy status column stays untouched until R5), plus the same
    /// projects/assessments/answers batch HealthOverviewStore uses so
    /// urgency can be the action's CURRENT domain score — the same sort key
    /// PlanView.urgency uses, keeping the lens and Plan consistent.
    func load(questionStore: QuestionStore, showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }
        error = nil
        do {
            // The three fetches are independent — run them concurrently;
            // one 5G round trip of latency instead of five stacked.
            let projectStore = ProjectStore()
            async let actionsFetch: [ProjectAction] = supabase
                .from("actions")
                .select()
                .neq("state", value: "done")
                .execute()
                .value
            async let projectsFetch: Void = projectStore.fetch()
            async let scoresFetch = latestScores(questionStore: questionStore)

            let actions = try await actionsFetch
            _ = await projectsFetch
            if let projectError = projectStore.error { throw projectError }
            let nameByProject = Dictionary(
                uniqueKeysWithValues: projectStore.projects.map { ($0.id, $0.name) }
            )
            let scoresByProject = try await scoresFetch

            var groups: [TaskState: [OpenActionRow]] = [:]
            for action in actions {
                // Orphaned actions (project deleted / not visible) are dropped.
                guard let teamName = nameByProject[action.projectId] else { continue }
                let state = action.taskState
                guard state != .done else { continue }
                var urgency: Int? = nil
                if let domain = Domain(caseInsensitive: action.domain) {
                    urgency = scoresByProject[action.projectId]?
                        .first(where: { $0.domain == domain })?.score
                }
                groups[state, default: []].append(
                    OpenActionRow(action: action, teamName: teamName, urgency: urgency)
                )
            }

            prio = sortedByUrgency(groups[.prio] ?? [])
            open = sortedByUrgency(groups[.open] ?? [])
            waiting = sortedByUrgency(groups[.waiting] ?? [])
        } catch {
            self.error = error
            print("OpenActionsStore load error: \(error)")
        }
    }

    /// Spinner-free refresh for pull-to-refresh, mirroring
    /// HealthOverviewStore's showSpinner: false path.
    func reload(questionStore: QuestionStore) async {
        await load(questionStore: questionStore, showSpinner: false)
    }

    /// Lowest current domain score first (most urgent on top), nil last;
    /// ties break newest-first on createdAt — Plan's tie-break (flat plan
    /// index) has no global equivalent.
    private func sortedByUrgency(_ rows: [OpenActionRow]) -> [OpenActionRow] {
        rows.sorted { a, b in
            let ua = a.urgency ?? Int.max
            let ub = b.urgency ?? Int.max
            if ua != ub { return ua < ub }
            return a.action.createdAt > b.action.createdAt
        }
    }

    /// Domain scores of each project's latest COMPLETED assessment
    /// (answered count >= question count, highest version) — the same
    /// batched derivation HealthOverviewStore.load performs.
    private func latestScores(questionStore: QuestionStore) async throws -> [UUID: [DomainScore]] {
        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }
        let questions = questionStore.questions
        let options = questionStore.options
        let questionCount = questions.count
        guard questionCount > 0 else { return [:] }

        let assessments: [AssessmentRef] = try await supabase
            .from("assessments")
            .select("id, project_id, version")
            .execute()
            .value
        guard !assessments.isEmpty else { return [:] }

        var answersByAssessment: [UUID: [UUID: UUID]] = [:]
        let assessmentIds = assessments.map { $0.id.uuidString }
        // PostgREST caps a response at 1000 rows silently — page until a
        // short page marks the end. Ordered so page windows stay disjoint.
        let pageSize = 1000
        var offset = 0
        while true {
            let page: [Answer] = try await supabase
                .from("answers")
                .select()
                .in("assessment_id", values: assessmentIds)
                .order("id", ascending: true)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            for row in page {
                guard let optionId = row.answerOptionId else { continue }
                answersByAssessment[row.assessmentId, default: [:]][row.questionId] = optionId
            }
            if page.count < pageSize { break }
            offset += pageSize
        }

        var scoresByProject: [UUID: [DomainScore]] = [:]
        for (projectId, refs) in Dictionary(grouping: assessments, by: { $0.projectId }) {
            let latestCompleted = refs
                .filter { (answersByAssessment[$0.id]?.count ?? 0) >= questionCount }
                .max { $0.version < $1.version }
            guard let latestCompleted else { continue }
            scoresByProject[projectId] = ScoringService.compute(
                answers: answersByAssessment[latestCompleted.id] ?? [:],
                questions: questions,
                options: options
            )
        }
        return scoresByProject
    }
}
