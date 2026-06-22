//
//  ActionStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-06-11.
//

import Foundation
import Supabase

struct ProjectAction: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var domain: String
    var title: String
    var status: String
    var assessmentId: UUID?
    var insightId: UUID?
    var createdFromScore: Int?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, domain, title, status
        case projectId = "project_id"
        case assessmentId = "assessment_id"
        case insightId = "insight_id"
        case createdFromScore = "created_from_score"
        case createdAt = "created_at"
    }

    var isDone: Bool { status == "done" }
}

private struct NewAction: Encodable {
    let project_id: UUID
    let domain: String
    let title: String
    let assessment_id: UUID?
    let insight_id: UUID?
    let created_from_score: Int?
}

private struct StatusUpdate: Encodable {
    let status: String
}

@MainActor
@Observable
class ActionStore {
    var actions: [ProjectAction] = []
    var error: Error? = nil

    func fetch(projectId: UUID) async {
        do {
            actions = try await supabase
                .from("actions")
                .select()
                .eq("project_id", value: projectId)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error
            print("ActionStore fetch error: \(error)")
        }
    }

    func add(
        projectId: UUID,
        domain: String,
        title: String,
        assessmentId: UUID?,
        insightId: UUID? = nil,
        createdFromScore: Int?
    ) async throws {
        let inserted: ProjectAction = try await supabase
            .from("actions")
            .insert(NewAction(
                project_id: projectId,
                domain: domain,
                title: title,
                assessment_id: assessmentId,
                insight_id: insightId,
                created_from_score: createdFromScore
            ))
            .select()
            .single()
            .execute()
            .value
        actions.insert(inserted, at: 0)
    }

    func toggle(_ action: ProjectAction) async {
        let newStatus = action.status == "open" ? "done" : "open"
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index].status = newStatus
        do {
            try await supabase
                .from("actions")
                .update(StatusUpdate(status: newStatus))
                .eq("id", value: action.id)
                .execute()
        } catch {
            if let index = actions.firstIndex(where: { $0.id == action.id }) {
                actions[index].status = action.status
            }
            print("ActionStore toggle error: \(error)")
        }
    }

    func delete(_ action: ProjectAction) async throws {
        try await supabase
            .from("actions")
            .delete()
            .eq("id", value: action.id)
            .execute()
        actions.removeAll { $0.id == action.id }
    }
}
