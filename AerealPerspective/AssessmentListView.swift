//
//  AssessmentListView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import SwiftUI
import Supabase

struct AssessmentListView: View {
    var project: Project
    var questionStore: QuestionStore

    @State private var assessmentStore = AssessmentStore()
    @State private var isCreating = false
    @State private var createError: String? = nil
    @State private var answeredCounts: [UUID: Int] = [:]
    /// Assessments that have at least one insights row — drives the
    /// "Insikter" chip. Plan presence needs no extra state: it rides along
    /// on assessments.plan, already loaded with the list.
    @State private var insightAssessmentIds: Set<UUID> = []

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
                        await fetchAnsweredCounts()
                        await fetchInsightIds()
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
        .task {
            await assessmentStore.fetch(projectId: project.id)
            await fetchAnsweredCounts()
            await fetchInsightIds()
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
            await fetchAnsweredCounts()
            await fetchInsightIds()
        }
    }

    @ViewBuilder
    private func assessmentRow(_ assessment: Assessment) -> some View {
        let completed = isComplete(assessment)
        NavigationLink {
            if completed {
                ResultView(
                    assessment: assessment,
                    project: project,
                    questionStore: questionStore
                )
            } else {
                AssessmentView(
                    assessment: assessment,
                    project: project,
                    questionStore: questionStore
                )
            }
        } label: {
            APCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assessment \(assessment.version)")
                            .font(.title3.bold())
                            .foregroundStyle(.apTextPrimary)
                        Text(assessment.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.apTextSecondary)
                        if completed {
                            // Chips only once completed — before that neither
                            // insights nor plan can be generated, and the
                            // progress line below carries the row's state.
                            HStack(spacing: 6) {
                                generationChip("Insikter", generated: insightAssessmentIds.contains(assessment.id))
                                generationChip("Plan", generated: assessment.plan != nil)
                            }
                            .padding(.top, 2)
                        } else {
                            Text("\(answeredCounts[assessment.id] ?? 0)/\(questionStore.questions.count)")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(APRowPressStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
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
        let total = questionStore.questions.count
        return total > 0 && (answeredCounts[assessment.id] ?? 0) >= total
    }

    private func fetchAnsweredCounts() async {
        let ids = assessmentStore.assessments.map { $0.id.uuidString }
        guard !ids.isEmpty else { return }
        do {
            let rows: [Answer] = try await supabase
                .from("answers")
                .select()
                .in("assessment_id", values: ids)
                .execute()
                .value
            var counts: [UUID: Int] = [:]
            for row in rows where row.answerOptionId != nil {
                counts[row.assessmentId, default: 0] += 1
            }
            answeredCounts = counts
        } catch {
            print("AssessmentListView: fetchAnsweredCounts error: \(error)")
        }
    }

    /// One batched existence query for the whole list (no N+1): which
    /// assessments have at least one insights row.
    private func fetchInsightIds() async {
        let ids = assessmentStore.assessments.map { $0.id.uuidString }
        guard !ids.isEmpty else { return }
        struct InsightRef: Decodable {
            let assessmentId: UUID
            enum CodingKeys: String, CodingKey {
                case assessmentId = "assessment_id"
            }
        }
        do {
            let rows: [InsightRef] = try await supabase
                .from("insights")
                .select("assessment_id")
                .in("assessment_id", values: ids)
                .execute()
                .value
            insightAssessmentIds = Set(rows.map(\.assessmentId))
        } catch {
            print("AssessmentListView: fetchInsightIds error: \(error)")
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

    private func createFirst() async {
        isCreating = true
        createError = nil
        defer { isCreating = false }
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
        do {
            _ = try await assessmentStore.createNext(projectId: project.id)
        } catch {
            createError = error.localizedDescription
            print("AssessmentListView: createNext error: \(error)")
        }
    }
}
