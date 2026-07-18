//
//  ActionStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-06-11.
//

import Foundation
import Supabase

/// The actions.state column. `open`/`done` drive today's UI; `prio` and
/// `waiting` get affordances in a later change.
enum TaskState: String {
    case open, prio, waiting, done
}

// Equatable so section moves can animate on .animation(value: actions).
struct ProjectAction: Identifiable, Codable, Equatable {
    let id: UUID
    var projectId: UUID
    var domain: String
    var title: String
    /// Source of truth. Plain String at the DB boundary; use taskState.
    var state: String
    var assessmentId: UUID?
    var insightId: UUID?
    var planActionId: UUID?
    var createdFromScore: Int?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, domain, title, state
        case projectId = "project_id"
        case assessmentId = "assessment_id"
        case insightId = "insight_id"
        case planActionId = "plan_action_id"
        case createdFromScore = "created_from_score"
        case createdAt = "created_at"
    }

    /// Unknown DB values degrade to .open instead of failing decode.
    var taskState: TaskState { TaskState(rawValue: state) ?? .open }

    var isDone: Bool { taskState == .done }
}

private struct NewAction: Encodable {
    let project_id: UUID
    let domain: String
    let title: String
    let state: String?
    let assessment_id: UUID?
    let insight_id: UUID?
    let plan_action_id: UUID?
    let created_from_score: Int?
}

/// R5: state is the only status column — the legacy dual-write is gone.
private struct StateUpdate: Encodable {
    let state: String
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

    /// The action created from a given plan item, if any. Computed over the
    /// already-loaded `actions` — does not fetch. Plan draws the row done
    /// when isDone; nil and non-nil-but-open both draw as the empty circle.
    func action(forPlanItem id: UUID) -> ProjectAction? {
        actions.first { $0.planActionId == id }
    }

    func add(
        projectId: UUID,
        domain: String,
        title: String,
        state: String? = nil,
        assessmentId: UUID?,
        insightId: UUID? = nil,
        planActionId: UUID? = nil,
        createdFromScore: Int?
    ) async throws {
        let inserted: ProjectAction = try await supabase
            .from("actions")
            .insert(NewAction(
                project_id: projectId,
                domain: domain,
                title: title,
                // nil rides the DB default ('open'); createLinkedAction
                // passes done/prio/waiting explicitly.
                state: state,
                assessment_id: assessmentId,
                insight_id: insightId,
                plan_action_id: planActionId,
                created_from_score: createdFromScore
            ))
            .select()
            .single()
            .execute()
            .value
        actions.insert(inserted, at: 0)
    }

    /// Sets the state column (the only status column since R5) with
    /// optimistic update and rollback.
    func setState(_ action: ProjectAction, to newState: TaskState) async {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index].state = newState.rawValue
        do {
            try await supabase
                .from("actions")
                .update(StateUpdate(state: newState.rawValue))
                .eq("id", value: action.id)
                .execute()
        } catch {
            if let index = actions.firstIndex(where: { $0.id == action.id }) {
                actions[index].state = action.state
            }
            print("ActionStore setState error: \(error)")
        }
    }

    func toggle(_ action: ProjectAction) async {
        // Un-toggling done lands on "open" regardless of any earlier
        // prio/waiting — decided; sections (R4b-2) may revisit.
        await setState(action, to: action.isDone ? .open : .done)
    }

    /// Hard delete with optimistic removal; the row is re-inserted at its
    /// old position if the DELETE fails.
    func delete(_ action: ProjectAction) async {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        let removed = actions.remove(at: index)
        do {
            try await supabase
                .from("actions")
                .delete()
                .eq("id", value: action.id)
                .execute()
        } catch {
            actions.insert(removed, at: min(index, actions.count))
            print("ActionStore delete error: \(error)")
        }
    }
}
