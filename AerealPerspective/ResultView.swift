//
//  ResultView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

struct ResultView: View {
    var assessment: Assessment
    var project: Project
    var questionStore: QuestionStore
    var onDone: (() -> Void)?

    private let selfLoads: Bool

    @State private var domainScores: [DomainScore]
    @State private var answerStore: AnswerStore
    @State private var hasLoadedScores: Bool
    @State private var showInsights = false
    @State private var previousScores: [DomainScore]? = nil

    // Completion auto-generation: insights + plan are produced here, the
    // moment the result view appears with either missing.
    @State private var insightStore = InsightStore()
    @State private var planStore = PlanStore()
    @State private var isAutoGenerating = false
    @State private var generationError: String? = nil
    /// View-branch gate ONLY — never touches the generation guard. True
    /// from frame one on the question-flow path (a just-completed
    /// assessment can never have insights/plan, so generation is certain);
    /// false on the list path. Cleared once autoGenerateIfNeeded has
    /// decided, so the overlay can't stick if the decision defensively
    /// falls out to "not needed".
    @State private var awaitingGenerationDecision: Bool

    // Reveal animation: radar draws in, numbers count up, cells stagger in.
    @State private var revealProgress: Double = 0
    @State private var cellsRevealed = false
    @State private var revealComplete = false

    init(
        assessment: Assessment,
        project: Project,
        domainScores: [DomainScore],
        answerStore: AnswerStore,
        questionStore: QuestionStore,
        onDone: (() -> Void)? = nil
    ) {
        self.assessment = assessment
        self.project = project
        self.questionStore = questionStore
        self.onDone = onDone
        self.selfLoads = false
        _domainScores = State(initialValue: domainScores)
        _answerStore = State(initialValue: answerStore)
        _hasLoadedScores = State(initialValue: true)
        _awaitingGenerationDecision = State(initialValue: onDone != nil)
    }

    init(
        assessment: Assessment,
        project: Project,
        questionStore: QuestionStore
    ) {
        self.assessment = assessment
        self.project = project
        self.questionStore = questionStore
        self.onDone = nil
        self.selfLoads = true
        _domainScores = State(initialValue: [])
        _answerStore = State(initialValue: AnswerStore())
        _hasLoadedScores = State(initialValue: false)
        _awaitingGenerationDecision = State(initialValue: false)
    }

    private var deltas: [Domain: Int]? {
        guard let previousScores else { return nil }
        return ScoringService.delta(current: domainScores, previous: previousScores)
    }

    var body: some View {
        ZStack {
            APAmbientBackground()
            if !hasLoadedScores {
                ProgressView()
                    .tint(.apOrange)
            } else if isAutoGenerating || awaitingGenerationDecision || generationError != nil {
                // Full-screen while generating so the radar reveal fires
                // only once the results actually appear.
                APGenerationLoadingView(
                    phrases: Self.generationPhrases,
                    errorMessage: generationError,
                    onRetry: {
                        generationError = nil
                        Task { await autoGenerateIfNeeded() }
                    },
                    onSkip: {
                        // Just dismisses the overlay: whatever is still
                        // missing re-triggers on the next visit.
                        generationError = nil
                    }
                )
            } else {
                resultContent
            }
        }
        .task {
            if selfLoads && !hasLoadedScores {
                await loadCurrentScores()
            }
            await loadPreviousScores()
            await autoGenerateIfNeeded()
            // Decision made (generated, not needed, or errored — the error
            // branch holds the overlay via generationError, not this flag).
            awaitingGenerationDecision = false
        }
        .navigationTitle("Resultat – Assessment \(assessment.version)")
        .navigationBarTitleDisplayMode(.inline)
        // Question-flow path (onDone set): back would return to the already
        // answered questions — Klar is the only way out. List path keeps the
        // system back.
        .navigationBarBackButtonHidden(onDone != nil)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Klar exists only while resultContent shows — during the
            // generation/error overlay a tap would pop mid-generation and
            // read as "nothing happened"; the error overlay's own skip is
            // the way out there.
            if let onDone, !isAutoGenerating, !awaitingGenerationDecision, generationError == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    // Haptic in the action closure — a stacked .haptic
                    // gesture swallows toolbar-button taps (the 7edbd68
                    // family).
                    Button("Klar") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDone()
                    }
                    .foregroundStyle(.apOrange)
                }
            }
        }
        .navigationDestination(isPresented: $showInsights) {
            InsightsView(
                assessment: assessment,
                project: project,
                domainScores: domainScores,
                answerStore: answerStore,
                questionStore: questionStore
            )
        }
    }

    private var resultContent: some View {
        ScrollView {
                VStack(spacing: 32) {
                    RadarChart(scores: domainScores, progress: revealProgress)
                        .frame(height: 300)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)

                    bentoGrid

                    VStack(spacing: 12) {
                        APPillButton(title: "Insikter", action: {
                            showInsights = true
                        }, haptic: .light)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
        }
        .onAppear { reveal() }
        .sensoryFeedback(.success, trigger: revealComplete)
    }

    /// Runs once when the results appear: the radar polygon blooms out from
    /// the center while the bento cells stagger in and their numbers count up.
    private func reveal() {
        guard revealProgress == 0 else { return }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) {
            revealProgress = 1
        }
        cellsRevealed = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            revealComplete = true
        }
    }

    // MARK: - Bento grid

    private var bentoGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Array(domainScores.enumerated()), id: \.element.domain) { index, ds in
                domainCell(ds)
                    .opacity(cellsRevealed ? 1 : 0)
                    .offset(y: cellsRevealed ? 0 : 14)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.8)
                            .delay(0.15 + Double(index) * 0.06),
                        value: cellsRevealed
                    )
            }
        }
        .padding(.horizontal, 16)
    }

    private func domainCell(_ ds: DomainScore) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.apLevel(ds.level))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(ds.domain.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(cellsRevealed ? ds.score : 0)")
                        .font(.title.bold().monospacedDigit())
                        .fontDesign(.rounded)
                        .contentTransition(.numericText(value: Double(cellsRevealed ? ds.score : 0)))
                        .foregroundStyle(.apTextPrimary)
                    if let delta = deltas?[ds.domain] {
                        deltaIndicator(delta)
                            .transition(.scale.combined(with: .opacity))
                    } else if previousScores == nil {
                        deltaIndicator(0).hidden()
                    }
                }
                APScorePill(score: ds.score, level: ds.level, label: levelWord(ds.level))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func deltaIndicator(_ delta: Int) -> some View {
        Group {
            if delta > 0 {
                Text("▲ +\(delta)")
                    .foregroundStyle(Color.apStrong)
            } else if delta < 0 {
                Text("▼ \(delta)")
                    .foregroundStyle(Color.apRisk)
            } else {
                Text("– 0")
                    .foregroundStyle(Color.apTextTertiary)
            }
        }
        .font(.caption2.monospacedDigit())
    }

    // MARK: - Auto-generation (completion push-model)

    /// The rolling lines shown while Claude works, in random order.
    private static let generationPhrases: [String] = [
        "Anropar Claude, sonnet-4-6 vaknar…",
        "Läser av sex domäner, letar mönster…",
        "Den här appen byggdes på under en månad, mestadels efter att barnen somnat.",
        "Svåraste biten att bygga? Att låta dina avbockningar överleva när planen görs om.",
        "Rumi: 'Igår var jag smart, så jag ville ändra världen. Idag är jag vis, så jag ändrar mig själv.'",
        "Gåta: Ju mer du tar av mig, desto större blir jag. Vad är jag?",
        "Översätter din bedömning till konkreta åtgärder…",
        "En bra produktägare mäter inte hur mycket teamet levererar, utan om det rör sig åt rätt håll.",
        "Byggd i SwiftUI mot Supabase, med Claude som bollplank och kodare. En person, fyra roller.",
        "Let's practice patience, säger du till dig själv medan du väntar."
    ]

    /// Generates whatever this assessment is missing (insights and/or an
    /// active plan). Guarded per step, so a retry after a partial failure
    /// only re-runs the failed half. Never generates blind: a failed
    /// insights fetch is ambiguous (empty vs error) and would risk
    /// duplicate rows.
    private func autoGenerateIfNeeded() async {
        guard !isAutoGenerating else { return }
        await insightStore.fetch(assessmentId: assessment.id)
        guard insightStore.error == nil else { return }
        await planStore.loadNewestActivePlan(assessmentIdsNewestFirst: [assessment.id])
        let needsInsights = insightStore.insights.isEmpty
        let needsPlan = planStore.activePlan == nil && planStore.error == nil
        guard needsInsights || needsPlan else { return }

        generationError = nil
        isAutoGenerating = true
        defer { isAutoGenerating = false }
        do {
            if needsInsights {
                let generated = try await EdgeFunctionService.generateInsights(
                    scores: domainScores,
                    answers: answerStore.answers,
                    questions: questionStore.questions,
                    options: questionStore.options
                )
                try await insightStore.save(generated, for: assessment.id)
            }
            if needsPlan {
                let generated = try await EdgeFunctionService.generatePlan(
                    scores: domainScores,
                    answers: answerStore.answers,
                    questions: questionStore.questions,
                    options: questionStore.options,
                    durationValue: project.durationValue,
                    durationUnit: project.durationUnit?.rawValue
                )
                // First generation for this assessment: no anchors to carry.
                try await planStore.regenerate(
                    assessmentId: assessment.id,
                    plan: PlanStore.translate(generated, keyMap: [:])
                )
            }
        } catch {
            generationError = error.localizedDescription
            print("ResultView: auto-generation error: \(error)")
        }
    }

    // MARK: - Score loading

    private func loadCurrentScores() async {
        await answerStore.fetch(assessmentId: assessment.id)
        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }
        domainScores = ScoringService.compute(
            answers: answerStore.answers,
            questions: questionStore.questions,
            options: questionStore.options
        )
        hasLoadedScores = true
    }

    private func loadPreviousScores() async {
        guard assessment.version > 1 else { return }
        do {
            let previous: Assessment = try await supabase
                .from("assessments")
                .select()
                .eq("project_id", value: project.id)
                .eq("version", value: assessment.version - 1)
                .single()
                .execute()
                .value

            let previousAnswerStore = AnswerStore()
            await previousAnswerStore.fetch(assessmentId: previous.id)

            if questionStore.questions.isEmpty {
                await questionStore.fetch()
            }

            let computed = ScoringService.compute(
                answers: previousAnswerStore.answers,
                questions: questionStore.questions,
                options: questionStore.options
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                previousScores = computed
            }
        } catch {
            print("ResultView: loadPreviousScores error: \(error)")
        }
    }

    private func levelWord(_ level: ScoreLevel) -> String {
        switch level {
        case .risk:   return "Risk"
        case .note:   return "Bevaka"
        case .strong: return "Starkt"
        }
    }
}

// MARK: - Radar Chart

private struct RadarChart: View, @preconcurrency Animatable {
    let scores: [DomainScore]
    var progress: Double = 1

    // Lets SwiftUI interpolate `progress` frame by frame so the score
    // polygon blooms out from the center instead of snapping into place.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let gridLevels: [Double] = [0.33, 0.66, 1.0]

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = Double(min(geo.size.width, geo.size.height)) / 2 * 0.62
            let n = scores.count

            ZStack {
                // Background grid rings
                ForEach(Self.gridLevels.indices, id: \.self) { gi in
                    hexPath(center: center, radius: radius * Self.gridLevels[gi], n: n)
                        .stroke(Color.apTextTertiary.opacity(0.3), lineWidth: 1)
                }

                // Axis spokes from center to each vertex
                ForEach(0..<n, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: vertex(i: i, n: n, center: center, r: radius))
                    }
                    .stroke(Color.apTextTertiary.opacity(0.3), lineWidth: 1)
                }

                // Score polygon fill
                scorePath(center: center, radius: radius, n: n)
                    .fill(
                        LinearGradient(
                            colors: [Color.apOrange.opacity(0.38), Color.apOrange.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Score polygon stroke
                scorePath(center: center, radius: radius, n: n)
                    .stroke(Color.apOrange, lineWidth: 2)

                // Score dots
                ForEach(0..<n, id: \.self) { i in
                    let r = radius * Double(scores[i].score) / 100.0 * progress
                    Circle()
                        .fill(Color.apOrange)
                        .frame(width: 7, height: 7)
                        .position(vertex(i: i, n: n, center: center, r: r))
                        .opacity(progress)
                }

                // Domain labels
                ForEach(0..<n, id: \.self) { i in
                    Text(scores[i].domain.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.apTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 68)
                        .position(vertex(i: i, n: n, center: center, r: radius + 30))
                }
            }
        }
    }

    // MARK: Geometry helpers

    private func angle(i: Int, n: Int) -> Double {
        (Double(i) * 360.0 / Double(n) - 90.0) * .pi / 180.0
    }

    private func vertex(i: Int, n: Int, center: CGPoint, r: Double) -> CGPoint {
        let θ = angle(i: i, n: n)
        return CGPoint(x: center.x + r * cos(θ), y: center.y + r * sin(θ))
    }

    private func hexPath(center: CGPoint, radius: Double, n: Int) -> Path {
        Path { p in
            for i in 0..<n {
                let pt = vertex(i: i, n: n, center: center, r: radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func scorePath(center: CGPoint, radius: Double, n: Int) -> Path {
        Path { p in
            for i in 0..<n {
                let r = radius * Double(scores[i].score) / 100.0 * progress
                let pt = vertex(i: i, n: n, center: center, r: r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
}
