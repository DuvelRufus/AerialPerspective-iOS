//
//  ResultView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
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
    }

    private var deltas: [Domain: Int]? {
        guard let previousScores else { return nil }
        return ScoringService.delta(current: domainScores, previous: previousScores)
    }

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            if !hasLoadedScores {
                ProgressView()
                    .tint(.apOrange)
            } else {
                resultContent
            }
        }
        .task {
            if selfLoads && !hasLoadedScores {
                await loadCurrentScores()
            }
            await loadPreviousScores()
        }
        .navigationTitle("Resultat – Assessment \(assessment.version)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Klar") { onDone() }
                        .foregroundStyle(.apOrange)
                        .haptic(.light)
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
                    RadarChart(scores: domainScores)
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
    }

    // MARK: - Bento grid

    private var bentoGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(domainScores, id: \.domain) { ds in
                domainCell(ds)
            }
        }
        .padding(.horizontal, 16)
    }

    private func domainCell(_ ds: DomainScore) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor(for: ds.level))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(ds.domain.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(ds.score)")
                        .font(.title.bold())
                        .foregroundStyle(.apTextPrimary)
                    if let delta = deltas?[ds.domain] {
                        deltaIndicator(delta)
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

            previousScores = ScoringService.compute(
                answers: previousAnswerStore.answers,
                questions: questionStore.questions,
                options: questionStore.options
            )
        } catch {
            print("ResultView: loadPreviousScores error: \(error)")
        }
    }

    private func accentColor(for level: ScoreLevel) -> Color {
        switch level {
        case .risk:   return Color.apRisk
        case .note:   return Color.apNote
        case .strong: return Color.apStrong
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

private struct RadarChart: View {
    let scores: [DomainScore]

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
                    .fill(Color.apOrange.opacity(0.25))

                // Score polygon stroke
                scorePath(center: center, radius: radius, n: n)
                    .stroke(Color.apOrange, lineWidth: 2)

                // Score dots
                ForEach(0..<n, id: \.self) { i in
                    let r = radius * Double(scores[i].score) / 100.0
                    Circle()
                        .fill(Color.apOrange)
                        .frame(width: 7, height: 7)
                        .position(vertex(i: i, n: n, center: center, r: r))
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
                let r = radius * Double(scores[i].score) / 100.0
                let pt = vertex(i: i, n: n, center: center, r: r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
}
