//
//  OversiktView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-06-11.
//

import Foundation
import SwiftUI

struct OversiktView: View {
    var questionStore: QuestionStore

    @State private var store = HealthOverviewStore()
    @State private var tasksStore = OpenActionsStore()
    /// Shared cache: one projects+scores load feeds both lenses.
    @State private var scoresProvider = OversiktScoresProvider()
    /// Set only after a SUCCESSFUL load so the .task guard doesn't swallow
    /// a failed first attempt; the error-state retry bypasses it entirely.
    @State private var tasksLoaded = false
    @State private var selectedLens = 0
    // Driver den staggrade "tänds upp"-effekten när korten visas.
    @State private var rowsRevealed = false

    var body: some View {
        ZStack {
            APAmbientBackground()

            VStack(spacing: 0) {
                APSegmentedControl(selection: $selectedLens, options: ["Team", "Tasks"])
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if selectedLens == 0 {
                    teamLens
                } else {
                    tasksLens
                }
            }
        }
        .navigationTitle("Översikt")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // On the stable ZStack, same lesson as ProjectListView: the
        // destination must stay mounted across lens/loading states.
        .navigationDestination(for: TeamPlanRoute.self) { route in
            ProjectTabView(project: route.project, questionStore: questionStore, initialSection: 1)
        }
        .task { await store.load(questionStore: questionStore, provider: scoresProvider) }
    }

    // MARK: - Lenses

    @ViewBuilder
    private var teamLens: some View {
        if store.isLoading {
            ProgressView()
                .tint(.apOrange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.error != nil {
            APErrorState {
                store.error = nil
                Task { await store.load(questionStore: questionStore, provider: scoresProvider) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.rows.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            healthList
        }
    }

    /// The global Tasks lens. Routes need full Project values; the health
    /// store's rows (loaded at view mount) provide the lookup.
    private var tasksLens: some View {
        TasksLensView(
            store: tasksStore,
            questionStore: questionStore,
            provider: scoresProvider,
            projectsById: Dictionary(
                uniqueKeysWithValues: store.rows.map { ($0.project.id, $0.project) }
            )
        )
        .task {
            guard !tasksLoaded else { return }
            await tasksStore.load(questionStore: questionStore, provider: scoresProvider)
            // A cancelled load leaves error nil (aborts are swallowed) but
            // must not mark done — the guard would block the retry on the
            // next activation.
            if !Task.isCancelled && tasksStore.error == nil { tasksLoaded = true }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 52))
                .foregroundStyle(.apOrange)
            Text("Inga projekt ännu")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            Text("Skapa ett projekt och kör en assessment för att se översikten.")
                .font(.caption)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Health cards

    private var healthList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                    healthCard(row)
                        .opacity(rowsRevealed ? 1 : 0)
                        .offset(y: rowsRevealed ? 0 : 10)
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.8)
                                .delay(min(Double(index) * 0.06, 0.5)),
                            value: rowsRevealed
                        )
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .onAppear { rowsRevealed = true }
        .refreshable {
            scoresProvider.invalidate()
            await store.load(questionStore: questionStore, provider: scoresProvider, showSpinner: false)
        }
    }

    private func healthCard(_ row: TeamHealth) -> some View {
        NavigationLink(
            destination: ProjectTabView(
                project: row.project,
                questionStore: questionStore
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.project.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.apTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    trendChip(row)
                }

                if let scores = row.latestScores {
                    scoreStrip(scores)
                    attentionLine(row)
                } else {
                    // Zero completed assessments: name + open count only.
                    Text("Ingen assessment ännu")
                        .font(.caption)
                        .foregroundStyle(.apTextTertiary)
                    if row.openCount > 0 {
                        Text(openLabel(row.openCount))
                            .font(.caption)
                            .foregroundStyle(.apOrange)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.apSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.apHairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(APRowPressStyle())
        .haptic(.light)
    }

    // MARK: - Card pieces

    /// ↑+N / ↓−N / →0 on the total-score delta; "NY" with one completed
    /// assessment; nothing with zero.
    @ViewBuilder
    private func trendChip(_ row: TeamHealth) -> some View {
        if row.isNew {
            chip("NY", color: .apOrange)
        } else if let delta = row.delta {
            if delta > 0 {
                chip("↑ +\(delta)", color: .apStrong)
            } else if delta < 0 {
                chip("↓ \(delta)", color: .apRisk)
            } else {
                chip("→ 0", color: .apTextTertiary)
            }
        }
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    /// Six equal segments, one per domain, band-colored by score.
    private func scoreStrip(_ scores: [DomainScore]) -> some View {
        HStack(spacing: 3) {
            ForEach(scores, id: \.domain) { ds in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.apScore(ds.score))
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func attentionLine(_ row: TeamHealth) -> some View {
        HStack(spacing: 6) {
            if let weakest = row.weakest {
                Text("Svagast: \(weakest.domain.rawValue) · \(weakest.score)")
                    .foregroundStyle(Color.apScore(weakest.score))
            }
            if row.openCount > 0 {
                Text("— \(openLabel(row.openCount))")
                    .foregroundStyle(.apTextTertiary)
            }
        }
        .font(.caption)
    }

    private func openLabel(_ count: Int) -> String {
        count == 1 ? "1 öppen" : "\(count) öppna"
    }
}
