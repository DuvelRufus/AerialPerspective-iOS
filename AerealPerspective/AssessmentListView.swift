//
//  AssessmentListView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import SwiftUI
import Supabase

/// A completed assessment's total and its deltas; both deltas are nil on
/// the first completed assessment.
private struct ScoreSummary {
    let total: Int
    let fromStart: Int?
    let sincePrevious: Int?
}

struct AssessmentListView: View {
    var project: Project
    var questionStore: QuestionStore

    @State private var assessmentStore = AssessmentStore()
    @State private var isCreating = false
    @State private var createError: String? = nil
    /// assessmentId → [questionId: answerOptionId], answered rows only.
    /// Drives both completion (its count) and the score summaries.
    @State private var answersByAssessment: [UUID: [UUID: UUID]] = [:]
    /// Completed assessments only, computed once per fetch — not per card.
    @State private var scoreSummaries: [UUID: ScoreSummary] = [:]
    /// Assessments that have at least one insights row — distinguishes
    /// "not generated" from "all handled" in the Insikter chip.
    @State private var insightAssessmentIds: Set<UUID> = []
    /// assessmentId → insights without a matching action (variant C:
    /// the orange "N att hantera" state).
    @State private var unhandledInsightCounts: [UUID: Int] = [:]
    /// Assessments with an active plans row — drives the "Plan" chip.
    @State private var planAssessmentIds: Set<UUID> = []
    /// List-owned push for the INCOMPLETE path: zeroing this removes
    /// AssessmentView AND anything above it (ResultView) in ONE stack
    /// mutation — no same-turn double-pop race. The system back-swipe
    /// writes nil back through the two-way item binding.
    @State private var activeAssessment: Assessment? = nil

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            if assessmentStore.isLoading {
                ProgressView()
                    .tint(.apOrange)
            } else if assessmentStore.error != nil {
                APErrorState {
                    assessmentStore.error = nil
                    Task {
                        await assessmentStore.fetch(projectId: project.id)
                        await fetchAnswers()
                        await fetchInsightStatus()
                        await fetchPlanIds()
                    }
                }
            } else if assessmentStore.assessments.isEmpty {
                emptyState
            } else {
                assessmentList
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // On the stable ZStack (the ProjectListView lesson): the destination
        // must stay mounted across loading/error/empty states.
        .navigationDestination(item: $activeAssessment) { assessment in
            AssessmentView(
                assessment: assessment,
                project: project,
                questionStore: questionStore,
                onFinished: { activeAssessment = nil }
            )
        }
        .task {
            await assessmentStore.fetch(projectId: project.id)
            await fetchAnswers()
            await fetchInsightStatus()
            await fetchPlanIds()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.apOrange)
            Text("Inga assessments ännu")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            Text(recommendedLabel)
                .font(.subheadline)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
            APPillButton(title: "Starta assessment 1") {
                Task { await createFirst() }
            }
            .disabled(isCreating)
            .opacity(isCreating ? 0.5 : 1)
            .overlay {
                if isCreating {
                    ProgressView().tint(.apOrange)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            if let createError {
                Text(createError)
                    .font(.caption)
                    .foregroundStyle(.apRisk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
    }

    private var assessmentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(assessmentStore.assessments) { assessment in
                    assessmentRow(assessment)
                }

                APPillButton(title: "Ny assessment", action: {
                    Task { await createNext() }
                }, style: .secondary)
                .disabled(isCreating)
                .opacity(isCreating ? 0.5 : 1)
                .overlay {
                    if isCreating {
                        ProgressView().tint(.apOrange)
                    }
                }
                .padding(.top, 8)

                if let createError {
                    Text(createError)
                        .font(.caption)
                        .foregroundStyle(.apRisk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await assessmentStore.fetch(projectId: project.id)
            await fetchAnswers()
            await fetchInsightStatus()
            await fetchPlanIds()
        }
    }

    @ViewBuilder
    private func assessmentRow(_ assessment: Assessment) -> some View {
        let completed = isComplete(assessment)
        if completed {
            // List path: straight to results, unchanged.
            NavigationLink {
                ResultView(
                    assessment: assessment,
                    project: project,
                    questionStore: questionStore
                )
            } label: {
                rowLabel(assessment, completed: true)
            }
            .buttonStyle(APRowPressStyle())
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })
        } else {
            // Incomplete path: list-owned push (mechanism d) — the button
            // sets the binding; haptic in the closure, no stacked gesture.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                activeAssessment = assessment
            } label: {
                rowLabel(assessment, completed: false)
            }
            .buttonStyle(APRowPressStyle())
        }
    }

    private func rowLabel(_ assessment: Assessment, completed: Bool) -> some View {
        APCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assessment \(assessment.version)")
                        .font(.title3.bold())
                        .foregroundStyle(.apTextPrimary)
                    Text(dateLine(assessment, completed: completed))
                        .font(.caption)
                        .foregroundStyle(.apTextSecondary)
                        .lineLimit(1)
                    if completed {
                        if let summary = scoreSummaries[assessment.id], summary.fromStart == nil {
                            Text("Start")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.apTextTertiary)
                                .lineLimit(1)
                        }
                        // Chips only once completed — before that neither
                        // insights nor plan can be generated, and the
                        // progress line below carries the row's state.
                        chipRows(for: assessment)
                            .padding(.top, 2)
                    } else {
                        Text("\(answeredCount(assessment))/\(completionTarget(assessment))")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    /// "<datum> · Totalt <N>" on completed rows with a summary; the date
    /// alone otherwise (incomplete rows, or questions unresolved).
    private func dateLine(_ assessment: Assessment, completed: Bool) -> String {
        let date = assessment.createdAt.formatted(date: .abbreviated, time: .omitted)
        guard completed, let summary = scoreSummaries[assessment.id] else { return date }
        return "\(date) · Totalt \(summary.total)"
    }

    /// The unchanged status chips, plus the two delta chips when this isn't
    /// the first completed assessment. One row if everything fits, else the
    /// delta chips drop to their own row below (and stack if even that
    /// row is too wide) — chips never wrap.
    @ViewBuilder
    private func chipRows(for assessment: Assessment) -> some View {
        let statusChips = HStack(spacing: 6) {
            insightChip(for: assessment)
            generationChip("Plan", generated: planAssessmentIds.contains(assessment.id))
        }
        if let summary = scoreSummaries[assessment.id],
           let fromStart = summary.fromStart,
           let sincePrevious = summary.sincePrevious {
            let fromStartChip = APTrendChip(delta: fromStart, suffix: "från start")
            let sincePreviousChip = APTrendChip(delta: sincePrevious, suffix: "sedan förra")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    statusChips
                    fromStartChip
                    sincePreviousChip
                }
                VStack(alignment: .leading, spacing: 6) {
                    statusChips
                    HStack(spacing: 6) {
                        fromStartChip
                        sincePreviousChip
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    statusChips
                    fromStartChip
                    sincePreviousChip
                }
            }
        } else {
            statusChips
        }
    }

    /// Three-state Insikter chip: unhandled count (orange) → all handled
    /// (green check, the plain generationChip) → not generated (dim outline).
    @ViewBuilder
    private func insightChip(for assessment: Assessment) -> some View {
        let hasInsights = insightAssessmentIds.contains(assessment.id)
        let unhandled = unhandledInsightCounts[assessment.id] ?? 0
        if hasInsights && unhandled > 0 {
            Text("\(unhandled) att hantera")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.apOrange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.apOrange.opacity(0.15)))
                .overlay(
                    Capsule().strokeBorder(Color.apOrange.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            generationChip("Insikter", generated: hasInsights)
        }
    }

    /// Generated → green check-chip; not yet → dim outline, deliberately
    /// neutral ("not yet", not a warning).
    private func generationChip(_ label: String, generated: Bool) -> some View {
        HStack(spacing: 4) {
            if generated {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(generated ? Color.apStrong : Color.apTextTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(generated ? Color.apStrong.opacity(0.15) : Color.clear))
        .overlay(
            Capsule().strokeBorder(
                generated ? Color.apStrong.opacity(0.4) : Color.apHairline,
                lineWidth: 0.5
            )
        )
    }

    private func isComplete(_ assessment: Assessment) -> Bool {
        let total = completionTarget(assessment)
        return total > 0 && answeredCount(assessment) >= total
    }

    private func answeredCount(_ assessment: Assessment) -> Int {
        answersByAssessment[assessment.id]?.count ?? 0
    }

    /// The count frozen on the assessment, or the project template's
    /// question count on rows predating question_count.
    private func completionTarget(_ assessment: Assessment) -> Int {
        assessment.questionCount ?? questionStore.questions(for: project).count
    }

    /// All answers for the list's assessments, paginated past PostgREST's
    /// silent 1000-row cap (the AssessmentScoresLoader pattern), grouped
    /// per assessment in the same pass; then the score summaries.
    private func fetchAnswers() async {
        let ids = assessmentStore.assessments.map { $0.id.uuidString }
        guard !ids.isEmpty else { return }
        do {
            var grouped: [UUID: [UUID: UUID]] = [:]
            // Ordered so page windows stay disjoint; a short page ends it.
            let pageSize = 1000
            var offset = 0
            while true {
                let page: [Answer] = try await supabase
                    .from("answers")
                    .select()
                    .in("assessment_id", values: ids)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                for row in page {
                    guard let optionId = row.answerOptionId else { continue }
                    grouped[row.assessmentId, default: [:]][row.questionId] = optionId
                }
                if page.count < pageSize { break }
                offset += pageSize
            }
            answersByAssessment = grouped
            computeScoreSummaries()
        } catch {
            print("AssessmentListView: fetchAnswers error: \(error)")
        }
    }

    /// Total per completed assessment plus its delta against the first
    /// (lowest-version) completed one and the nearest lower completed one —
    /// incomplete assessments are skipped, never compared against. Same
    /// inputs as ResultView.recomputeCurrentScores. Empty while the
    /// project's questions are unresolved, so no all-zero totals show.
    private func computeScoreSummaries() {
        let questions = questionStore.questions(for: project)
        guard !questions.isEmpty else {
            scoreSummaries = [:]
            return
        }
        let completed = assessmentStore.assessments
            .filter(isComplete)
            .sorted { $0.version < $1.version }
        var summaries: [UUID: ScoreSummary] = [:]
        var startTotal: Int? = nil
        var previousTotal: Int? = nil
        for assessment in completed {
            let total = ScoringService.total(ScoringService.compute(
                answers: answersByAssessment[assessment.id] ?? [:],
                questions: questions,
                options: questionStore.options
            ))
            summaries[assessment.id] = ScoreSummary(
                total: total,
                fromStart: startTotal.map { total - $0 },
                sincePrevious: previousTotal.map { total - $0 }
            )
            if startTotal == nil { startTotal = total }
            previousTotal = total
        }
        scoreSummaries = summaries
    }

    /// One batched existence query for the whole list (no N+1): which
    /// assessments have an active plans row.
    private func fetchPlanIds() async {
        let ids = assessmentStore.assessments.map { $0.id.uuidString }
        guard !ids.isEmpty else { return }
        struct PlanRef: Decodable {
            let assessmentId: UUID
            enum CodingKeys: String, CodingKey {
                case assessmentId = "assessment_id"
            }
        }
        do {
            let rows: [PlanRef] = try await supabase
                .from("plans")
                .select("assessment_id")
                .eq("is_active", value: true)
                .in("assessment_id", values: ids)
                .execute()
                .value
            planAssessmentIds = Set(rows.map(\.assessmentId))
        } catch {
            print("AssessmentListView: fetchPlanIds error: \(error)")
        }
    }

    /// One batched existence query for the whole list (no N+1): which
    /// assessments have at least one insights row.
    private func fetchInsightStatus() async {
        let ids = assessmentStore.assessments.map { $0.id.uuidString }
        guard !ids.isEmpty else { return }
        struct InsightRef: Decodable {
            let id: UUID
            let assessmentId: UUID
            enum CodingKeys: String, CodingKey {
                case id
                case assessmentId = "assessment_id"
            }
        }
        struct LinkedActionRef: Decodable {
            // Optional as a belt: the count survives even if the not-null
            // filter's server behavior ever differs.
            let insightId: UUID?
            enum CodingKeys: String, CodingKey {
                case insightId = "insight_id"
            }
        }
        do {
            let insights: [InsightRef] = try await supabase
                .from("insights")
                .select("id, assessment_id")
                .in("assessment_id", values: ids)
                .execute()
                .value
            let linked: [LinkedActionRef] = try await supabase
                .from("actions")
                .select("insight_id")
                .eq("project_id", value: project.id)
                .not("insight_id", operator: .is, value: "null")
                .execute()
                .value
            let linkedIds = Set(linked.compactMap(\.insightId))

            insightAssessmentIds = Set(insights.map(\.assessmentId))
            var counts: [UUID: Int] = [:]
            for insight in insights where !linkedIds.contains(insight.id) {
                counts[insight.assessmentId, default: 0] += 1
            }
            unhandledInsightCounts = counts
        } catch {
            print("AssessmentListView: fetchInsightStatus error: \(error)")
        }
    }

    private var recommendedLabel: String {
        guard let unit = project.durationUnit else {
            return "Rekommenderat: 2 assessments"
        }
        switch unit {
        case .weeks:
            let isLong = (project.durationValue ?? 0) >= 5
            return isLong ? "Rekommenderat: 3 assessments" : "Rekommenderat: 2 assessments"
        case .months, .years:
            return "Rekommenderat: 3 assessments"
        }
    }

    /// Refetches if unresolved; false (with createError set) when the
    /// project's template has no questions — no assessment row is created.
    private func questionsAvailable() async -> Bool {
        if questionStore.questions.isEmpty || !questionStore.templatesLoaded {
            await questionStore.fetch()
        }
        guard !questionStore.questions(for: project).isEmpty else {
            createError = "Frågorna kunde inte laddas. Kontrollera din anslutning och försök igen."
            return false
        }
        return true
    }

    private func createFirst() async {
        isCreating = true
        createError = nil
        defer { isCreating = false }
        guard await questionsAvailable() else { return }
        do {
            _ = try await assessmentStore.createOrFetchLatest(projectId: project.id)
        } catch {
            createError = error.localizedDescription
            print("AssessmentListView: createFirst error: \(error)")
        }
    }

    private func createNext() async {
        isCreating = true
        createError = nil
        defer { isCreating = false }
        guard await questionsAvailable() else { return }
        do {
            _ = try await assessmentStore.createNext(projectId: project.id)
        } catch {
            createError = error.localizedDescription
            print("AssessmentListView: createNext error: \(error)")
        }
    }
}
