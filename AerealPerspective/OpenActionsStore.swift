//
//  OpenActionsStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-16.
//

import Foundation
import Supabase

/// One row in the global Tasks lens: an open action plus the context the
/// lens renders per row but the action itself doesn't carry.
struct OpenActionRow: Identifiable {
    let action: ProjectAction
    let teamName: String
    /// Current score of the action's domain (latest completed assessment);
    /// nil = unresolvable domain or no completed assessment, sorts last.
    let urgency: Int?

    var id: UUID { action.id }
}

@MainActor
@Observable
class OpenActionsStore {
    var prio: [OpenActionRow] = []
    var open: [OpenActionRow] = []
    var waiting: [OpenActionRow] = []
    var isLoading = false
    var error: Error? = nil

    /// Fixed query count regardless of team count — no N+1: one query for
    /// ALL open actions (state != 'done', the only status column since
    /// R5), plus the same
    /// projects/assessments/answers batch HealthOverviewStore uses so
    /// urgency can be the action's CURRENT domain score — the same sort key
    /// PlanView.urgency uses, keeping the lens and Plan consistent.
    func load(questionStore: QuestionStore, provider: OversiktScoresProvider, showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }
        error = nil
        do {
            // The two fetches are independent — run them concurrently; the
            // provider dedupes projects+scores with the Team lens.
            async let actionsFetch: [ProjectAction] = supabase
                .from("actions")
                .select()
                .neq("state", value: "done")
                .execute()
                .value
            async let snapshotFetch = provider.load(questionStore: questionStore)

            let actions = try await actionsFetch
            let snapshot = try await snapshotFetch
            let nameByProject = Dictionary(
                uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.name) }
            )
            let scoresByProject = snapshot.scores.latestScoresByProject()

            var groups: [TaskState: [OpenActionRow]] = [:]
            for action in actions {
                // Orphaned actions (project deleted / not visible) are dropped.
                guard let teamName = nameByProject[action.projectId] else { continue }
                let state = action.taskState
                guard state != .done else { continue }
                var urgency: Int? = nil
                if let domain = Domain(caseInsensitive: action.domain) {
                    urgency = scoresByProject[action.projectId]?
                        .first(where: { $0.domain == domain })?.score
                }
                groups[state, default: []].append(
                    OpenActionRow(action: action, teamName: teamName, urgency: urgency)
                )
            }

            prio = sortedByUrgency(groups[.prio] ?? [])
            open = sortedByUrgency(groups[.open] ?? [])
            waiting = sortedByUrgency(groups[.waiting] ?? [])
        } catch is CancellationError {
            // Cancelled by a newer load or view teardown (pull-to-refresh,
            // segment switch) — not a failure: keep current rows, no error view.
        } catch let error as URLError where error.code == .cancelled {
            // The same abort surfaced at the URLSession layer instead.
        } catch {
            self.error = error
            print("OpenActionsStore load error: \(error)")
        }
    }

    /// Spinner-free refresh for pull-to-refresh, mirroring
    /// HealthOverviewStore's showSpinner: false path.
    func reload(questionStore: QuestionStore, provider: OversiktScoresProvider) async {
        await load(questionStore: questionStore, provider: provider, showSpinner: false)
    }

    /// Lowest current domain score first (most urgent on top), nil last;
    /// ties break newest-first on createdAt — Plan's tie-break (flat plan
    /// index) has no global equivalent.
    private func sortedByUrgency(_ rows: [OpenActionRow]) -> [OpenActionRow] {
        rows.sorted { a, b in
            let ua = a.urgency ?? Int.max
            let ub = b.urgency ?? Int.max
            if ua != ub { return ua < ub }
            return a.action.createdAt > b.action.createdAt
        }
    }

}
