//
//  PlanView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-19.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

// MARK: - Flattened to-do item

private struct PlanItem: Identifiable {
    let action: PlanAction
    let phaseIndex: Int      // 0 = 1–30, 1 = 31–60, 2 = 61–90
    let phaseLabel: String   // "Dag 1–30"
    let order: Int           // original flat index, for stable sorting

    var id: UUID? { action.id }

    /// First sentence of the text, split on the first ". ".
    var shortText: String {
        if let range = action.text.range(of: ". ") {
            return String(action.text[..<range.lowerBound]) + "."
        }
        return action.text
    }
}

struct PlanView: View {
    var project: Project
    var questionStore: QuestionStore
    var actionStore: ActionStore

    // Source assessment context
    @State private var sourceAssessment: Assessment? = nil
    @State private var plan: PlanResult? = nil
    @State private var domainScores: [DomainScore] = []
    @State private var answerStore = AnswerStore()

    // Generate target when no plan exists yet
    @State private var generateTarget: Assessment? = nil

    // Row state
    @State private var expandedItems: Set<UUID> = []
    /// Plan item ids whose linked action is being created — drives optimistic
    /// "Pågår" before the inserted action lands in actionStore.actions.
    @State private var pendingPlanIds: Set<UUID> = []

    // View state
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    /// Cycled by APGeneratingState while generate-plan-funktionen kör.
    private static let generationPhrases: [String] = [
        "Analyserar dina svar...",
        "Prioriterar åtgärder...",
        "Bygger dag 1–30...",
        "Bygger dag 31–60...",
        "Bygger dag 61–90...",
        "Finslipar planen..."
    ]

    @ViewBuilder
    private var content: some View {
        if isGenerating {
            APGeneratingState(phrases: Self.generationPhrases)
        } else if isLoading {
            loadingState("Laddar plan...")
        } else if let plan {
            todoList(plan)
        } else {
            emptyState
        }
    }

    private func loadingState(_ label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.apOrange)
            Text(label)
                .foregroundStyle(.apTextSecondary)
                .font(.subheadline)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.apOrange)
            Text("Ingen plan ännu")
                .foregroundStyle(.apTextPrimary)
                .font(.headline)
            if generateTarget != nil {
                APPillButton(title: "Generera 30-60-90 plan", action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await generate() }
                })
                .padding(.horizontal, 40)
            } else {
                Text("Kör en assessment först")
                    .font(.subheadline)
                    .foregroundStyle(.apTextSecondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.apRisk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - To-do list

    private func todoList(_ plan: PlanResult) -> some View {
        let items = sortedItems(plan)
        let total = items.count
        let done = items.filter { isDone($0) }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressHeader(done: done, total: total)

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.order) { index, item in
                        itemRow(item)
                        if index != items.count - 1 {
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

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.apRisk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            actionStore.error = nil
            await actionStore.fetch(projectId: project.id)
            await load()
        }
    }

    private func progressHeader(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = sourceAssessment {
                Text("Baserad på Assessment \(source.version)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apTextSecondary)
            }
            HStack {
                Text("\(done) / \(total) klara")
                    .font(.subheadline.bold())
                    .foregroundStyle(.apTextPrimary)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.apHairline)
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.apStrong)
                        .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(done) / CGFloat(total), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PlanItem) -> some View {
        let done = isDone(item)
        let expanded = item.id.map { expandedItems.contains($0) } ?? false

        HStack(alignment: .top, spacing: 12) {
            statusCircle(item)

            Button {
                guard let id = item.id else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if expandedItems.contains(id) {
                        expandedItems.remove(id)
                    } else {
                        expandedItems.insert(id)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(expanded ? item.action.text : item.shortText)
                        .font(.subheadline)
                        .strikethrough(done)
                        .foregroundStyle(done ? Color.apTextTertiary : Color.apTextPrimary)
                        .multilineTextAlignment(.leading)
                    Text(metadataLine(item))
                        .font(.caption)
                        .foregroundStyle(.apTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.id == nil)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.apTextTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(done ? 0.6 : 1)
    }

    private func statusCircle(_ item: PlanItem) -> some View {
        Button {
            handleCircleTap(item)
        } label: {
            statusIcon(item)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .haptic(.light)
        .minTapTarget()
    }

    @ViewBuilder
    private func statusIcon(_ item: PlanItem) -> some View {
        switch status(item) {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundStyle(.apTextTertiary)
        case .inProgress:
            Image(systemName: "smallcircle.filled.circle")
                .foregroundStyle(.apOrange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.apStrong)
        }
    }

    // MARK: - Status

    private enum ItemStatus { case notStarted, inProgress, done }

    private func linkedAction(_ item: PlanItem) -> ProjectAction? {
        guard let id = item.id else { return nil }
        return actionStore.action(forPlanItem: id)
    }

    private func status(_ item: PlanItem) -> ItemStatus {
        if let action = linkedAction(item) {
            return action.isDone ? .done : .inProgress
        }
        if let id = item.id, pendingPlanIds.contains(id) {
            return .inProgress
        }
        return .notStarted
    }

    private func isDone(_ item: PlanItem) -> Bool {
        linkedAction(item)?.isDone ?? false
    }

    private func metadataLine(_ item: PlanItem) -> String {
        // PlanAction.domain is the action's category, shown only when present.
        if let raw = item.action.domain, Domain(rawValue: raw) != nil {
            return "\(item.phaseLabel) · \(raw)"
        }
        return item.phaseLabel
    }

    // MARK: - Circle tap

    private func handleCircleTap(_ item: PlanItem) {
        guard let id = item.id else { return }
        switch status(item) {
        case .notStarted:
            createLinkedAction(item, id: id)
        case .inProgress, .done:
            // Non-destructive: surfacing the action in Åtgärder needs cross-tab
            // coordination DocumentView doesn't support, so this is a no-op.
            break
        }
    }

    private func createLinkedAction(_ item: PlanItem, id: UUID) {
        // One tap, no sheet. Use the plan item's domain when present; otherwise
        // silently default to the source assessment's lowest-scoring domain —
        // only as the action's domain, never shown in the plan metadata line.
        let domain: Domain
        if let raw = item.action.domain, let resolved = Domain(rawValue: raw) {
            domain = resolved
        } else if let lowest = domainScores.min(by: { $0.score < $1.score })?.domain {
            domain = lowest
        } else {
            domain = .team
        }

        pendingPlanIds.insert(id) // optimistic: flip to "Pågår" immediately
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await actionStore.add(
                    projectId: project.id,
                    domain: domain.rawValue,
                    title: item.action.text,
                    assessmentId: sourceAssessment?.id,
                    planActionId: id,
                    createdFromScore: domainScores.first { $0.domain == domain }?.score
                )
            } catch {
                pendingPlanIds.remove(id)
                errorMessage = error.localizedDescription
                print("PlanView: createLinkedAction error: \(error)")
            }
        }
    }

    // MARK: - Sorting

    private func flatItems(_ plan: PlanResult) -> [PlanItem] {
        let phases: [(Int, String, PlanPhase)] = [
            (0, "Dag 1–30", plan.day1_30),
            (1, "Dag 31–60", plan.day31_60),
            (2, "Dag 61–90", plan.day61_90)
        ]
        var items: [PlanItem] = []
        var order = 0
        for (index, label, phase) in phases {
            for action in phase.actions {
                items.append(PlanItem(action: action, phaseIndex: index, phaseLabel: label, order: order))
                order += 1
            }
        }
        return items
    }

    /// Undone first, done last. Within each group, preserve phase order
    /// (and original order within a phase) via the stable `order` tiebreaker.
    private func sortedItems(_ plan: PlanResult) -> [PlanItem] {
        flatItems(plan).sorted { a, b in
            let aDone = isDone(a)
            let bDone = isDone(b)
            if aDone != bDone { return !aDone }
            if a.phaseIndex != b.phaseIndex { return a.phaseIndex < b.phaseIndex }
            return a.order < b.order
        }
    }

    // MARK: - Load

    private func load() async {
        errorMessage = nil
        let assessmentStore = AssessmentStore()
        await assessmentStore.fetch(projectId: project.id)
        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }

        let byNewest = assessmentStore.assessments.sorted { $0.version > $1.version }

        // Source: latest assessment that already has a plan.
        if let source = byNewest.first(where: { $0.plan != nil }) {
            sourceAssessment = source
            plan = source.plan
            generateTarget = nil
            await loadScores(for: source)
        } else {
            // No plan anywhere: offer to generate for the latest completed one.
            sourceAssessment = nil
            plan = nil
            generateTarget = await latestCompleted(in: byNewest)
            if let target = generateTarget {
                await loadScores(for: target)
            }
        }

        isLoading = false
    }

    /// Loads answers for `assessment` and computes its domain scores. The
    /// scores back the lowest-domain default and `generate()`.
    private func loadScores(for assessment: Assessment) async {
        await answerStore.fetch(assessmentId: assessment.id)
        domainScores = ScoringService.compute(
            answers: answerStore.answers,
            questions: questionStore.questions,
            options: questionStore.options
        )
    }

    /// The newest assessment with all questions answered, scanning newest-first.
    private func latestCompleted(in byNewest: [Assessment]) async -> Assessment? {
        let total = questionStore.questions.count
        guard total > 0 else { return nil }
        for assessment in byNewest {
            let store = AnswerStore()
            await store.fetch(assessmentId: assessment.id)
            if store.answers.count >= total {
                return assessment
            }
        }
        return nil
    }

    // MARK: - Generate

    private func generate() async {
        guard let target = generateTarget else { return }
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            let result = try await EdgeFunctionService.generatePlan(
                scores: domainScores,
                answers: answerStore.answers,
                questions: questionStore.questions,
                options: questionStore.options,
                durationValue: project.durationValue,
                durationUnit: project.durationUnit?.rawValue
            )
            try await supabase
                .from("assessments")
                .update(AssessmentPlanUpdate(plan: result))
                .eq("id", value: target.id)
                .execute()
            // Re-load so the source/plan/scores reflect persisted state.
            isLoading = true
            await load()
        } catch {
            errorMessage = error.localizedDescription
            print("PlanView: generate error: \(error)")
        }
    }
}

private struct AssessmentPlanUpdate: Encodable {
    let plan: PlanResult
}
