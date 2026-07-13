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
        guard !assessmentIdsNewestFirst.isEmpty else { return }
        do {
            let plans: [Plan] = try await supabase
                .from("plans")
                .select()
                .in("assessment_id", values: assessmentIdsNewestFirst.map(\.uuidString))
                .eq("is_active", value: true)
                .execute()
                .value
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
}
