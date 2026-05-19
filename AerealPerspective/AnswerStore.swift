//
//  AnswerStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

@MainActor
@Observable
class AnswerStore {
    var answers: [UUID: UUID] = [:]  // question_id -> answer_option_id
    var isLoading = false

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
        answers[questionId] = answerOptionId
        do {
            let existing: [Answer] = try await supabase
                .from("answers")
                .select()
                .eq("assessment_id", value: assessmentId)
                .eq("question_id", value: questionId)
                .execute()
                .value

            if let existing = existing.first {
                try await supabase
                    .from("answers")
                    .update(["answer_option_id": AnyJSON.string(answerOptionId.uuidString)])
                    .eq("id", value: existing.id)
                    .execute()
            } else {
                try await supabase
                    .from("answers")
                    .insert([
                        "assessment_id": AnyJSON.string(assessmentId.uuidString),
                        "question_id": AnyJSON.string(questionId.uuidString),
                        "answer_option_id": AnyJSON.string(answerOptionId.uuidString)
                    ])
                    .execute()
            }
        } catch {
            print("AnswerStore save error: \(error)")
        }
    }
}
