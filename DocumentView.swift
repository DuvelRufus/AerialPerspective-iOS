//
//  DocumentView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-27.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

// MARK: - Delete intent

private enum DeleteIntent {
    case action(ProjectAction)

    var title: String {
        switch self {
        case .action(let a): return "Radera \"\(a.title)\"?"
        }
    }
}

// MARK: - Add action target

private struct AddActionTarget: Identifiable {
    let domain: Domain
    let score: Int?
    var id: String { domain.rawValue }
}

// MARK: - DocumentView

struct DocumentView: View {
    var project: Project
    var questionStore: QuestionStore
    var actionStore: ActionStore

    // Assessment context
    @State private var latestAssessment: Assessment? = nil
    @State private var domainScores: [Domain: DomainScore] = [:]

    // Actions
    @State private var addActionTarget: AddActionTarget? = nil

    // View state
    @State private var isLoading = true

    // Search & delete
    @State private var searchText = ""
    @State private var pendingDelete: DeleteIntent? = nil
    /// The action row whose swipe actions are revealed, if any.
    @State private var openSwipeActionId: UUID? = nil

    // MARK: Filtered

    private func actionsFor(_ domain: Domain) -> [ProjectAction] {
        actionStore.actions.filter {
            $0.domain == domain.rawValue &&
            (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    // MARK: Domain ordering

    private var sortedDomains: [Domain] {
        Domain.allCases.sorted { sortKey($0) < sortKey($1) }
    }

    private func sortKey(_ domain: Domain) -> (Int, Int) {
        guard let ds = domainScores[domain] else { return (3, 0) }
        switch ds.level {
        case .risk:   return (0, ds.score)
        case .note:   return (1, ds.score)
        case .strong: return (2, ds.score)
        }
    }

    private func hasActions(_ domain: Domain) -> Bool {
        actionStore.actions.contains { $0.domain == domain.rawValue }
    }

    private func isCompact(_ domain: Domain) -> Bool {
        domainScores[domain]?.level == .strong && !hasActions(domain)
    }

    private var fullCardDomains: [Domain] {
        sortedDomains.filter { !isCompact($0) }
    }

    private var compactDomains: [Domain] {
        sortedDomains.filter { isCompact($0) }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            APAmbientBackground()
            if isLoading {
                ProgressView()
                    .tint(.apOrange)
            } else if actionStore.error != nil {
                APErrorState {
                    Task {
                        actionStore.error = nil
                        await actionStore.fetch(projectId: project.id)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    searchBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if latestAssessment == nil {
                                noAssessmentState
                            } else {
                                ForEach(fullCardDomains, id: \.self) { domain in
                                    domainCard(domain)
                                }
                                if !compactDomains.isEmpty {
                                    APSectionHeader(title: "STARKA DOMÄNER")
                                        .padding(.top, 12)
                                    ForEach(compactDomains, id: \.self) { domain in
                                        compactDomainRow(domain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        actionStore.error = nil
                        await actionStore.fetch(projectId: project.id)
                        await fetchAll()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await fetchAll() }
        .sheet(item: $addActionTarget) { target in
            AddActionSheet(domainName: target.domain.rawValue) { title in
                Task { await addAction(domain: target.domain, score: target.score, title: title) }
            }
        }
        .confirmationDialog(
            pendingDelete?.title ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                guard let intent = pendingDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDelete = nil
                Task { await performDelete(intent) }
            }
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Åtgärden kan inte ångras.")
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.apTextTertiary)
                .font(.subheadline)
            TextField("Sök...", text: $searchText)
                .foregroundStyle(.apTextPrimary)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.apSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - No assessment state

    private var noAssessmentState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(.apOrange)
            Text("Kör en assessment först")
                .font(.subheadline)
                .foregroundStyle(.apTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Domain cards

    private func domainCard(_ domain: Domain) -> some View {
        let ds = domainScores[domain]
        let domainActions = actionsFor(domain)
        let isWeak = ds.map { $0.level != .strong } ?? false

        return HStack(spacing: 0) {
            Rectangle()
                .fill(levelColor(ds?.level))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(domain.rawValue.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.apTextSecondary)
                    Spacer()
                    Text(ds.map { "\($0.score)" } ?? "–")
                        .font(.title2.bold())
                        .fontDesign(.rounded)
                        .foregroundStyle(.apTextPrimary)
                    if let ds {
                        levelPill(ds.level)
                    }
                }

                if isWeak || !domainActions.isEmpty {
                    if !domainActions.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(domainActions) { action in
                                actionRow(action)
                            }
                        }
                    }

                    if isWeak {
                        Button {
                            addActionTarget = AddActionTarget(domain: domain, score: ds?.score)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Lägg till åtgärd")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.apOrange)
                        }
                        .buttonStyle(.plain)
                        .haptic(.medium)
                        .minTapTarget()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func compactDomainRow(_ domain: Domain) -> some View {
        let ds = domainScores[domain]
        return HStack(spacing: 0) {
            Rectangle()
                .fill(levelColor(ds?.level))
                .frame(width: 4)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(domain.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apTextSecondary)
                Spacer()
                Text(ds.map { "\($0.score)" } ?? "–")
                    .font(.title2.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(.apTextPrimary)
                if let ds {
                    levelPill(ds.level)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func actionRow(_ action: ProjectAction) -> some View {
        HStack(spacing: 10) {
            Button {
                if action.isDone {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                Task { await actionStore.toggle(action) }
            } label: {
                Image(systemName: action.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(action.isDone ? Color.apStrong : Color.apTextTertiary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: action.isDone)
            }
            .buttonStyle(.plain)
            .minTapTarget()

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.subheadline)
                    .strikethrough(action.isDone)
                    .foregroundStyle(action.isDone ? Color.apTextTertiary : Color.apTextPrimary)
                if let score = action.createdFromScore {
                    Text("Skapad vid \(score) poäng")
                        .font(.caption)
                        .foregroundStyle(.apTextTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: action.isDone)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .action(action)
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
        // R4a: Vänta/Ta bort are visual stubs — real behavior lands in R4b.
        // Klar stays on the circle tap.
        .apSwipeActions(id: action.id, openId: $openSwipeActionId, actions: [
            APSwipeAction(title: "Vänta", systemImage: "clock", color: .apWaiting) {
                print("DocumentView: Vänta stub – \(action.id)")
            },
            APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                print("DocumentView: Ta bort stub – \(action.id)")
            }
        ])
    }

    private func levelColor(_ level: ScoreLevel?) -> Color {
        switch level {
        case .risk:   return .apRisk
        case .note:   return .apNote
        case .strong: return .apStrong
        case nil:     return .apTextTertiary
        }
    }

    private func levelPill(_ level: ScoreLevel) -> some View {
        Text(levelLabel(level))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(levelColor(level))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(levelColor(level).opacity(0.15))
            .clipShape(Capsule())
    }

    private func levelLabel(_ level: ScoreLevel) -> String {
        switch level {
        case .risk:   return "risk"
        case .note:   return "bevaka"
        case .strong: return "starkt"
        }
    }

    // MARK: - Fetch

    private func fetchAll() async {
        // Actions are fetched once at ProjectTabView and shared; this loads
        // only DocumentView's own per-view data.
        await loadAssessmentContext()
        isLoading = false
    }

    private func loadAssessmentContext() async {
        let assessmentStore = AssessmentStore()
        await assessmentStore.fetch(projectId: project.id)
        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }
        let questions = questionStore.questions
        let options = questionStore.options

        let byNewest = assessmentStore.assessments.sorted { $0.version > $1.version }
        for assessment in byNewest {
            let answerStore = AnswerStore()
            await answerStore.fetch(assessmentId: assessment.id)
            guard !answerStore.answers.isEmpty else { continue }
            let computed = ScoringService.compute(
                answers: answerStore.answers,
                questions: questions,
                options: options
            )
            var byDomain: [Domain: DomainScore] = [:]
            for ds in computed {
                let answeredInDomain = questions
                    .filter { $0.domain == ds.domain.rawValue }
                    .contains { answerStore.answers[$0.id] != nil }
                if answeredInDomain {
                    byDomain[ds.domain] = ds
                }
            }
            latestAssessment = assessment
            domainScores = byDomain
            return
        }
        latestAssessment = nil
        domainScores = [:]
    }

    // MARK: - Add

    private func addAction(domain: Domain, score: Int?, title: String) async {
        do {
            try await actionStore.add(
                projectId: project.id,
                domain: domain.rawValue,
                title: title,
                assessmentId: latestAssessment?.id,
                createdFromScore: score
            )
        } catch {
            print("DocumentView: addAction error: \(error)")
        }
    }

    // MARK: - Delete

    private func performDelete(_ intent: DeleteIntent) async {
        do {
            switch intent {
            case .action(let a):
                try await actionStore.delete(a)
            }
        } catch {
            print("DocumentView: delete error: \(error)")
        }
    }
}

// MARK: - Add Action Sheet

private struct AddActionSheet: View {
    let domainName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "ÅTGÄRD – \(domainName.uppercased())")
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
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
}

