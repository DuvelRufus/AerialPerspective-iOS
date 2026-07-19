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

            if selectedLens == 0 {
                teamLens
            } else {
                tasksLens
            }
        }
        // Pinned above BOTH lenses: a safe-area inset sits outside the
        // scroll geometry AND outside the system's large-title tracking, so
        // pull/scroll can neither drag nor clip title or segment — only the
        // list moves, and the refresh spinner lands below the block. Own
        // title Text (system large-title metrics) since the nav bar is
        // hidden on this root.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Översikt")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.apTextPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                APSegmentedControl(selection: $selectedLens, options: ["Team", "Tasks"])
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The plate must reach the physical top now that the nav bar is
            // gone — content stays inside the safe area (title never under
            // the clock), only the background extends past it.
            .background(Color.apBackground.ignoresSafeArea(edges: .top))
        }
        // Tab root, never pushed — no back button exists; hiding the bar is
        // per-view, so pushed ProjectTabView gets its own bar back.
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
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
        Group {
            if let scores = row.latestScores {
                // Scored teams land on Plan (the task surface) via the
                // value route — a deliberate change from the old
                // Assessments landing.
                NavigationLink(value: TeamPlanRoute(project: row.project)) {
                    ringCardContent(row, scores: scores)
                }
            } else {
                // Zero completed: keep the Assessments landing so the
                // first-assessment flow stays one tap away.
                NavigationLink(
                    destination: ProjectTabView(project: row.project, questionStore: questionStore)
                ) {
                    placeholderCardContent(row)
                }
            }
        }
        .buttonStyle(APRowPressStyle())
        .haptic(.light)
    }

    private func ringCardContent(_ row: TeamHealth, scores: [DomainScore]) -> some View {
        // Full-width row: ring | flexible text column | trend chip at the
        // card's trailing edge.
        APCard(padding: 14) {
            HStack(spacing: 12) {
                scoreRing(ScoringService.total(scores))

                VStack(alignment: .leading, spacing: 6) {
                    Text(row.project.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.apTextPrimary)
                        .lineLimit(1)
                    if let weakest = row.weakest {
                        (Text("Svagast ")
                            .foregroundStyle(Color.apTextSecondary)
                        + Text("\(weakest.domain.rawValue) \(weakest.score)")
                            .foregroundStyle(Color.apScore(weakest.score)))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trendChip(row)
            }
        }
    }

    /// Zero completed assessments: empty gray track ring (no number), name
    /// and the placeholder caption — no chip, exactly as before.
    private func placeholderCardContent(_ row: TeamHealth) -> some View {
        APCard(padding: 14) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(Color.apHairline, lineWidth: 5)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text(row.project.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.apTextPrimary)
                        .lineLimit(1)
                    Text("Ingen assessment ännu")
                        .font(.caption2)
                        .foregroundStyle(.apTextTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Total-score ring: gray track, trim colored by the shared 66/34
    /// bands, number centered — the same color logic the old strip used.
    private func scoreRing(_ total: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.apHairline, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(total) / 100)
                .stroke(Color.apScore(total), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(total)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.apTextPrimary)
        }
        .frame(width: 48, height: 48)
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

}
