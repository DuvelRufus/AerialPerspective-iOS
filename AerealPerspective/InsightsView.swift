//
//  InsightsView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-19.
//

import Foundation
import SwiftUI

struct InsightsView: View {
    var assessment: Assessment
    var project: Project
    var domainScores: [DomainScore]
    var answerStore: AnswerStore
    var questionStore: QuestionStore

    @State private var insightStore = InsightStore()
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .navigationTitle("Insikter")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await insightStore.fetch(assessmentId: assessment.id) }
    }

    @ViewBuilder
    private var content: some View {
        if insightStore.isLoading || isGenerating {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.cyan)
                Text("Analyserar...")
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.subheadline)
            }
        } else if insightStore.insights.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)
                Text("Inga insikter ännu")
                    .foregroundStyle(.white)
                    .font(.headline)
                generateButton("Generera insikter")
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(insightStore.insights) { insight in
                        insightCard(insight)
                    }
                    generateButton("Uppdatera")
                        .padding(.top, 8)
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
    }

    private func insightCard(_ insight: Insight) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(riskColor(insight.riskLevel))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                if let title = insight.title {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                if let content = insight.content {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func generateButton(_ label: String) -> some View {
        Button(label) {
            Task { await generate() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.cyan)
    }

    private func generate() async {
        print("InsightsView: generate() start – assessment \(assessment.id)")
        errorMessage = nil
        isGenerating = true
        defer {
            isGenerating = false
            print("InsightsView: generate() end")
        }
        do {
            let generated = try await EdgeFunctionService.generateInsights(
                scores: domainScores,
                answers: answerStore.answers,
                questions: questionStore.questions,
                options: questionStore.options
            )
            print("InsightsView: received \(generated.count) insights")
            try await insightStore.save(generated, for: assessment.id)
        } catch {
            errorMessage = error.localizedDescription
            print("InsightsView: generate error: \(error)")
        }
    }

    private func riskColor(_ level: RiskLevel?) -> Color {
        switch level {
        case .strong: return .green
        case .note:   return .yellow
        case .risk:   return .red
        case nil:     return .gray
        }
    }
}
