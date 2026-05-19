//
//  ProjectStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

struct ProjectInsert: Encodable {
    let name: String
    let user_id: UUID
}

@MainActor
@Observable
class ProjectStore {
    var projects: [Project] = []
    var isLoading = false
    var error: Error? = nil

    func fetch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await supabase
                .from("projects")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error
            print("ProjectStore fetch error: \(error)")
        }
    }

    func create(name: String) async throws -> Project {
        let user = try await supabase.auth.user()
        let insert = ProjectInsert(name: name, user_id: user.id)
        let project: Project = try await supabase
            .from("projects")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
        projects.insert(project, at: 0)
        return project
    }

    func delete(_ project: Project) async throws {
        try await supabase
            .from("projects")
            .delete()
            .eq("id", value: project.id)
            .execute()
        projects.removeAll { $0.id == project.id }
    }
}
