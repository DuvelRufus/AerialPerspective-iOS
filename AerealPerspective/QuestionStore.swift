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
    /// True once the templates fetch succeeded and the software template
    /// resolved; false triggers a refetch of templates on the next fetch().
    var templatesLoaded = false

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
    /// software. A nil templateId means software; if the software template
    /// is unresolved (templates not loaded, or its row dropped) the result
    /// is empty — failing closed rather than mixing every template's
    /// questions. A non-nil templateId filters on the questions' own
    /// template_id, so it works even if that template's row was dropped.
    func questions(forTemplate templateId: UUID?) -> [Question] {
        guard let id = templateId ?? softwareTemplateId else { return [] }
        return questions.filter { ($0.templateId ?? softwareTemplateId) == id }
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

    /// Display label for a domain under a template: the template's
    /// non-empty "sv" label, else the rawValue (software has no labels).
    /// Display only — DB writes and matching keep using rawValue.
    func domainLabel(_ domain: Domain, templateId: UUID?) -> String {
        let id = templateId ?? softwareTemplateId
        if let template = templates.first(where: { $0.id == id }),
           let label = template.domainLabels["sv"]?[domain.rawValue],
           !label.isEmpty {
            return label
        }
        return domain.rawValue
    }

    /// As above for a raw domain string; an unknown key is returned as is.
    func domainLabel(key: String, templateId: UUID?) -> String {
        guard let domain = Domain(caseInsensitive: key) else { return key }
        return domainLabel(domain, templateId: templateId)
    }

    func domainLabel(_ domain: Domain, project: Project) -> String {
        domainLabel(domain, templateId: project.templateId)
    }

    func domainLabel(key: String, project: Project) -> String {
        domainLabel(key: key, templateId: project.templateId)
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
        // Refetched on every call (never skipped when questions are loaded),
        // so a failure or a missing software row is retried next fetch().
        do {
            let rows: [LossyDecodable<Template>] = try await supabase
                .from("templates")
                .select()
                .execute()
                .value
            templates = rows.compactMap { $0.value }
            let dropped = rows.count - templates.count
            if dropped > 0 {
                print("QuestionStore: dropped \(dropped) undecodable template row(s)")
            }
            templatesLoaded = softwareTemplateId != nil
        } catch {
            templatesLoaded = false
            print("QuestionStore templates fetch error: \(error)")
        }
    }
}
