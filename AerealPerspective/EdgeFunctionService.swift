//
//  EdgeFunctionService.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

enum EdgeFunctionError: Error, LocalizedError {
    case decodingFailed(function: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let fn, let e):
            return "Failed to decode response from '\(fn)': \(e.localizedDescription)"
        }
    }
}

struct EdgeFunctionService {

    // MARK: - Payload types

    private struct InsightsPayload: Encodable {
        let scores: [String: Int]
        let questionsWithAnswers: [[String: String]]
    }

    private struct PlanPayload: Encodable {
        let scores: [String: Int]
        let questionsWithAnswers: [[String: String]]
        let durationValue: Int?
        let durationUnit: String?
        // nil (first generation) is omitted from the JSON, keeping the
        // request identical to the pre-regeneration contract.
        let currentActions: [CurrentPlanAction]?
    }

    // Wrapper matching { "insights": [...] } returned by generate-insights.
    private struct InsightsResponse: Decodable {
        var insights: [InsightResult]
    }

    private struct InsightResult: Decodable {
        var title: String
        var body: String
        var risk_level: String
        // Optional: absent while the deployed function predates domain tagging.
        var domain: String?
        var suggested_action: String?
    }

    // MARK: - Public API

    static func generateInsights(
        scores: [DomainScore],
        answers: [UUID: UUID],
        questions: [Question],
        options: [AnswerOption]
    ) async throws -> [Insight] {
        let payload = InsightsPayload(
            scores: scoreDict(from: scores),
            questionsWithAnswers: buildQnA(answers: answers, questions: questions, options: options)
        )

        let wrapper: InsightsResponse
        do {
            wrapper = try await supabase.functions.invoke(
                "generate-insights",
                options: FunctionInvokeOptions(body: payload),
                decode: { data, _ in
                    print("EdgeFunctionService: generate-insights raw response: \(String(data: data, encoding: .utf8) ?? "<unreadable>")")
                    return try JSONDecoder().decode(InsightsResponse.self, from: data)
                }
            )
        } catch let e as DecodingError {
            throw EdgeFunctionError.decodingFailed(function: "generate-insights", underlying: e)
        }

        return wrapper.insights.map { r in
            Insight(
                id: UUID(),
                assessmentId: UUID(),
                title: r.title,
                content: r.body,
                riskLevel: RiskLevel(rawValue: r.risk_level) ?? .note,
                domain: r.domain,
                suggestedAction: r.suggested_action,
                createdAt: Date()
            )
        }
    }

    // Wrapper matching { "plan": { ... } } returned by generate-plan.
    // Standard decoder preserves day1_30/day31_60/day61_90 keys exactly.
    private struct PlanResponse: Decodable {
        var plan: GeneratedPlan
    }

    static func generatePlan(
        scores: [DomainScore],
        answers: [UUID: UUID],
        questions: [Question],
        options: [AnswerOption],
        durationValue: Int?,
        durationUnit: String?,
        currentActions: [CurrentPlanAction]? = nil
    ) async throws -> GeneratedPlan {
        let payload = PlanPayload(
            scores: scoreDict(from: scores),
            questionsWithAnswers: buildQnA(answers: answers, questions: questions, options: options),
            durationValue: durationValue,
            durationUnit: durationUnit,
            currentActions: currentActions
        )

        let wrapper: PlanResponse
        do {
            wrapper = try await supabase.functions.invoke(
                "generate-plan",
                options: FunctionInvokeOptions(body: payload),
                decode: { data, _ in
                    print("EdgeFunctionService: generate-plan raw response: \(String(data: data, encoding: .utf8) ?? "<unreadable>")")
                    return try JSONDecoder().decode(PlanResponse.self, from: data)
                }
            )
        } catch let e as DecodingError {
            throw EdgeFunctionError.decodingFailed(function: "generate-plan", underlying: e)
        }

        return wrapper.plan
    }

    // MARK: - Helpers

    private static func scoreDict(from scores: [DomainScore]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: scores.map { ($0.domain.rawValue, $0.score) })
    }

    private static func buildQnA(
        answers: [UUID: UUID],
        questions: [Question],
        options: [AnswerOption]
    ) -> [[String: String]] {
        let optionById = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        return questions.compactMap { q in
            guard let optionId = answers[q.id],
                  let option = optionById[optionId] else { return nil }
            return [
                "domain": q.domain,
                "question": q.questionText,
                "answerLabel": option.label
            ]
        }
    }
}

// MARK: - generate-plan regeneration contract

/// One action of the current active plan, sent so the function can anchor
/// retained actions. Keys are short ("a1", "a2", ...) because the model
/// echoes those reliably; the key→plan_actions.id map stays client-side.
struct CurrentPlanAction: Encodable {
    let key: String
    let phase: String
    let text: String
    let domain: String?
}

/// The function's response. `ref` echoes a currentActions key on retained
/// actions; absent on new ones. `domain` is optional in practice — the
/// model sometimes omits it. Never persisted as-is: translated to the
/// regenerate_plan RPC payload, where ref becomes prev_id.
struct GeneratedPlan: Decodable {
    var summary: String
    var day1_30: GeneratedPhase
    var day31_60: GeneratedPhase
    var day61_90: GeneratedPhase
}

struct GeneratedPhase: Decodable {
    var focus: String
    var actions: [GeneratedAction]
}

struct GeneratedAction: Decodable {
    var text: String
    var domain: String?
    var ref: String?
}
