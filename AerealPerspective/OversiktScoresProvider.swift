//
//  OversiktScoresProvider.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-18.
//

import Foundation

/// Shared, lazily-filled cache for Översikt's two lenses: ONE
/// assessments+answers derivation and ONE projects fetch per fill
/// instead of one per store. Owned by OversiktView — lives across
/// segment/tab switches, dies with the view, exactly like the stores.
@MainActor
@Observable
class OversiktScoresProvider {
    struct Snapshot {
        let scores: AssessmentScores
        let projects: [Project]
    }

    private var cached: Snapshot?
    private var inFlight: Task<Snapshot, Error>?
    /// Bumped by invalidate(): a stale in-flight result is returned to its
    /// awaiter but never published into the cache.
    private var generation = 0

    /// Cached snapshot, or await the in-flight load, or start one —
    /// concurrent callers (Team mount + Tasks activation close in time)
    /// share a single underlying fetch.
    func load(questionStore: QuestionStore) async throws -> Snapshot {
        if let cached { return cached }
        if let inFlight { return try await inFlight.value }
        let gen = generation
        let task = Task {
            let projectStore = ProjectStore()
            async let scoresFetch = AssessmentScoresLoader.load(questionStore: questionStore)
            await projectStore.fetch()
            let scores = try await scoresFetch
            if let projectError = projectStore.error { throw projectError }
            return Snapshot(scores: scores, projects: projectStore.projects)
        }
        inFlight = task
        defer { if generation == gen { inFlight = nil } }
        let snapshot = try await task.value
        if generation == gen { cached = snapshot }
        return snapshot
    }

    /// Pull-to-refresh calls this BEFORE the store's reload so the next
    /// load fetches fresh.
    func invalidate() {
        generation += 1
        cached = nil
        inFlight = nil
    }
}
