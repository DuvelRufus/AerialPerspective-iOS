
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
    @State private var actionStore = ActionStore()
    @State private var errorMessage: String? = nil
    @State private var insightForAction: Insight? = nil
    // Storen kan inte skilja "aldrig hämtat" från "hämtat, tomt" — båda är
    // isLoading == false, error == nil, insights == []. Tomma läget får
    // bara visas efter en genomförd hämtning.
    @State private var hasFetched = false
    // Driver för den staggrade intåget av insiktskorten.
    @State private var cardsRevealed = false

    var body: some View {
        ZStack {
            APAmbientBackground()
            content
        }
        .navigationTitle("Insikter")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            await insightStore.fetch(assessmentId: assessment.id)
            hasFetched = true
            await actionStore.fetch(projectId: project.id)
        }
        .sheet(item: $insightForAction) { insight in
            CreateActionSheet(insight: insight, domainScores: domainScores, insights: insightStore.insights) { title, domain in
                Task { await createAction(title: title, domain: domain, insightId: insight.id) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if insightStore.isLoading {
            loadingState
        } else if insightStore.error != nil {
            APErrorState {
                Task { await insightStore.fetch(assessmentId: assessment.id) }
            }
        } else if !hasFetched && insightStore.insights.isEmpty {
            loadingState
        } else if insightStore.insights.isEmpty {
            // Generering sker automatiskt när en assessment slutförs
            // (ResultView) — ingen manuell trigger här längre.
            VStack(spacing: 20) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 48))
                    .foregroundStyle(.apOrange)
                Text("Inga insikter ännu")
                    .foregroundStyle(.apTextPrimary)
                    .font(.headline)
                Text("Insikter skapas automatiskt när en assessment slutförs.")
                    .font(.subheadline)
                    .foregroundStyle(.apTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(insightStore.insights.enumerated()), id: \.element.id) { index, insight in
                        insightCard(insight)
                            .opacity(cardsRevealed ? 1 : 0)
                            .offset(y: cardsRevealed ? 0 : 16)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.8)
                                    .delay(min(Double(index) * 0.07, 0.6)),
                                value: cardsRevealed
                            )
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
                            }
                    }
                }
                .padding()
            }
            .onAppear { cardsRevealed = true }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.apOrange)
            Text("Analyserar...")
                .foregroundStyle(.apTextSecondary)
                .font(.subheadline)
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
            let isLinked = actionStore.actions.contains { $0.insightId == insight.id }
            Button {
                insightForAction = insight
            } label: {
                Image(systemName: isLinked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isLinked ? Color.apStrong : Color.apOrange)
            }
            .buttonStyle(.plain)
            .haptic(.medium)
            .minTapTarget()
            .padding(.trailing, 4)
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func createAction(title: String, domain: Domain, insightId: UUID?) async {
        do {
            try await actionStore.add(
                projectId: project.id,
                domain: domain.rawValue,
                title: title,
                assessmentId: assessment.id,
                insightId: insightId,
                createdFromScore: domainScores.first { $0.domain == domain }?.score
            )
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
            print("InsightsView: createAction error: \(error)")
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

// MARK: - Create Action Sheet

private struct CreateActionSheet: View {
    let insight: Insight
    let domainScores: [DomainScore]
    let insights: [Insight]
    let onSave: (String, Domain) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var domain: Domain
    @State private var selectedSuggestionId: UUID?

    init(
        insight: Insight,
        domainScores: [DomainScore],
        insights: [Insight],
        onSave: @escaping (String, Domain) -> Void
    ) {
        self.insight = insight
        self.domainScores = domainScores
        self.insights = insights
        self.onSave = onSave
        _title = State(initialValue: insight.suggestedAction ?? insight.title ?? "")
        _domain = State(initialValue: insight.domain.flatMap(Domain.init(rawValue:))
            ?? domainScores.min(by: { $0.score < $1.score })?.domain ?? .team)
        _selectedSuggestionId = State(initialValue: insight.suggestedAction != nil ? insight.id : nil)
    }

    private var suggestions: [Insight] {
        insights.filter { $0.domain == domain.rawValue && $0.suggestedAction != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "ÅTGÄRD")
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            APSectionHeader(title: "FÖRSLAG FRÅN INSIKTER")
                            ForEach(suggestions) { suggestion in
                                suggestionRow(suggestion)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "DOMÄN")
                        Picker("Domän", selection: $domain) {
                            ForEach(Domain.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.apOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.apSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, domain)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Ny åtgärd")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }

    private func suggestionRow(_ suggestion: Insight) -> some View {
        let isSelected = selectedSuggestionId == suggestion.id
        return Button {
            title = suggestion.suggestedAction ?? ""
            selectedSuggestionId = suggestion.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.apOrange)
                Text(suggestion.suggestedAction ?? "")
                    .font(.caption)
                    .foregroundStyle(.apTextPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.apSurfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.apOrange : Color.apHairline,
                                  lineWidth: isSelected ? 1 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .haptic(.light)
    }
}
