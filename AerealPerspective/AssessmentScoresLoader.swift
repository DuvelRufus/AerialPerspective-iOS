//
//  AssessmentScoresLoader.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-17.
//

import Foundation
import Supabase

/// Lightweight assessments row — id/project/version/count only, shared by every
/// score-derivation consumer so the heavy Assessment model (JSONB plan)
/// never has to decode for scoring.
struct AssessmentRef: Decodable {
    let id: UUID
    let projectId: UUID
    let version: Int
    /// Set by a DB trigger at insert; nil on rows predating the column.
    let questionCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, version
        case projectId = "project_id"
        case questionCount = "question_count"
    }
}

/// The shared intermediate both Översikt stores (and next, PlanView) build
/// on: completed assessments per project plus the answer data to score
/// them. Consumers take their own slice; scoring goes through scores(for:)
/// so the ScoringService.compute call can't drift between them.
struct AssessmentScores {
    let questions: [Question]
    let options: [AnswerOption]
    /// Completed (answered >= the assessment's question count) assessments per project,
    /// newest version first. Empty when there are no questions.
    let completedByProject: [UUID: [AssessmentRef]]
    let answersByAssessment: [UUID: [UUID: UUID]]

    static let empty = AssessmentScores(
        questions: [], options: [], completedByProject: [:], answersByAssessment: [:]
    )

    func scores(for ref: AssessmentRef) -> [DomainScore] {
        ScoringService.compute(
            answers: answersByAssessment[ref.id] ?? [:],
            questions: questions,
            options: options
        )
    }

    /// The latest completed assessment's scores per project.
    func latestScoresByProject() -> [UUID: [DomainScore]] {
        completedByProject.compactMapValues { refs in
            refs.first.map(scores(for:))
        }
    }
}

/// Owns the Supabase I/O that pure ScoringService must not: fetches all
/// assessments plus their answers (paginated past PostgREST's silent
/// 1000-row cap) and derives the completed set per project.
enum AssessmentScoresLoader {
    @MainActor
    static func load(questionStore: QuestionStore) async throws -> AssessmentScores {
        if questionStore.questions.isEmpty || !questionStore.templatesLoaded {
            await questionStore.fetch()
        }
        // Unfiltered: scoring only counts answered questions, so every
        // template's questions can back every assessment.
        let questions = questionStore.questions
        let options = questionStore.options
        guard !questions.isEmpty else { return .empty }
        // Fallback target for rows without question_count: all of them
        // predate templates, so they belong to software.
        let softwareQuestionCount = questionStore
            .questions(forTemplate: questionStore.softwareTemplateId).count

        let assessments: [AssessmentRef] = try await supabase
            .from("assessments")
            .select("id, project_id, version, question_count")
            .execute()
            .value
        guard !assessments.isEmpty else {
            return AssessmentScores(
                questions: questions,
                options: options,
                completedByProject: [:],
                answersByAssessment: [:]
            )
        }

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

        let completedByProject = Dictionary(grouping: assessments, by: { $0.projectId })
            .mapValues { refs in
                refs.filter { ref in
                    // > 0 mirrors AssessmentListView.isComplete: a zero
                    // count must not mark an empty assessment complete.
                    let target = ref.questionCount ?? softwareQuestionCount
                    return target > 0 && (answersByAssessment[ref.id]?.count ?? 0) >= target
                }
                    .sorted { $0.version > $1.version }
            }

        return AssessmentScores(
            questions: questions,
            options: options,
            completedByProject: completedByProject,
            answersByAssessment: answersByAssessment
        )
    }
}
