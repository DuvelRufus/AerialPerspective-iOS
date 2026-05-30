//
//  InsightsView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-19.
//

import Foundation
import UIKit
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
            Color.apBackground.ignoresSafeArea()
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
                    .tint(.apOrange)
                Text("Analyserar...")
                    .foregroundStyle(.apTextSecondary)
                    .font(.subheadline)
            }
        } else if insightStore.insights.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 48))
                    .foregroundStyle(.apOrange)
                Text("Inga insikter ännu")
                    .foregroundStyle(.apTextPrimary)
                    .font(.headline)
                generateButton("Generera insikter")
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.apRisk)
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
                    generateButton("Uppdatera", style: .secondary)
                        .padding(.top, 8)
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.apRisk)
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
                        .foregroundStyle(.apTextPrimary)
                }
                if let content = insight.content {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.apTextSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            Spacer(minLength: 0)
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func generateButton(_ label: String, style: APPillButtonStyle = .primary) -> some View {
        APPillButton(title: label, action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await generate() }
        }, style: style)
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
        case .strong: return .apStrong
        case .note:   return .apNote
        case .risk:   return .apRisk
        case nil:     return .apTextTertiary
        }
    }
}
