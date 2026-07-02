//
//  NoteStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-02.
//

import Foundation
import Supabase

enum NoteSaveStatus: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed
}

// MARK: - DB models

private struct ProjectDocument: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var content: String
    var type: String
    var updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, content, type
        case projectId = "project_id"
        case updatedAt = "updated_at"
    }
}

private struct NewNote: Encodable {
    let project_id: UUID
    let content: String
    let type: String
}

private struct UpdateNote: Encodable {
    let content: String
}

// MARK: - NoteStore

@MainActor
@Observable
class NoteStore {
    var content = ""
    var status: NoteSaveStatus = .idle
    private(set) var isLoaded = false

    private var documentId: UUID? = nil
    private var lastPersistedContent = ""
    private var saveTask: Task<Void, Never>? = nil
    private var projectId: UUID? = nil

    func fetch(projectId: UUID) async {
        self.projectId = projectId
        do {
            let docs: [ProjectDocument] = try await supabase
                .from("documents")
                .select()
                .eq("project_id", value: projectId)
                .eq("type", value: "note")
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()
                .value
            if let doc = docs.first {
                content = doc.content
                documentId = doc.id
                lastPersistedContent = doc.content
            }
        } catch {
            print("NoteStore fetch error: \(error)")
        }
        isLoaded = true
    }

    /// Debounce ägd av storen: en väntande sparning överlever segment-byten,
    /// och Tasken håller storen vid liv tills skrivningen är klar även om
    /// hela projektvyn poppas.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    func save() async {
        guard let projectId else { return }
        // Snapshot: det är denna text som skickas, så det är den som ska
        // bokföras som persisterad — inte tangenttryck som landar under awaiten.
        let snapshot = content
        // No-op: inget har ändrats sedan senaste lyckade skrivning.
        if snapshot == lastPersistedContent { return }
        // Skydd: ett tömt fält får aldrig tyst skriva över en sparad anteckning.
        // Avsiktlig rensning går via clear(), som är enda tillåtna vägen
        // att persistera tom text.
        if snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastPersistedContent.isEmpty {
            return
        }
        status = .saving
        do {
            if let existingId = documentId {
                try await supabase
                    .from("documents")
                    .update(UpdateNote(content: snapshot))
                    .eq("id", value: existingId)
                    .execute()
            } else {
                let inserted: ProjectDocument = try await supabase
                    .from("documents")
                    .insert(NewNote(project_id: projectId, content: snapshot, type: "note"))
                    .select()
                    .single()
                    .execute()
                    .value
                documentId = inserted.id
            }
            lastPersistedContent = snapshot
            status = .saved(Date())
        } catch {
            // content lämnas orörd — det skrivna finns kvar i minnet och
            // nästa lyckade sparning rensar .failed.
            status = .failed
            print("NoteStore save error: \(error)")
        }
    }

    /// Avsiktlig rensning — enda vägen förbi tomt-skyddet i save().
    /// Uppdaterar raden till "" i stället för att radera den, så framtida
    /// redigeringar stannar på update-vägen och UI:t ser identiskt ut
    /// (placeholdern styrs av content.isEmpty).
    func clear() async {
        saveTask?.cancel()
        guard let existingId = documentId else {
            content = ""
            lastPersistedContent = ""
            return
        }
        status = .saving
        do {
            try await supabase
                .from("documents")
                .update(UpdateNote(content: ""))
                .eq("id", value: existingId)
                .execute()
            lastPersistedContent = ""
            content = ""
            status = .saved(Date())
        } catch {
            // Fältet behåller gammal text — servern rensades aldrig.
            status = .failed
            print("NoteStore clear error: \(error)")
        }
    }
}
