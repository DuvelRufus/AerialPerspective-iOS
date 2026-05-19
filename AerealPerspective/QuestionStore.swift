//
//  QuestionStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

@MainActor
@Observable
class QuestionStore {
    var questions: [Question] = []
    var options: [AnswerOption] = []
    var isLoading = false

    var groupedByDomain: [(domain: Domain, questions: [Question])] {
        Domain.allCases.map { domain in
            let domainQuestions = questions
                .filter { $0.domain == domain.rawValue }
                .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            return (domain: domain, questions: domainQuestions)
        }
    }

    func optionsFor(question: Question) -> [AnswerOption] {
        options
            .filter { $0.questionId == question.id }
            .sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    func fetch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            questions = try await supabase
                .from("questions")
                .select()
                .order("sort_order", ascending: true)
                .execute()
                .value
            options = try await supabase
                .from("answer_options")
                .select()
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            print("QuestionStore fetch error: \(error)")
        }
    }
}
