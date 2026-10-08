//
//  ActionStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-06-11.
//

import Foundation
import Supabase

/// The actions.state column. open/prio/waiting are the to-do states
/// (Todo column in kanban), doing is work in progress, done is finished.
/// Unknown DB values still read as .open (ProjectAction.taskState).
enum TaskState: String {
    case open, prio, doing, waiting, done
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
    /// Set to now() by a DB trigger when state becomes done, cleared when
    /// it leaves done. The client writes it ONLY via setCompletedDate
    /// (never NewAction/StateUpdate). nil on tasks completed before the
    /// column existed.
    var completedAt: Date?
    /// true = completedAt was set by hand afterwards (an approximation);
    /// the trigger resets it with every state change.
    var completedAtManual: Bool

    enum CodingKeys: String, CodingKey {
        case id, domain, title, state
        case projectId = "project_id"
        case assessmentId = "assessment_id"
        case insightId = "insight_id"
        case planActionId = "plan_action_id"
        case createdFromScore = "created_from_score"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case completedAtManual = "completed_at_manual"
    }

    /// Unknown DB values degrade to .open instead of failing decode.
    var taskState: TaskState { TaskState(rawValue: state) ?? .open }

    var isDone: Bool { taskState == .done }

    /// Derived from the link columns; the plan link wins over the insight
    /// link. A link the DB nulled (SET NULL) reads as .own.
    var origin: ActionOrigin {
        if planActionId != nil { return .plan }
        if insightId != nil { return .insight }
        return .own
    }
}

/// Where a task came from — display only, never stored.
enum ActionOrigin {
    case plan, insight, own

    var label: String {
        switch self {
        case .plan:    return "Plan"
        case .insight: return "Insikt"
        case .own:     return "Egen"
        }
    }
}

// In an extension so the memberwise initializer survives.
extension ProjectAction {
    /// Synthesized decoding except completedAtManual: a missing or null
    /// column degrades to false instead of failing the whole array (which
    /// would empty the task list silently).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        domain = try c.decode(String.self, forKey: .domain)
        title = try c.decode(String.self, forKey: .title)
        state = try c.decode(String.self, forKey: .state)
        assessmentId = try c.decodeIfPresent(UUID.self, forKey: .assessmentId)
        insightId = try c.decodeIfPresent(UUID.self, forKey: .insightId)
        planActionId = try c.decodeIfPresent(UUID.self, forKey: .planActionId)
        createdFromScore = try c.decodeIfPresent(Int.self, forKey: .createdFromScore)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        completedAtManual = try c.decodeIfPresent(Bool.self, forKey: .completedAtManual) ?? false
    }
}

enum ActionStoreError: LocalizedError {
    /// The guarded update matched no row: the task is no longer done (or
    /// is gone / not visible to this user).
    case notDone
    /// A state update matched no row: the task is gone or not visible.
    case notFound
    /// A title/domain edit matched no row: the task is gone or not visible.
    case editNotSaved

    var errorDescription: String? {
        switch self {
        case .notDone:
            return "Uppgiften är inte längre markerad som klar. Datumet sparades inte."
        case .notFound:
            return "Uppgiften hittades inte. Statusen sparades inte."
        case .editNotSaved:
            return "Ändringen sparades inte."
        }
    }
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

/// The ONLY client write of completed_at — a manual date on a done task.
/// The trigger leaves a completed_at-only update on a done row untouched.
private struct CompletedDateUpdate: Encodable {
    let completed_at: Date
    let completed_at_manual: Bool
}

/// Title and/or domain edit. Only the fields that changed are encoded;
/// never state or the completed_at columns.
private struct TitleDomainUpdate: Encodable {
    let title: String?
    let domain: String?

    enum CodingKeys: String, CodingKey {
        case title, domain
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(domain, forKey: .domain)
    }
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
    /// optimistic update and rollback. Throws after rolling back, so the
    /// caller can show the failure — no silent rollback.
    func setState(_ action: ProjectAction, to newState: TaskState) async throws {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index].state = newState.rawValue
        do {
            // Returning the row keeps the trigger-owned completedAt /
            // completedAtManual current without a refetch. Applied only if
            // no newer state change landed locally meanwhile, so a late
            // response can't undo a faster second tap.
            let rows: [ProjectAction] = try await supabase
                .from("actions")
                .update(StateUpdate(state: newState.rawValue))
                .eq("id", value: action.id)
                .select()
                .execute()
                .value
            // Zero matched rows (deleted / not visible) is a failure too —
            // otherwise the optimistic state would stick locally.
            guard let row = rows.first else { throw ActionStoreError.notFound }
            if let index = actions.firstIndex(where: { $0.id == action.id }),
               actions[index].state == newState.rawValue {
                actions[index] = row
            }
        } catch {
            if let index = actions.firstIndex(where: { $0.id == action.id }) {
                actions[index].state = action.state
            }
            print("ActionStore setState error: \(error)")
            throw error
        }
    }

    /// Manual completion date on a done task. Guarded on state = done so a
    /// task reopened meanwhile can't get a date; zero matched rows throws.
    func setCompletedDate(actionId: UUID, date: Date) async throws {
        let rows: [ProjectAction] = try await supabase
            .from("actions")
            .update(CompletedDateUpdate(completed_at: date, completed_at_manual: true))
            .eq("id", value: actionId)
            .eq("state", value: "done")
            .select()
            .execute()
            .value
        guard let row = rows.first else { throw ActionStoreError.notDone }
        if let index = actions.firstIndex(where: { $0.id == actionId }) {
            actions[index] = row
        }
    }

    /// Edits title and/or domain; nil leaves that column untouched. The
    /// returned row replaces the local one; zero matched rows throws.
    func update(_ action: ProjectAction, title: String?, domain: Domain?) async throws {
        guard title != nil || domain != nil else { return }
        do {
            let rows: [ProjectAction] = try await supabase
                .from("actions")
                .update(TitleDomainUpdate(title: title, domain: domain?.rawValue))
                .eq("id", value: action.id)
                .select()
                .execute()
                .value
            guard let row = rows.first else { throw ActionStoreError.editNotSaved }
            if let index = actions.firstIndex(where: { $0.id == action.id }) {
                actions[index] = row
            }
        } catch {
            print("ActionStore update error: \(error)")
            throw error
        }
    }

    func toggle(_ action: ProjectAction) async throws {
        // Un-toggling done lands on "open" regardless of any earlier
        // prio/doing/waiting — decided; sections (R4b-2) may revisit.
        try await setState(action, to: action.isDone ? .open : .done)
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
