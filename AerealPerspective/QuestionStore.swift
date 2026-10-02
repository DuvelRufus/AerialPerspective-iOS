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
    var templates: [Template] = []
    var isLoading = false

    static let softwareTemplateKey = "software"

    var softwareTemplateId: UUID? {
        templates.first { $0.key == Self.softwareTemplateKey }?.id
    }

    /// The project's template; projects without one belong to software.
    func effectiveTemplateId(for project: Project) -> UUID? {
        project.templateId ?? softwareTemplateId
    }

    func template(for project: Project) -> Template? {
        guard let id = effectiveTemplateId(for: project) else { return nil }
        return templates.first { $0.id == id }
    }

    /// Questions of one template; a question without template_id counts as
    /// software. A nil templateId (templates not loaded and the project
    /// has none) returns every question — today's unfiltered behavior —
    /// rather than an empty, unanswerable flow.
    func questions(forTemplate templateId: UUID?) -> [Question] {
        guard let templateId else { return questions }
        return questions.filter { ($0.templateId ?? softwareTemplateId) == templateId }
    }

    func questions(for project: Project) -> [Question] {
        questions(forTemplate: effectiveTemplateId(for: project))
    }

    /// Generation context for the edge functions: nil for both on the
    /// software template (or when unresolved), so the request stays
    /// byte-identical to the pre-template contract.
    func generationContext(for project: Project) -> (templateName: String?, domainLabels: [String: String]?) {
        guard let template = template(for: project),
              template.key != Self.softwareTemplateKey else { return (nil, nil) }
        return (template.nameSv, template.domainLabels["sv"])
    }

    func groupedByDomain(templateId: UUID?) -> [(domain: Domain, questions: [Question])] {
        let templateQuestions = questions(forTemplate: templateId)
        return Domain.allCases.map { domain in
            let domainQuestions = templateQuestions
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
        // Separate catch: a templates failure must not touch questions.
        do {
            templates = try await supabase
                .from("templates")
                .select()
                .execute()
                .value
        } catch {
            print("QuestionStore templates fetch error: \(error)")
        }
    }
}
