//
//  AnswerStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

private struct AnswerUpsert: Encodable {
    let assessment_id: UUID
    let question_id: UUID
    let answer_option_id: UUID
}

@MainActor
@Observable
class AnswerStore {
    var answers: [UUID: UUID] = [:]  // question_id -> answer_option_id
    var isLoading = false
    var error: Error? = nil

    func fetch(assessmentId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [Answer] = try await supabase
                .from("answers")
                .select()
                .eq("assessment_id", value: assessmentId)
                .execute()
                .value
            answers = Dictionary(
                uniqueKeysWithValues: rows.compactMap { row in
                    guard let optionId = row.answerOptionId else { return nil }
                    return (row.questionId, optionId)
                }
            )
        } catch {
            print("AnswerStore fetch error: \(error)")
        }
    }

    func save(assessmentId: UUID, questionId: UUID, answerOptionId: UUID) async {
        let previous = answers[questionId]
        answers[questionId] = answerOptionId
        error = nil
        do {
            try await supabase
                .from("answers")
                .upsert(
                    AnswerUpsert(
                        assessment_id: assessmentId,
                        question_id: questionId,
                        answer_option_id: answerOptionId
                    ),
                    onConflict: "assessment_id,question_id"
                )
                .execute()
        } catch {
            // Revert only if a newer selection hasn't replaced this one while
            // the request was in flight.
            if answers[questionId] == answerOptionId {
                answers[questionId] = previous
            }
            self.error = error
            print("AnswerStore save error: \(error)")
        }
    }
}
