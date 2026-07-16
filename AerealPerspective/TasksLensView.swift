//
//  TasksLensView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-16.
//

import Foundation
import SwiftUI

/// Value pushed onto the Översikt stack: opens the team's Plan segment.
struct TeamPlanRoute: Hashable {
    let project: Project
}

/// The global Tasks lens: read-only triage over every team's open actions,
/// grouped PRIO / ATT GÖRA / VÄNTAR and urgency-sorted by OpenActionsStore.
/// No swipes, no state mutation — a row tap navigates to the team's Plan.
struct TasksLensView: View {
    var store: OpenActionsStore
    var questionStore: QuestionStore
    /// projectId → Project for building routes; rows whose project isn't
    /// resolvable yet render without navigation until the health load lands.
    var projectsById: [UUID: Project]

    var body: some View {
        if store.isLoading {
            ProgressView()
                .tint(.apOrange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.error != nil {
            APErrorState {
                store.error = nil
                Task { await store.load(questionStore: questionStore) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.prio.isEmpty && store.open.isEmpty && store.waiting.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            taskList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 44))
                .foregroundStyle(.apOrange)
            Text("Inga öppna tasks")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            Text("Alla teams uppgifter är klara.")
                .font(.caption)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(title: "PRIO", tint: .apRisk, rows: store.prio)
                section(title: "ATT GÖRA", tint: nil, rows: store.open)
                // Waiting rows draw dimmed — parked, not actionable here.
                section(title: "VÄNTAR", tint: .apWaiting, rows: store.waiting, dimmed: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .refreshable { await store.reload(questionStore: questionStore) }
    }

    @ViewBuilder
    private func section(title: String, tint: Color?, rows: [OpenActionRow], dimmed: Bool = false) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .tracking(1.5)
                    .foregroundStyle(tint ?? Color.apTextSecondary)
                rowCard(rows, dimmed: dimmed)
            }
        }
    }

    private func rowCard(_ rows: [OpenActionRow], dimmed: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowLink(row, dimmed: dimmed)
                if index != rows.count - 1 {
                    Divider().background(Color.apHairline)
                }
            }
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func rowLink(_ row: OpenActionRow, dimmed: Bool) -> some View {
        if let project = projectsById[row.action.projectId] {
            NavigationLink(value: TeamPlanRoute(project: project)) {
                rowContent(row)
            }
            .buttonStyle(APRowPressStyle())
            .haptic(.light)
            .opacity(dimmed ? 0.6 : 1)
        } else {
            rowContent(row)
                .opacity(dimmed ? 0.6 : 1)
        }
    }

    private func rowContent(_ row: OpenActionRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.action.title)
                .font(.subheadline)
                .foregroundStyle(.apTextPrimary)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                teamPill(row.teamName)
                domainPill(row)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func teamPill(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2")
                .font(.system(size: 9, weight: .semibold))
            Text(name)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.apTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.apTextSecondary.opacity(0.15))
        .clipShape(Capsule())
        .lineLimit(1)
    }

    /// Score-band colored via the row's urgency (the domain's current
    /// score); unresolvable domain/score falls back to a neutral pill.
    private func domainPill(_ row: OpenActionRow) -> some View {
        let label = Domain(caseInsensitive: row.action.domain)?.rawValue
            ?? row.action.domain.capitalized
        let band = row.urgency.map { Color.apScore($0) } ?? Color.apTextTertiary
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(band)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(band.opacity(0.15))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}
