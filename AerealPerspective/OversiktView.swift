//
//  OversiktView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-06-11.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

struct OversiktView: View {
    var questionStore: QuestionStore

    @State private var rows: [OverviewRow] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private static let nameColumnWidth: CGFloat = 92
    private static let cellSpacing: CGFloat = 5

    private static let domainAbbreviations: [Domain: String] = [
        .team: "TEAM",
        .process: "PROC",
        .product: "PROD",
        .tech: "TECH",
        .stakeholders: "STAKE",
        .culture: "CULT"
    ]

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(.apOrange)
            } else if loadFailed {
                APErrorState {
                    loadFailed = false
                    Task { await loadOverview() }
                }
            } else if rows.allSatisfy({ $0.scores == nil }) {
                emptyState
            } else {
                heatmap
            }
        }
        .navigationTitle("Översikt")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadOverview() }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 52))
                .foregroundStyle(.apOrange)
            Text("Inga assessments ännu")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            Text("Kör en assessment i ett projekt för att se översikten.")
                .font(.caption)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var heatmap: some View {
        ScrollView {
            VStack(spacing: 8) {
                headerRow
                ForEach(rows) { row in
                    rowView(row)
                }
                legend
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Heatmap

    private var headerRow: some View {
        HStack(spacing: Self.cellSpacing) {
            Color.clear
                .frame(width: Self.nameColumnWidth, height: 1)
            ForEach(Domain.allCases, id: \.self) { domain in
                Text(Self.domainAbbreviations[domain] ?? domain.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.apTextTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    private func rowView(_ row: OverviewRow) -> some View {
        NavigationLink(
            destination: ProjectTabView(
                project: row.project,
                questionStore: questionStore
            )
        ) {
            HStack(spacing: Self.cellSpacing) {
                Text(row.project.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: Self.nameColumnWidth, alignment: .leading)
                ForEach(Domain.allCases, id: \.self) { domain in
                    scoreCell(row.scores?.first { $0.domain == domain })
                }
            }
            .padding(8)
            .background(Color.apSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .haptic(.light)
    }

    private func scoreCell(_ ds: DomainScore?) -> some View {
        Text(ds.map { "\($0.score)" } ?? "–")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(ds.map { cellColor(for: $0.level) } ?? .apTextTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(ds.map { cellBackground(for: $0.level) } ?? .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func cellColor(for level: ScoreLevel) -> Color {
        switch level {
        case .risk:   return .apRisk
        case .note:   return .apNote
        case .strong: return .apStrong
        }
    }

    private func cellBackground(for level: ScoreLevel) -> Color {
        switch level {
        case .risk:   return Color.apRisk.opacity(0.14)
        case .note:   return Color.apNote.opacity(0.13)
        case .strong: return Color.apStrong.opacity(0.13)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .apRisk, label: "0-33 risk")
            legendItem(color: .apNote, label: "34-65 bevaka")
            legendItem(color: .apStrong, label: "66+ starkt")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.apTextSecondary)
        }
    }

    // MARK: - Data

    private func loadOverview() async {
        isLoading = true
        defer { isLoading = false }

        let projectStore = ProjectStore()
        await projectStore.fetch()
        guard projectStore.error == nil else {
            loadFailed = true
            return
        }
        let projects = projectStore.projects

        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }
        let questions = questionStore.questions
        let options = questionStore.options

        var scoresByProject: [UUID: [DomainScore]] = [:]
        await withTaskGroup(of: (UUID, [DomainScore]?).self) { group in
            for project in projects {
                group.addTask { @MainActor in
                    let assessmentStore = AssessmentStore()
                    await assessmentStore.fetch(projectId: project.id)
                    guard let latest = assessmentStore.assessments.max(by: { $0.version < $1.version }) else {
                        return (project.id, nil)
                    }
                    let answerStore = AnswerStore()
                    await answerStore.fetch(assessmentId: latest.id)
                    let scores = ScoringService.compute(
                        answers: answerStore.answers,
                        questions: questions,
                        options: options
                    )
                    return (project.id, scores)
                }
            }
            for await (projectId, scores) in group {
                if let scores {
                    scoresByProject[projectId] = scores
                }
            }
        }

        rows = projects.map { OverviewRow(project: $0, scores: scoresByProject[$0.id]) }
    }
}

private struct OverviewRow: Identifiable {
    let project: Project
    let scores: [DomainScore]?
    var id: UUID { project.id }
}
