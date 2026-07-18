//
//  HealthOverviewStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-16.
//

import Foundation
import Supabase

/// One team's aggregated health for the Översikt dashboard.
struct TeamHealth: Identifiable {
    let project: Project
    /// The latest COMPLETED assessment's six domain scores;
    /// nil = no completed assessment yet (placeholder card).
    let latestScores: [DomainScore]?
    /// total(latest) − total(previous); nil with fewer than two completed.
    let delta: Int?
    /// Exactly one completed assessment — renders the "NY" chip.
    let isNew: Bool
    let openCount: Int

    /// Headline risk: the lowest-scoring domain of the latest assessment.
    var weakest: DomainScore? {
        latestScores?.min { $0.score < $1.score }
    }

    var id: UUID { project.id }
}

@MainActor
@Observable
class HealthOverviewStore {
    var rows: [TeamHealth] = []
    var isLoading = false
    var error: Error? = nil

    private struct OpenActionRef: Decodable {
        let projectId: UUID

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
        }
    }

    /// Fixed query count regardless of team count — no N+1: the shared
    /// provider (projects + assessments + paginated answers, deduped with
    /// the Tasks lens) and the open-action counts. Trend = total-score
    /// delta between the two newest completed assessments.
    func load(questionStore: QuestionStore, provider: OversiktScoresProvider, showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }
        error = nil
        do {
            let snapshot = try await provider.load(questionStore: questionStore)
            let projects = snapshot.projects
            let scoreData = snapshot.scores

            let openRows: [OpenActionRef] = try await supabase
                .from("actions")
                .select("project_id")
                .neq("state", value: "done")
                .execute()
                .value
            var openCounts: [UUID: Int] = [:]
            for row in openRows {
                openCounts[row.projectId, default: 0] += 1
            }

            rows = projects.map { project in
                let completed = scoreData.completedByProject[project.id] ?? []

                let latest = completed.first.map(scoreData.scores(for:))
                var delta: Int? = nil
                if let latest, completed.count >= 2 {
                    delta = ScoringService.total(latest)
                        - ScoringService.total(scoreData.scores(for: completed[1]))
                }

                return TeamHealth(
                    project: project,
                    latestScores: latest,
                    delta: delta,
                    isNew: completed.count == 1,
                    openCount: openCounts[project.id] ?? 0
                )
            }
        } catch is CancellationError {
            // Cancelled by a newer load or view teardown (pull-to-refresh,
            // tab switch) — not a failure: keep current rows, no error view.
        } catch let error as URLError where error.code == .cancelled {
            // The same abort surfaced at the URLSession layer instead.
        } catch {
            self.error = error
            print("HealthOverviewStore load error: \(error)")
        }
    }
}
