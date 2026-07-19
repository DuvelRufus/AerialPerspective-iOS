//
//  NotesStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-19.
//

import Foundation
import Supabase

// MARK: - Model

// Hashable: navigationDestination(item:)-pushen till redigeringsvyn kräver det.
struct Note: Identifiable, Codable, Hashable {
    let id: UUID
    var projectId: UUID
    var title: String
    var body: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, tags
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Payloads

private struct NewNote: Encodable {
    let project_id: UUID
    let title: String
    let body: String
    let tags: [String]
}

/// updated_at skickas aldrig — moddatetime-triggern i DB äger den kolumnen.
private struct NoteUpdate: Encodable {
    let title: String
    let body: String
    let tags: [String]
}

// MARK: - NotesStore

@MainActor
@Observable
class NotesStore {
    var notes: [Note] = []
    var isLoading = false
    var error: Error? = nil

    func fetch(projectId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            notes = try await supabase
                .from("notes")
                .select()
                .eq("project_id", value: projectId)
                .order("updated_at", ascending: false)
                .execute()
                .value
        } catch is CancellationError {
            // Cancelled by a newer load or view teardown — not a failure:
            // keep current rows, no error state.
        } catch let error as URLError where error.code == .cancelled {
            // The same abort surfaced at the URLSession layer instead.
        } catch {
            // notes lämnas orörda: en misslyckad refetch får inte tömma en
            // fylld lista.
            self.error = error
            print("NotesStore fetch error: \(error)")
        }
    }

    func add(projectId: UUID, title: String, body: String, tags: [String]) async throws {
        let inserted: Note = try await supabase
            .from("notes")
            .insert(NewNote(project_id: projectId, title: title, body: body, tags: tags))
            .select()
            .single()
            .execute()
            .value
        notes.insert(inserted, at: 0)
    }

    /// Optimistic title/body edit with rollback. The returned server row
    /// (carrying the trigger-set updated_at) replaces the local element on
    /// success; the list is deliberately not re-sorted in place so rows don't
    /// jump mid-edit — the next fetch reorders.
    func update(_ note: Note) async {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let original = notes[index]
        notes[index].title = note.title
        notes[index].body = note.body
        notes[index].tags = note.tags
        do {
            let updated: Note = try await supabase
                .from("notes")
                .update(NoteUpdate(title: note.title, body: note.body, tags: note.tags))
                .eq("id", value: note.id)
                .select()
                .single()
                .execute()
                .value
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = updated
            }
        } catch {
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = original
            }
            print("NotesStore update error: \(error)")
        }
    }

    /// Hard delete with optimistic removal; the row is re-inserted at its
    /// old position if the DELETE fails.
    func delete(_ note: Note) async {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let removed = notes.remove(at: index)
        do {
            try await supabase
                .from("notes")
                .delete()
                .eq("id", value: note.id)
                .execute()
        } catch {
            notes.insert(removed, at: min(index, notes.count))
            print("NotesStore delete error: \(error)")
        }
    }
}
