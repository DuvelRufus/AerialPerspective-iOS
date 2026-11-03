//
//  HandoverLoader.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-11-03.
//

import Foundation
import Supabase

// Read-only: the Supabase I/O of the internal handover export. Every query is
// direct and throwing, with an explicit column list; no store that swallows
// errors is used. All rules live in HandoverTeamBuilder / HandoverData and run
// without a backend. This file only reads rows and hands them over.
//
// Not wired into any view yet.

enum HandoverLoaderError: LocalizedError {
    /// QuestionStore.templatesLoaded is false after a fetch.
    case templatesNotLoaded
    /// Definitions or options are missing, so scoring would give zeros.
    case questionsNotLoaded

    var errorDescription: String? {
        switch self {
        case .templatesNotLoaded:
            return "Mallarna kunde inte laddas. Kontrollera din anslutning och försök igen."
        case .questionsNotLoaded:
            return "Frågorna kunde inte laddas. Kontrollera din anslutning och försök igen."
        }
    }
}

enum HandoverLoader {

    // MARK: Project list

    /// All projects the signed-in user can read, ordered by name. A row
    /// owned by someone else comes back flagged (and should start unchecked);
    /// a NULL owner is normal. Throws on any failure.
    ///
    /// projects: id, name, user_id, created_at, template_id · no filter ·
    /// order name, id.
    @MainActor
    static func loadProjects() async throws -> [HandoverProjectCandidate] {
        let userId = try await supabase.auth.session.user.id
        let rows: [ProjectDBRow] = try await fetchSingle(
            supabase
                .from("projects")
                .select("id, name, user_id, created_at, template_id", count: .exact)
                .order("name", ascending: true)
                .order("id", ascending: true)
        )
        return HandoverProjects.candidates(
            rows: rows.map {
                HandoverProjectRow(id: $0.id, name: $0.name, userId: $0.userId, createdAt: $0.createdAt, templateId: $0.templateId)
            },
            currentUserId: userId
        )
    }

    // MARK: Export

    /// Loads the given projects one after the other. `progress` is called
    /// before each team with (1-based index, total, team name).
    ///
    /// - Throws before any team when the store's templates, definitions or
    ///   options are not loaded: the whole export is refused.
    /// - A team whose data cannot be read becomes `.failed(reason:)`; the
    ///   others still load. CancellationError is rethrown, never a failure.
    @MainActor
    static func load(
        projects: [HandoverProjectCandidate],
        questionStore: QuestionStore,
        progress: (_ index: Int, _ total: Int, _ teamName: String) -> Void
    ) async throws -> HandoverData {
        try await prepare(questionStore)

        var teams: [HandoverTeam] = []
        for (offset, project) in projects.enumerated() {
            try Task.checkCancellation()
            progress(offset + 1, projects.count, project.name)
            do {
                let data = try await loadTeam(project, questionStore: questionStore)
                teams.append(HandoverTeam(
                    projectId: project.id,
                    name: project.name,
                    domainLabels: Dictionary(
                        uniqueKeysWithValues: Domain.allCases.map {
                            ($0, questionStore.domainLabel($0, templateId: project.templateId))
                        }
                    ),
                    outcome: .loaded(data)
                ))
            } catch {
                guard let kind = HandoverFailureKind.classify(error) else {
                    throw CancellationError()
                }
                // The project id identifies the team in the log; its name,
                // task texts and scoring input never go to the console.
                print("HandoverLoader: team \(project.id) failed (\(kind.reason)): \(describeForLog(error))")
                teams.append(HandoverTeam(
                    projectId: project.id,
                    name: project.name,
                    domainLabels: [:],
                    outcome: .failed(reason: kind.reason)
                ))
            }
        }
        try Task.checkCancellation()
        return HandoverData(generatedAt: Date(), requestedCount: projects.count, teams: teams)
    }

    /// QuestionStore.fetch swallows its own errors, so success is judged from
    /// the store's state afterwards: templatesLoaded, and non-empty
    /// definitions and options.
    @MainActor
    private static func prepare(_ questionStore: QuestionStore) async throws {
        await questionStore.fetch()
        guard questionStore.templatesLoaded else { throw HandoverLoaderError.templatesNotLoaded }
        guard !questionStore.questions.isEmpty, !questionStore.options.isEmpty else {
            throw HandoverLoaderError.questionsNotLoaded
        }
    }

    // MARK: One team

    /// The queries for one team, in order (all `count: .exact`):
    ///  1. assessments  id, version, created_at, question_count
    ///                  eq project_id · order version · single request
    ///  2. answers      assessment_id, question_id, answer_option_id
    ///                  in assessment_id (the project's assessments) ·
    ///                  order assessment_id, question_id · paged
    ///  3. actions      id, title, domain, state, plan_action_id, insight_id, created_at
    ///                  eq project_id · NO state filter · order created_at, id · paged
    ///  4. plans        id, assessment_id, summary, focus_day1_30, focus_day31_60,
    ///                  focus_day61_90, is_active, created_at
    ///                  in assessment_id · eq is_active true · single request
    ///  5. plan_actions id, phase, text, domain, sort_order
    ///                  eq plan_id (the selected plan) · order sort_order, id · single
    ///  6. insights     title, domain, risk_level, suggested_action
    ///                  eq assessment_id (latest completed) · order created_at · single
    /// 2 and 4 are skipped without assessments; 5 without a plan; 6 without
    /// a completed assessment. insights.content is never selected.
    @MainActor
    private static func loadTeam(
        _ project: HandoverProjectCandidate,
        questionStore: QuestionStore
    ) async throws -> HandoverTeamData {
        // Same set the store gives questions(for: project).
        let questions = questionStore.questions(forTemplate: project.templateId)
        if let failure = HandoverTeamBuilder.precheck(
            explicitTemplateId: project.templateId,
            loadedTemplateIds: Set(questionStore.templates.map(\.id)),
            questionCount: questions.count
        ) {
            throw HandoverTeamFailure(kind: failure)
        }

        let assessmentRows: [AssessmentDBRow] = try await fetchSingle(
            supabase
                .from("assessments")
                .select("id, version, created_at, question_count", count: .exact)
                .eq("project_id", value: project.id)
                .order("version", ascending: true)
        )
        let assessments = assessmentRows.map {
            HandoverAssessmentRow(id: $0.id, version: $0.version, createdAt: $0.createdAt, questionCount: $0.questionCount)
        }
        let assessmentIds = assessments.map(\.id.uuidString)

        var answersByAssessment: [UUID: [UUID: UUID]] = [:]
        if !assessments.isEmpty {
            // Ordered by the selected columns: ordering by a column that is
            // not selected was not verified to work, so it is not relied on.
            let scoringRows: [ScoringDBRow] = try await HandoverPaging.collectAll { from, to in
                let response: PostgrestResponse<[ScoringDBRow]> = try await supabase
                    .from("answers")
                    .select("assessment_id, question_id, answer_option_id", count: .exact)
                    .in("assessment_id", values: assessmentIds)
                    .order("assessment_id", ascending: true)
                    .order("question_id", ascending: true)
                    .range(from: from, to: to)
                    .execute()
                return HandoverPage(rows: response.value, total: response.count)
            }
            answersByAssessment = try HandoverScoringIndex.build(
                scoringRows.map {
                    HandoverScoringRow(assessmentId: $0.assessmentId, questionId: $0.questionId, optionId: $0.optionId)
                }
            )
        }

        let actionDBRows: [ActionDBRow] = try await HandoverPaging.collectAll { from, to in
            let response: PostgrestResponse<[ActionDBRow]> = try await supabase
                .from("actions")
                .select("id, title, domain, state, plan_action_id, insight_id, created_at", count: .exact)
                .eq("project_id", value: project.id)
                .order("created_at", ascending: true)
                .order("id", ascending: true)
                .range(from: from, to: to)
                .execute()
            return HandoverPage(rows: response.value, total: response.count)
        }
        let actionRows = actionDBRows.map {
            HandoverActionRow(
                id: $0.id, title: $0.title, domain: $0.domain, state: $0.state,
                createdAt: $0.createdAt, planActionId: $0.planActionId, insightId: $0.insightId
            )
        }

        var activePlans: [HandoverPlanRow] = []
        if !assessments.isEmpty {
            let planDBRows: [PlanDBRow] = try await fetchSingle(
                supabase
                    .from("plans")
                    .select("id, assessment_id, summary, focus_day1_30, focus_day31_60, focus_day61_90, is_active, created_at", count: .exact)
                    .in("assessment_id", values: assessmentIds)
                    .eq("is_active", value: true)
            )
            activePlans = planDBRows.map {
                HandoverPlanRow(
                    id: $0.id, assessmentId: $0.assessmentId,
                    // Display text only: a NULL reads as empty rather than
                    // failing the whole team.
                    summary: $0.summary ?? "",
                    focusDay1_30: $0.focusDay1_30 ?? "",
                    focusDay31_60: $0.focusDay31_60 ?? "",
                    focusDay61_90: $0.focusDay61_90 ?? "",
                    isActive: $0.isActive, createdAt: $0.createdAt
                )
            }
        }

        var planItemRows: [HandoverPlanItemRow] = []
        if let selected = HandoverTeamBuilder.selectPlan(assessments: assessments, plans: activePlans) {
            let itemDBRows: [PlanItemDBRow] = try await fetchSingle(
                supabase
                    .from("plan_actions")
                    .select("id, phase, text, domain, sort_order", count: .exact)
                    .eq("plan_id", value: selected.plan.id)
                    .order("sort_order", ascending: true)
                    .order("id", ascending: true)
            )
            planItemRows = itemDBRows.map {
                HandoverPlanItemRow(id: $0.id, phase: $0.phase, text: $0.text, domain: $0.domain, sortOrder: $0.sortOrder)
            }
        }

        var insights: [HandoverInsight] = []
        let completed = HandoverTeamBuilder.completedAssessments(
            assessments,
            answers: answersByAssessment,
            templateQuestionCount: questions.count
        )
        if let latest = completed.last {
            // Title, domain, risk level and suggested action only.
            let insightDBRows: [InsightDBRow] = try await fetchSingle(
                supabase
                    .from("insights")
                    .select("title, domain, risk_level, suggested_action", count: .exact)
                    .eq("assessment_id", value: latest.id)
                    .order("created_at", ascending: true)
            )
            insights = insightDBRows.map {
                HandoverInsight(title: $0.title, domain: $0.domain, riskLevel: $0.riskLevel, suggestedAction: $0.suggestedAction)
            }
        }

        return HandoverTeamBuilder.build(HandoverTeamBuilder.Input(
            assessments: assessments,
            answersByAssessment: answersByAssessment,
            questions: questions,
            options: questionStore.options,
            activePlans: activePlans,
            planItemRows: planItemRows,
            actionRows: actionRows,
            insights: insights
        ))
    }

    // MARK: Helpers

    /// One request; refuses a result that may have been capped or that does
    /// not match the server's own total.
    @MainActor
    private static func fetchSingle<Row: Decodable>(_ query: PostgrestTransformBuilder) async throws -> [Row] {
        let response: PostgrestResponse<[Row]> = try await query.execute()
        try HandoverPaging.validateSingle(rowCount: response.value.count, total: response.count)
        return response.value
    }

    /// Console text for an error: the kind, a code or a coding path. Never a
    /// row value, a project name, a task text or scoring input.
    private static func describeForLog(_ error: Error) -> String {
        switch error {
        case let urlError as URLError:
            return "URLError code \(urlError.code.rawValue)"
        case let decoding as DecodingError:
            switch decoding {
            case .typeMismatch(_, let ctx):     return "DecodingError typeMismatch at \(path(ctx))"
            case .valueNotFound(_, let ctx):    return "DecodingError valueNotFound at \(path(ctx))"
            case .keyNotFound(let key, let ctx): return "DecodingError keyNotFound \(key.stringValue) at \(path(ctx))"
            case .dataCorrupted(let ctx):       return "DecodingError dataCorrupted at \(path(ctx))"
            @unknown default:                   return "DecodingError"
            }
        case let postgrest as PostgrestError:
            return "PostgrestError code \(postgrest.code ?? "-"): \(postgrest.message)"
        case let http as HTTPError:
            return "HTTPError status \(http.response.statusCode)"
        case let read as HandoverReadError:
            return "HandoverReadError \(read)"
        case let failure as HandoverTeamFailure:
            return "HandoverTeamFailure \(failure.kind.reason)"
        default:
            return String(describing: type(of: error))
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map(\.stringValue).joined(separator: ".")
    }
}

// MARK: - Decoded rows

private nonisolated struct ProjectDBRow: Decodable {
    let id: UUID
    let name: String
    let userId: UUID?
    let createdAt: Date
    let templateId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userId = "user_id"
        case createdAt = "created_at"
        case templateId = "template_id"
    }
}

private nonisolated struct AssessmentDBRow: Decodable {
    let id: UUID
    let version: Int
    let createdAt: Date
    let questionCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, version
        case createdAt = "created_at"
        case questionCount = "question_count"
    }
}

/// answers, three columns only. Used to score and then dropped.
private nonisolated struct ScoringDBRow: Decodable {
    let assessmentId: UUID
    let questionId: UUID
    let optionId: UUID?

    enum CodingKeys: String, CodingKey {
        case assessmentId = "assessment_id"
        case questionId = "question_id"
        case optionId = "answer_option_id"
    }
}

private nonisolated struct ActionDBRow: Decodable {
    let id: UUID
    let title: String
    let domain: String
    let state: String
    let planActionId: UUID?
    let insightId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, domain, state
        case planActionId = "plan_action_id"
        case insightId = "insight_id"
        case createdAt = "created_at"
    }
}

private nonisolated struct PlanDBRow: Decodable {
    let id: UUID
    let assessmentId: UUID
    let summary: String?
    let focusDay1_30: String?
    let focusDay31_60: String?
    let focusDay61_90: String?
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, summary
        case assessmentId = "assessment_id"
        case focusDay1_30 = "focus_day1_30"
        case focusDay31_60 = "focus_day31_60"
        case focusDay61_90 = "focus_day61_90"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

private nonisolated struct PlanItemDBRow: Decodable {
    let id: UUID
    let phase: String
    let text: String
    let domain: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, phase, text, domain
        case sortOrder = "sort_order"
    }
}

private nonisolated struct InsightDBRow: Decodable {
    let title: String?
    let domain: String?
    let riskLevel: String?
    let suggestedAction: String?

    enum CodingKeys: String, CodingKey {
        case title, domain
        case riskLevel = "risk_level"
        case suggestedAction = "suggested_action"
    }
}
