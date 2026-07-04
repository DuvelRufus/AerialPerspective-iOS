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
    @State private var openCounts: [UUID: Int] = [:]
    @State private var isLoading = true
    @State private var loadFailed = false
    // Driver den staggrade "tänds upp"-effekten när heatmapen visas.
    @State private var rowsRevealed = false

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
            APAmbientBackground()

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
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row)
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
                legend
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .onAppear { rowsRevealed = true }
        .refreshable { await loadOverview(showSpinner: false) }
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.project.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.apTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let count = openCounts[row.project.id], count > 0 {
                        Text("\(count) öppna")
                            .font(.caption2)
                            .foregroundStyle(.apOrange)
                    }
                }
                .frame(width: Self.nameColumnWidth, alignment: .leading)
                ForEach(Domain.allCases, id: \.self) { domain in
                    scoreCell(row.scores?[domain])
                }
            }
            .padding(8)
            .background(Color.apSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.apHairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(APRowPressStyle())
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

    private func loadOverview(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        defer { isLoading = false }

        let projectStore = ProjectStore()
        await projectStore.fetch()
        guard projectStore.error == nil else {
            loadFailed = true
            return
        }
        let projects = projectStore.projects

        await fetchOpenCounts()

        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }
        let questions = questionStore.questions
        let options = questionStore.options

        var scoresByProject: [UUID: [Domain: DomainScore]] = [:]
        await withTaskGroup(of: (UUID, [Domain: DomainScore]?).self) { group in
            for project in projects {
                group.addTask { @MainActor in
                    let assessmentStore = AssessmentStore()
                    await assessmentStore.fetch(projectId: project.id)
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
                        return (project.id, byDomain)
                    }
                    return (project.id, nil)
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

    private func fetchOpenCounts() async {
        do {
            let rows: [OpenActionRow] = try await supabase
                .from("actions")
                .select("project_id")
                .eq("status", value: "open")
                .execute()
                .value
            var counts: [UUID: Int] = [:]
            for row in rows {
                counts[row.projectId, default: 0] += 1
            }
            openCounts = counts
        } catch {
            print("OversiktView: fetchOpenCounts error: \(error)")
        }
    }
}

private struct OpenActionRow: Codable {
    let projectId: UUID
    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
    }
}

private struct OverviewRow: Identifiable {
    let project: Project
    /// nil = no assessment with any answers; missing domain key = domain unanswered.
    let scores: [Domain: DomainScore]?
    var id: UUID { project.id }
}
