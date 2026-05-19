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
            Color.black.ignoresSafeArea()

            if assessmentStore.isLoading {
                ProgressView().tint(.cyan)
            } else if assessmentStore.assessments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundStyle(.cyan)
                    Text("Inga assessments ännu")
                        .foregroundStyle(.white)
                    Button("Starta assessment 1") {
                        Task { await createFirst() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                }
            } else {
                List {
                    ForEach(assessmentStore.assessments) { assessment in
                        NavigationLink {
                            AssessmentView(
                                assessment: assessment,
                                project: project,
                                questionStore: questionStore
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Assessment \(assessment.version)")
                                        .foregroundStyle(.white)
                                        .font(.headline)
                                    Text(assessment.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }

                    Button {
                        Task { await createNext() }
                    } label: {
                        Label("Ny assessment", systemImage: "plus")
                            .foregroundStyle(.cyan)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .task { await assessmentStore.fetch(projectId: project.id) }
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
