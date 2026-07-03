//
//  InsightStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-19.
//

import Foundation
import Supabase

@MainActor
@Observable
class InsightStore {
    var insights: [Insight] = []
    var isLoading = false
    var error: Error? = nil

    func fetch(assessmentId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            insights = try await supabase
                .from("insights")
                .select()
                .eq("assessment_id", value: assessmentId)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            // insights lämnas orörda: en misslyckad refetch får inte tömma en
            // fylld array — tom array är det som visar generera-knappen i vyn.
            self.error = error
            print("InsightStore fetch error: \(error)")
        }
    }

    /// Insert-only, avsiktligt: delete-all-först var mekanismen som raderade
    /// insikter permanent vid misslyckad insert och bröt insight_id-länkar på
    /// skapade åtgärder (SET NULL-FK). Klienten kan bara lägga till rader.
    func save(_ insights: [Insight], for assessmentId: UUID) async throws {
        guard !insights.isEmpty else { return }
        let rows = insights.map { InsightInsert(from: $0, assessmentId: assessmentId) }
        try await supabase
            .from("insights")
            .insert(rows)
            .execute()
        await fetch(assessmentId: assessmentId)
    }
}

// MARK: - Insert payload

private struct InsightInsert: Encodable {
    let assessment_id: UUID
    let title: String?
    let content: String?
    let risk_level: String?
    let domain: String?
    let suggested_action: String?

    init(from insight: Insight, assessmentId: UUID) {
        self.assessment_id = assessmentId
        self.title = insight.title
        self.content = insight.content
        self.risk_level = insight.riskLevel?.rawValue
        self.domain = insight.domain
        self.suggested_action = insight.suggestedAction
    }
}

