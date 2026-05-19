//
//  ResultView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import SwiftUI

struct ResultView: View {
    var assessment: Assessment
    var project: Project
    var domainScores: [DomainScore]
    var answerStore: AnswerStore
    var questionStore: QuestionStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 32) {
                    RadarChart(scores: domainScores)
                        .frame(height: 300)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                    domainList

                    VStack(spacing: 12) {
                        NavigationLink {
                            InsightsView(
                                assessment: assessment,
                                project: project,
                                domainScores: domainScores,
                                answerStore: answerStore,
                                questionStore: questionStore
                            )
                        } label: {
                            Text("Insikter")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)

                        NavigationLink {
                            PlanView(
                                assessment: assessment,
                                project: project,
                                domainScores: domainScores,
                                answerStore: answerStore,
                                questionStore: questionStore
                            )
                        } label: {
                            Text("30-60-90 Plan")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Resultat – Assessment \(assessment.version)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var domainList: some View {
        VStack(spacing: 12) {
            ForEach(domainScores, id: \.domain) { ds in
                HStack(spacing: 12) {
                    Text(ds.domain.rawValue)
                        .foregroundStyle(.white)
                        .font(.subheadline)
                    Spacer()
                    Text("\(ds.score)")
                        .foregroundStyle(Color.white.opacity(0.6))
                        .font(.subheadline.monospacedDigit())
                    levelPill(ds.level)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func levelPill(_ level: ScoreLevel) -> some View {
        Text(levelLabel(level))
            .font(.caption2.bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(levelColor(level))
            .clipShape(Capsule())
    }

    private func levelLabel(_ level: ScoreLevel) -> String {
        switch level {
        case .strong: return "Stark"
        case .note:   return "Notera"
        case .risk:   return "Risk"
        }
    }

    private func levelColor(_ level: ScoreLevel) -> Color {
        switch level {
        case .strong: return .green
        case .note:   return .yellow
        case .risk:   return .red
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
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                // Axis spokes from center to each vertex
                ForEach(0..<n, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: vertex(i: i, n: n, center: center, r: radius))
                    }
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                // Score polygon fill
                scorePath(center: center, radius: radius, n: n)
                    .fill(Color.cyan.opacity(0.22))

                // Score polygon stroke
                scorePath(center: center, radius: radius, n: n)
                    .stroke(Color.cyan, lineWidth: 2)

                // Score dots
                ForEach(0..<n, id: \.self) { i in
                    let r = radius * Double(scores[i].score) / 100.0
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 7, height: 7)
                        .position(vertex(i: i, n: n, center: center, r: r))
                }

                // Domain labels
                ForEach(0..<n, id: \.self) { i in
                    Text(scores[i].domain.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
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
        // Start at top (−90°), proceed clockwise
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

