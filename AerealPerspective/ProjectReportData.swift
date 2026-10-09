//
//  ProjectReportData.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-10-06.
//

import Foundation

/// Everything a project (team) report shows, as plain data — no views, no
/// I/O. Built by ProjectReportLoader; a later step renders it.
struct ProjectReportData {
    /// The real name, or the loader's anonymizedName when nameHidden.
    let projectName: String
    let nameHidden: Bool
    /// Task and insight titles were left out by the loader: doneActions
    /// carry an origin placeholder, latestInsights carry no titles.
    let textsHidden: Bool
    /// The project template's display label per domain (domainLabel).
    let templateLabelsPerDomain: [Domain: String]
    let generatedAt: Date

    /// Completed assessments only, oldest version first.
    let series: [AssessmentPoint]
    /// Assessments not (yet) completed — listed as a count only.
    let incompleteAssessmentCount: Int

    /// latest − first per domain and in total; nil with fewer than two
    /// completed assessments.
    let firstToLatestDelta: ScoreDelta?
    /// One per neighbouring pair in `series`, oldest first; empty with
    /// fewer than two completed. Neighbours among COMPLETED assessments,
    /// so a pair can span an incomplete one (v2→v4) — the versions show it.
    /// The pairs telescope: their sum equals firstToLatestDelta.
    let adjacentDeltas: [AdjacentDelta]

    /// Keyed by the matched Domain; action rows whose domain string
    /// matches no Domain are counted in unknownDomainActions instead.
    let actionsPerDomain: [Domain: ActionCounts]
    let unknownDomainActions: ActionCounts
    /// Newest completion first; undated done tasks last, newest created first.
    let doneActions: [DoneAction]

    /// The latest completed assessment's insights — title and domain only;
    /// title always nil when textsHidden.
    let latestInsights: [InsightSummary]
}

struct AssessmentPoint {
    let version: Int
    /// assessments.created_at — the assessment has no completion timestamp.
    let date: Date
    let total: Int
    let domainScores: [Domain: Int]
    let levels: [Domain: ScoreLevel]
}

struct ScoreDelta {
    let perDomain: [Domain: Int]
    let total: Int
}

struct AdjacentDelta {
    let fromVersion: Int
    let toVersion: Int
    let delta: ScoreDelta
}

struct ActionCounts {
    var open = 0
    var prio = 0
    var doing = 0
    var waiting = 0
    var done = 0
    /// done split by whether completed_at is set.
    var doneWithDate = 0
    var doneWithoutDate = 0
    /// Subset of doneWithDate whose date was set by hand (approximate).
    var doneWithManualDate = 0
}

struct DoneAction {
    /// The task's title, or an origin placeholder when textsHidden.
    let title: String
    let origin: ActionOrigin
    /// Raw actions.domain; may match no Domain.
    let domain: String
    let completedAt: Date?
    /// completedAt was set by hand afterwards — an approximation.
    let completedAtManual: Bool
    /// nil when completedAt is nil.
    let period: ReportPeriod?
}

/// Where a completion falls on the series' timeline (assessment dates).
/// fromVersion nil = before the first completed assessment; toVersion
/// nil = after the latest one.
struct ReportPeriod: Equatable {
    let fromVersion: Int?
    let toVersion: Int?
}

struct InsightSummary {
    let title: String?
    let domain: String?
}
