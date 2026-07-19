//
//  ContactsStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-19.
//

import Foundation
import Supabase

// MARK: - Model

struct Contact: Identifiable, Codable, Equatable {
    let id: UUID
    var projectId: UUID
    var name: String
    var role: String?
    var contactInfo: String?
    var avatarColor: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case projectId = "project_id"
        case contactInfo = "contact_info"
        case avatarColor = "avatar_color"
        case createdAt = "created_at"
    }
}

// MARK: - Payloads

private struct NewContact: Encodable {
    let project_id: UUID
    let name: String
    let role: String?
    let contact_info: String?
    let avatar_color: String?
}

// MARK: - ContactsStore

@MainActor
@Observable
class ContactsStore {
    var contacts: [Contact] = []
    var isLoading = false
    var error: Error? = nil

    func fetch(projectId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            contacts = try await supabase
                .from("contacts")
                .select()
                .eq("project_id", value: projectId)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch is CancellationError {
            // Cancelled by a newer load or view teardown — not a failure:
            // keep current rows, no error state.
        } catch let error as URLError where error.code == .cancelled {
            // The same abort surfaced at the URLSession layer instead.
        } catch {
            // contacts lämnas orörda: en misslyckad refetch får inte tömma
            // en fylld lista.
            self.error = error
            print("ContactsStore fetch error: \(error)")
        }
    }

    /// avatarColor är den valda palettfärgen (#RRGGBB) eller nil — detta
    /// steg skickar callern alltid nil; färgväljaren kommer i layout-steget.
    func add(
        projectId: UUID,
        name: String,
        role: String?,
        contactInfo: String?,
        avatarColor: String?
    ) async throws {
        let inserted: Contact = try await supabase
            .from("contacts")
            .insert(NewContact(
                project_id: projectId,
                name: name,
                role: role,
                contact_info: contactInfo,
                avatar_color: avatarColor
            ))
            .select()
            .single()
            .execute()
            .value
        contacts.insert(inserted, at: 0)
    }

    /// Hard delete with optimistic removal; the row is re-inserted at its
    /// old position if the DELETE fails.
    func delete(_ contact: Contact) async {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        let removed = contacts.remove(at: index)
        do {
            try await supabase
                .from("contacts")
                .delete()
                .eq("id", value: contact.id)
                .execute()
        } catch {
            contacts.insert(removed, at: min(index, contacts.count))
            print("ContactsStore delete error: \(error)")
        }
    }
}
