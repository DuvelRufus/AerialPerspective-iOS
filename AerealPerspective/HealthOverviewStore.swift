//
//  HealthOverviewStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-16.
//

import Foundation
import Supabase

/// One team's aggregated health for the Översikt dashboard.
struct TeamHealth: Identifiable {
    let project: Project
    /// The latest COMPLETED assessment's six domain scores;
    /// nil = no completed assessment yet (placeholder card).
    let latestScores: [DomainScore]?
    /// total(latest) − total(previous); nil with fewer than two completed.
    let delta: Int?
    /// Exactly one completed assessment — renders the "NY" chip.
    let isNew: Bool
    let openCount: Int

    /// Headline risk: the lowest-scoring domain of the latest assessment.
    var weakest: DomainScore? {
        latestScores?.min { $0.score < $1.score }
    }

    var id: UUID { project.id }
}

@MainActor
@Observable
class HealthOverviewStore {
    var rows: [TeamHealth] = []
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

    private struct OpenActionRef: Decodable {
        let projectId: UUID

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
        }
    }

    /// Four queries regardless of team count — no N+1: projects, all
    /// assessments (RLS scopes them to the owner), all answers batched via
    /// .in, and the open-action counts. Everything else is computed here:
    /// completed = answered count >= question count; trend = total-score
    /// delta between the two newest completed assessments.
    func load(questionStore: QuestionStore, showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }
        error = nil
        do {
            if questionStore.questions.isEmpty {
                await questionStore.fetch()
            }
            let questions = questionStore.questions
            let options = questionStore.options
            let questionCount = questions.count

            let projectStore = ProjectStore()
            await projectStore.fetch()
            if let projectError = projectStore.error { throw projectError }
            let projects = projectStore.projects

            let assessments: [AssessmentRef] = try await supabase
                .from("assessments")
                .select("id, project_id, version")
                .execute()
                .value

            var answersByAssessment: [UUID: [UUID: UUID]] = [:]
            let assessmentIds = assessments.map { $0.id.uuidString }
            if !assessmentIds.isEmpty {
                let answers: [Answer] = try await supabase
                    .from("answers")
                    .select()
                    .in("assessment_id", values: assessmentIds)
                    .execute()
                    .value
                for row in answers {
                    guard let optionId = row.answerOptionId else { continue }
                    answersByAssessment[row.assessmentId, default: [:]][row.questionId] = optionId
                }
            }

            let openRows: [OpenActionRef] = try await supabase
                .from("actions")
                .select("project_id")
                .eq("status", value: "open")
                .execute()
                .value
            var openCounts: [UUID: Int] = [:]
            for row in openRows {
                openCounts[row.projectId, default: 0] += 1
            }

            let byProject = Dictionary(grouping: assessments, by: { $0.projectId })
            rows = projects.map { project in
                let completed = (byProject[project.id] ?? [])
                    .filter { questionCount > 0 && (answersByAssessment[$0.id]?.count ?? 0) >= questionCount }
                    .sorted { $0.version > $1.version }

                func scores(_ ref: AssessmentRef) -> [DomainScore] {
                    ScoringService.compute(
                        answers: answersByAssessment[ref.id] ?? [:],
                        questions: questions,
                        options: options
                    )
                }

                let latest = completed.first.map(scores)
                var delta: Int? = nil
                if let latest, completed.count >= 2 {
                    delta = ScoringService.total(latest) - ScoringService.total(scores(completed[1]))
                }

                return TeamHealth(
                    project: project,
                    latestScores: latest,
                    delta: delta,
                    isNew: completed.count == 1,
                    openCount: openCounts[project.id] ?? 0
                )
            }
        } catch {
            self.error = error
            print("HealthOverviewStore load error: \(error)")
        }
    }
}
