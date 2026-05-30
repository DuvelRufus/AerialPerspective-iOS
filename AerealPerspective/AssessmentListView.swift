//
//  AssessmentListView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import SwiftUI

struct AssessmentListView: View {
    var project: Project
    var questionStore: QuestionStore

    @State private var assessmentStore = AssessmentStore()
    @State private var isCreating = false

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            if assessmentStore.isLoading {
                ProgressView()
                    .tint(.apOrange)
            } else if assessmentStore.assessments.isEmpty {
                emptyState
            } else {
                assessmentList
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await assessmentStore.fetch(projectId: project.id) }
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
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    private var assessmentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(assessmentStore.assessments) { assessment in
                    NavigationLink {
                        AssessmentView(
                            assessment: assessment,
                            project: project,
                            questionStore: questionStore
                        )
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
                                }
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(Color.apOrange)
                                        .frame(width: 36, height: 36)
                                    Text("\(assessment.version)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                }

                APPillButton(title: "Ny assessment", style: .secondary) {
                    Task { await createNext() }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
        defer { isCreating = false }
        try? await assessmentStore.createOrFetchLatest(projectId: project.id)
    }

    private func createNext() async {
        isCreating = true
        defer { isCreating = false }
        try? await assessmentStore.createNext(projectId: project.id)
    }
}
