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

    func fetch(assessmentId: UUID) async {
        isLoading = true
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
            print("InsightStore fetch error: \(error)")
        }
    }

    func save(_ insights: [Insight], for assessmentId: UUID) async throws {
        try await supabase
            .from("insights")
            .delete()
            .eq("assessment_id", value: assessmentId)
            .execute()

        if !insights.isEmpty {
            let rows = insights.map { InsightInsert(from: $0, assessmentId: assessmentId) }
            try await supabase
                .from("insights")
                .insert(rows)
                .execute()
        }

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

