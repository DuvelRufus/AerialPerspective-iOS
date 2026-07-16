//
//  PlanStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-13.
//

import Foundation
import Supabase

@MainActor
@Observable
class PlanStore {
    var activePlan: Plan? = nil
    var actions: [PlanActionRow] = []
    /// Assessments that have an active plan — byproduct of the same query
    /// loadNewestActivePlan already runs; drives the per-assessment
    /// generate gate without an extra round-trip.
    var activeAssessmentIds: Set<UUID> = []
    var isLoading = false
    var error: Error? = nil

    /// Loads the active plans row of the newest assessment that has one,
    /// plus its plan_actions. `assessmentIdsNewestFirst` decides precedence.
    /// Read-only — plan writes (generation/regeneration) land via a later
    /// RPC, never through this store's fetches. On error both stay empty,
    /// which lets PlanView fall back to the legacy JSONB plan.
    func loadNewestActivePlan(assessmentIdsNewestFirst: [UUID]) async {
        isLoading = true
        defer { isLoading = false }
        activePlan = nil
        actions = []
        activeAssessmentIds = []
        guard !assessmentIdsNewestFirst.isEmpty else { return }
        do {
            let plans: [Plan] = try await supabase
                .from("plans")
                .select()
                .in("assessment_id", values: assessmentIdsNewestFirst.map(\.uuidString))
                .eq("is_active", value: true)
                .execute()
                .value
            activeAssessmentIds = Set(plans.map(\.assessmentId))
            guard let plan = assessmentIdsNewestFirst
                .lazy
                .compactMap({ id in plans.first { $0.assessmentId == id } })
                .first
            else { return }
            activePlan = plan
            actions = try await supabase
                .from("plan_actions")
                .select()
                .eq("plan_id", value: plan.id)
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error
            print("PlanStore load error: \(error)")
        }
    }

    /// Plan curation: removes one plan_actions row. The linked actions row
    /// is never touched — the FK's ON DELETE SET NULL detaches it, so the
    /// task survives in Åtgärder. Throwing: the view owns the optimistic
    /// removal/rollback of its visible list.
    func deletePlanAction(_ id: UUID) async throws {
        try await supabase
            .from("plan_actions")
            .delete()
            .eq("id", value: id)
            .execute()
        actions.removeAll { $0.id == id }
    }

    /// Persists a generated plan through the regenerate_plan RPC: inserts
    /// the new plan + actions, re-links tasks via prev_id, archives the
    /// outgoing active plan and activates the new one — atomically. Also
    /// the first-generation path (nothing to deactivate then).
    func regenerate(assessmentId: UUID, plan: RegeneratedPlanPayload) async throws {
        struct Params: Encodable {
            let p_assessment_id: UUID
            let p_plan: RegeneratedPlanPayload
        }
        try await supabase
            .rpc("regenerate_plan", params: Params(p_assessment_id: assessmentId, p_plan: plan))
            .execute()
    }

    /// ref → prev_id translation per the regeneration contract: a ref that
    /// names a known key keeps its identity the FIRST time it appears;
    /// unknown or already-used refs are dropped (first-wins) and the action
    /// is treated as new. `ref` itself is never serialized to the RPC.
    static func translate(_ generated: GeneratedPlan, keyMap: [String: UUID]) -> RegeneratedPlanPayload {
        var usedKeys: Set<String> = []

        func phase(_ p: GeneratedPhase) -> RegeneratedPlanPayload.Phase {
            let actions = p.actions.map { action -> RegeneratedPlanPayload.Action in
                var prevId: UUID? = nil
                if let ref = action.ref, let mapped = keyMap[ref], !usedKeys.contains(ref) {
                    usedKeys.insert(ref)
                    prevId = mapped
                }
                return RegeneratedPlanPayload.Action(
                    text: action.text,
                    domain: action.domain,
                    prev_id: prevId
                )
            }
            return RegeneratedPlanPayload.Phase(focus: p.focus, actions: actions)
        }

        return RegeneratedPlanPayload(
            summary: generated.summary,
            day1_30: phase(generated.day1_30),
            day31_60: phase(generated.day31_60),
            day61_90: phase(generated.day61_90)
        )
    }
}

/// The p_plan jsonb argument of regenerate_plan.
struct RegeneratedPlanPayload: Encodable {
    struct Action: Encodable {
        let text: String
        let domain: String?
        let prev_id: UUID?
    }

    struct Phase: Encodable {
        let focus: String
        let actions: [Action]
    }

    let summary: String
    let day1_30: Phase
    let day31_60: Phase
    let day61_90: Phase
}
