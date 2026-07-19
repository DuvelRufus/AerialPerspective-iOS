//
//  LinksStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-19.
//

import Foundation
import Supabase

// MARK: - Model

struct ProjectLink: Identifiable, Codable, Equatable {
    let id: UUID
    var projectId: UUID
    var title: String
    var url: String
    var category: String
    var faviconUrl: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, url, category
        case projectId = "project_id"
        case faviconUrl = "favicon_url"
        case createdAt = "created_at"
    }
}

// MARK: - Payloads

private struct NewLink: Encodable {
    let project_id: UUID
    let title: String
    let url: String
    let category: String
    let favicon_url: String?
}

// MARK: - Favicon policy

/// Härledning, inte hämtning: ren URL-konstruktion från länkens host —
/// inget nätverksanrop. Googles tjänst svarar med en generisk glob-ikon
/// för okända hosts, så nil-fallet är bara host-lös/ogiltig URL.
enum FaviconPolicy {
    static func faviconUrl(for linkUrl: String) -> String? {
        guard let host = URLComponents(string: linkUrl)?.host, !host.isEmpty else { return nil }
        return "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
    }
}

// MARK: - LinksStore

@MainActor
@Observable
class LinksStore {
    var links: [ProjectLink] = []
    var isLoading = false
    var error: Error? = nil

    func fetch(projectId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            links = try await supabase
                .from("links")
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
            // links lämnas orörda: en misslyckad refetch får inte tömma en
            // fylld lista.
            self.error = error
            print("LinksStore fetch error: \(error)")
        }
    }

    /// `url` är redan LinkURLPolicy-normaliserad av AddLinkSheet, så hosten
    /// finns att härleda favicon ur.
    func add(projectId: UUID, title: String, url: String, category: String) async throws {
        let inserted: ProjectLink = try await supabase
            .from("links")
            .insert(NewLink(
                project_id: projectId,
                title: title,
                url: url,
                category: category,
                favicon_url: FaviconPolicy.faviconUrl(for: url)
            ))
            .select()
            .single()
            .execute()
            .value
        links.insert(inserted, at: 0)
    }

    /// Hard delete with optimistic removal; the row is re-inserted at its
    /// old position if the DELETE fails.
    func delete(_ link: ProjectLink) async {
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        let removed = links.remove(at: index)
        do {
            try await supabase
                .from("links")
                .delete()
                .eq("id", value: link.id)
                .execute()
        } catch {
            links.insert(removed, at: min(index, links.count))
            print("LinksStore delete error: \(error)")
        }
    }
}
