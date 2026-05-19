//
//  AssessmentStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

@MainActor
@Observable
class AssessmentStore {
    var assessments: [Assessment] = []
    var isLoading = false
    var error: Error? = nil

    func fetch(projectId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            assessments = try await supabase
                .from("assessments")
                .select()
                .eq("project_id", value: projectId)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error
        }
    }

    func createOrFetchLatest(projectId: UUID) async throws -> Assessment {
        if let latest = assessments.last {
            return latest
        }
        return try await create(projectId: projectId, version: 1)
    }

    func createNext(projectId: UUID) async throws -> Assessment {
        let nextVersion = (assessments.map { $0.version }.max() ?? 0) + 1
        return try await create(projectId: projectId, version: nextVersion)
    }

    private func create(projectId: UUID, version: Int) async throws -> Assessment {
        let assessment: Assessment = try await supabase
            .from("assessments")
            .insert([
                "project_id": AnyJSON.string(projectId.uuidString),
                "version": AnyJSON.double(Double(version))
            ])
            .select()
            .single()
            .execute()
            .value
        assessments.append(assessment)
        return assessment
    }
}
