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
    let id: UUID             // plan_actions.id — what tasks link back to
    let text: String
    let domain: String?
    let phaseIndex: Int      // 0 = 1–30, 1 = 31–60, 2 = 61–90
    let phaseLabel: String   // "Dag 1–30"
    let order: Int           // original flat index, for stable sorting
}

struct PlanView: View {
    var project: Project
    var questionStore: QuestionStore
    var actionStore: ActionStore

    // Source assessment context
    @State private var sourceAssessment: Assessment? = nil
    /// Built once per load() — from plan_actions rows, or from the legacy
    /// JSONB fallback. Non-empty exactly when sourceAssessment != nil.
    @State private var items: [PlanItem] = []
    @State private var planStore = PlanStore()
    @State private var domainScores: [DomainScore] = []
    @State private var answerStore = AnswerStore()

    @State private var showReplaceConfirm = false

    // Row state
    /// The plan item whose swipe actions are revealed, if any.
    @State private var openSwipeId: UUID? = nil
    // Section expansion: waiting is deliberately-deferred ACTIVE work and
    // stays visible by default; only finished work starts collapsed.
    @State private var waitingExpanded = true
    @State private var doneExpanded = false
    /// The plan item awaiting the "Ta bort ur planen?" confirmation.
    @State private var pendingPlanDelete: PlanItem? = nil
    /// Plan item ids whose done-marked action is being inserted — renders as
    /// done before the row lands in actionStore.actions.
    @State private var pendingPlanIds: Set<UUID> = []

    // View state
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            APAmbientBackground()
            content
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .confirmationDialog(
            "Ta bort ur planen?",
            isPresented: Binding(
                get: { pendingPlanDelete != nil },
                set: { if !$0 { pendingPlanDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ta bort", role: .destructive) {
                guard let item = pendingPlanDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingPlanDelete = nil
                deleteFromPlan(item)
            }
            Button("Avbryt", role: .cancel) { pendingPlanDelete = nil }
        } message: {
            Text("Åtgärden tas bort ur planen. En kopplad uppgift ligger kvar under Åtgärder.")
        }
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
        } else if sourceAssessment != nil {
            todoList
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
            // Första planen genereras automatiskt när en assessment
            // slutförs (ResultView) — ingen manuell trigger här.
            Text("Slutför en assessment så skapas planen automatiskt.")
                .font(.subheadline)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
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

    private var todoList: some View {
        let sections = makeSections()
        let total = items.count
        let done = sections.done.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                progressHeader(done: done, total: total)

                if !sections.prio.isEmpty {
                    planSection(title: "PRIO", tint: Color.apOrange, list: sections.prio)
                }
                if !sections.open.isEmpty {
                    planSection(title: "ATT GÖRA", tint: nil, list: sections.open)
                }
                if !sections.waiting.isEmpty {
                    collapsibleSection(title: "VÄNTAR", countTint: Color.apWaiting, list: sections.waiting, expanded: $waitingExpanded)
                }
                if !sections.done.isEmpty {
                    collapsibleSection(title: "KLART", countTint: Color.apStrong, list: sections.done, expanded: $doneExpanded)
                }

                // Regeneration replaces the shown active plan — confirmed.
                // (First generation is automatic on assessment completion.)
                if let source = sourceAssessment {
                    APPillButton(title: "Generera ny plan", action: {
                        showReplaceConfirm = true
                    }, style: .secondary)
                    .confirmationDialog(
                        "Ersätt nuvarande plan?",
                        isPresented: $showReplaceConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Ersätt", role: .destructive) {
                            Task { await generate(for: source, replacingActive: true) }
                        }
                        Button("Avbryt", role: .cancel) {}
                    } message: {
                        Text("Nuvarande plan arkiveras. Avbockade åtgärder som känns igen följer med till den nya planen.")
                    }
                }

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
            // Spring rows between sections when a state changes (swipe
            // Prio/Vänta, circle Klar) — keyed to the store, which is where
            // the optimistic flips land.
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: actionStore.actions)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: pendingPlanIds)
        }
        .refreshable {
            actionStore.error = nil
            await actionStore.fetch(projectId: project.id)
            await load()
        }
    }

    // MARK: - Sections

    private struct PlanSections {
        var prio: [PlanItem] = []
        var open: [PlanItem] = []
        var waiting: [PlanItem] = []
        var done: [PlanItem] = []
    }

    private func itemState(_ item: PlanItem) -> TaskState {
        if let action = linkedAction(item) { return action.taskState }
        return pendingPlanIds.contains(item.id) ? .done : .open
    }

    /// Lower domain score = more urgent. Items without a resolvable domain
    /// sort last within their section.
    private func urgency(_ item: PlanItem) -> Int {
        guard let raw = item.domain,
              let domain = Domain(rawValue: raw),
              let score = domainScores.first(where: { $0.domain == domain })?.score
        else { return Int.max }
        return score
    }

    private func sortedByUrgency(_ list: [PlanItem]) -> [PlanItem] {
        list.sorted { a, b in
            let ua = urgency(a)
            let ub = urgency(b)
            if ua != ub { return ua < ub }
            return a.order < b.order
        }
    }

    private func makeSections() -> PlanSections {
        var sections = PlanSections()
        for item in items {
            switch itemState(item) {
            case .prio:    sections.prio.append(item)
            case .open:    sections.open.append(item)
            case .waiting: sections.waiting.append(item)
            case .done:    sections.done.append(item)
            }
        }
        sections.prio = sortedByUrgency(sections.prio)
        sections.open = sortedByUrgency(sections.open)
        sections.waiting = sortedByUrgency(sections.waiting)
        sections.done = sortedByUrgency(sections.done)
        return sections
    }

    private func planSection(title: String, tint: Color?, list: [PlanItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .tracking(1.5)
                .foregroundStyle(tint ?? Color.apTextSecondary)
            itemCard(list)
        }
    }

    private func collapsibleSection(title: String, countTint: Color, list: [PlanItem], expanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // Only the count carries the section color.
                    HStack(spacing: 4) {
                        Text("\(title) ·")
                            .foregroundStyle(Color.apTextSecondary)
                        Text("\(list.count)")
                            .foregroundStyle(countTint)
                    }
                    .font(.caption)
                    .tracking(1.5)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.apTextTertiary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                itemCard(list)
            }
        }
    }

    private func itemCard(_ list: [PlanItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                itemRow(item)
                if index != list.count - 1 {
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
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: done)
                }
            }
            .frame(height: 4)
        }
    }

    private func itemRow(_ item: PlanItem) -> some View {
        // Prio/Vänta write the linked action's state, creating the link when
        // none exists. Ta bort removes the plan_actions row (plan curation)
        // behind a confirm — a linked task survives in Åtgärder via the
        // FK's SET NULL. Klar stays on the circle tap.
        rowContent(item)
            .apSwipeActions(id: item.id, openId: $openSwipeId, actions: [
                APSwipeAction(title: "Prio", systemImage: "flag.fill", color: .apOrange) {
                    setLinkedState(item, to: .prio)
                },
                APSwipeAction(title: "Vänta", systemImage: "clock", color: .apWaiting) {
                    setLinkedState(item, to: .waiting)
                },
                APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                    pendingPlanDelete = item
                }
            ])
    }

    private func deleteFromPlan(_ item: PlanItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            _ = items.remove(at: index)
        }
        Task {
            do {
                try await planStore.deletePlanAction(item.id)
                // The FK nulled any linked task's plan_action_id server-side;
                // refetch so the in-memory link doesn't go stale.
                await actionStore.fetch(projectId: project.id)
            } catch {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    items.insert(item, at: min(index, items.count))
                }
                errorMessage = error.localizedDescription
                print("PlanView: deleteFromPlan error: \(error)")
            }
        }
    }

    private func setLinkedState(_ item: PlanItem, to state: TaskState) {
        if let action = linkedAction(item) {
            Task { await actionStore.setState(action, to: state) }
        } else {
            createLinkedAction(item, state: state)
        }
    }

    @ViewBuilder
    private func rowContent(_ item: PlanItem) -> some View {
        let done = isDone(item)

        // Full text always — no expand/collapse: the tap-and-chevron
        // interaction raced the swipe gesture for the same drag.
        HStack(alignment: .top, spacing: 12) {
            statusCircle(item)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.subheadline)
                    .strikethrough(done)
                    .foregroundStyle(done ? Color.apTextTertiary : Color.apTextPrimary)
                    .multilineTextAlignment(.leading)
                // State tag + domain: the tag keeps the row legible when
                // scrolled away from its section header. ATT GÖRA and KLART
                // rows carry no tag (default resp. strikethrough reads done).
                // The phase is data-only, never shown.
                if stateTag(item) != nil || domainLabel(item) != nil {
                    HStack(spacing: 6) {
                        if let tag = stateTag(item) {
                            Text(tag.word)
                                .foregroundStyle(tag.color)
                        }
                        if let domain = domainLabel(item) {
                            Text(domain)
                                .foregroundStyle(Color.apTextTertiary)
                        }
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isDone(item))
        }
        .buttonStyle(.plain)
        .haptic(.light)
        .minTapTarget()
    }

    /// Binary: green check when done, otherwise the empty circle — an "open"
    /// linked action draws identically to a row with no linked action yet.
    @ViewBuilder
    private func statusIcon(_ item: PlanItem) -> some View {
        if isDone(item) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.apStrong)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.apTextTertiary)
        }
    }

    // MARK: - Status

    private func linkedAction(_ item: PlanItem) -> ProjectAction? {
        actionStore.action(forPlanItem: item.id)
    }

    private func isDone(_ item: PlanItem) -> Bool {
        if let action = linkedAction(item) { return action.isDone }
        return pendingPlanIds.contains(item.id)
    }

    private func domainLabel(_ item: PlanItem) -> String? {
        // The item's domain is the action's category, shown only when valid.
        guard let raw = item.domain, Domain(rawValue: raw) != nil else { return nil }
        return raw
    }

    private func stateTag(_ item: PlanItem) -> (word: String, color: Color)? {
        switch itemState(item) {
        case .prio:    return ("Prio", Color.apOrange)
        case .waiting: return ("Väntar", Color.apWaiting)
        default:       return nil
        }
    }

    // MARK: - Circle tap

    private func handleCircleTap(_ item: PlanItem) {
        if let action = linkedAction(item) {
            // Un-toggling done goes back to "open" (draws as the empty
            // circle), never deletes — the linked Åtgärd row must survive.
            Task { await actionStore.toggle(action) }
        } else if !pendingPlanIds.contains(item.id) {
            createLinkedAction(item)
        }
    }

    private func createLinkedAction(_ item: PlanItem, state: TaskState = .done) {
        // Inserts the linked action directly in the requested state (circle
        // tap: done; swipe: prio/waiting — status stays 'open' for those).
        // Use the plan item's domain when present; otherwise silently default
        // to the source assessment's lowest-scoring domain — only as the
        // action's domain, never shown on the row.
        let domain: Domain
        if let raw = item.domain, let resolved = Domain(rawValue: raw) {
            domain = resolved
        } else if let lowest = domainScores.min(by: { $0.score < $1.score })?.domain {
            domain = lowest
        } else {
            domain = .team
        }

        if state == .done {
            pendingPlanIds.insert(item.id) // optimistic: flip to done immediately
        }

        Task {
            do {
                try await actionStore.add(
                    projectId: project.id,
                    domain: domain.rawValue,
                    title: item.text,
                    status: state == .done ? "done" : nil,
                    state: state.rawValue,
                    assessmentId: sourceAssessment?.id,
                    planActionId: item.id,
                    createdFromScore: domainScores.first { $0.domain == domain }?.score
                )
                pendingPlanIds.remove(item.id)
            } catch {
                pendingPlanIds.remove(item.id)
                errorMessage = error.localizedDescription
                print("PlanView: createLinkedAction error: \(error)")
            }
        }
    }

    // MARK: - Items

    private static func phaseIndex(_ phase: String) -> Int {
        switch phase {
        case "day1_30": return 0
        case "day31_60": return 1
        case "day61_90": return 2
        default: return 3 // unknown phase: render last instead of failing
        }
    }

    private static func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "day1_30": return "Dag 1–30"
        case "day31_60": return "Dag 31–60"
        case "day61_90": return "Dag 61–90"
        default: return phase
        }
    }

    /// Items from plan_actions rows — ids are the rows' primary keys, the
    /// same values backfilled from the old embedded ids, so existing task
    /// links resolve unchanged.
    private func makeItems(from rows: [PlanActionRow]) -> [PlanItem] {
        let ordered = rows.sorted { a, b in
            let ai = Self.phaseIndex(a.phase)
            let bi = Self.phaseIndex(b.phase)
            if ai != bi { return ai < bi }
            return a.sortOrder < b.sortOrder
        }
        return ordered.enumerated().map { index, row in
            PlanItem(
                id: row.id,
                text: row.text,
                domain: row.domain,
                phaseIndex: Self.phaseIndex(row.phase),
                phaseLabel: Self.phaseLabel(row.phase),
                order: index
            )
        }
    }

    /// Fallback items from a legacy JSONB plan without a plans row. Ids
    /// missing in the JSON are minted once per load, so expand state stays
    /// stable across renders within a session.
    private func makeItems(fromLegacy plan: PlanResult) -> [PlanItem] {
        let phases: [(Int, String, PlanPhase)] = [
            (0, "Dag 1–30", plan.day1_30),
            (1, "Dag 31–60", plan.day31_60),
            (2, "Dag 61–90", plan.day61_90)
        ]
        var items: [PlanItem] = []
        var order = 0
        for (index, label, phase) in phases {
            for action in phase.actions {
                items.append(PlanItem(
                    id: action.id ?? UUID(),
                    text: action.text,
                    domain: action.domain,
                    phaseIndex: index,
                    phaseLabel: label,
                    order: order
                ))
                order += 1
            }
        }
        return items
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

        // Primary source: the active plans row of the newest assessment that
        // has one.
        await planStore.loadNewestActivePlan(assessmentIdsNewestFirst: byNewest.map(\.id))

        if let activePlan = planStore.activePlan,
           let source = byNewest.first(where: { $0.id == activePlan.assessmentId }) {
            sourceAssessment = source
            items = makeItems(from: planStore.actions)
            await loadScores(for: source)
        } else if let source = byNewest.first(where: { $0.plan != nil }),
                  let legacy = source.plan {
            // Fallback: a JSONB plan without a plans row (defensive
            // post-backfill; also covers a plan generated before writes
            // move to rows). Display parity only.
            sourceAssessment = source
            items = makeItems(fromLegacy: legacy)
            await loadScores(for: source)
        } else {
            // No plan anywhere: first generation happens automatically when
            // an assessment is completed (ResultView), never from here.
            sourceAssessment = nil
            items = []
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

    // MARK: - Regenerate

    /// Both paths: edge function → ref→prev_id translation → regenerate_plan
    /// RPC → reload rows. No JSONB writes. `replacingActive` sends the shown
    /// active plan's actions as anchors so the RPC can re-link tasks;
    /// first generation sends none.
    private func generate(for target: Assessment, replacingActive: Bool) async {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            // The Q&A payload must belong to the target assessment — it may
            // differ from whichever assessment load() last scored.
            await loadScores(for: target)

            var currentActions: [CurrentPlanAction]? = nil
            var keyMap: [String: UUID] = [:]
            if replacingActive, planStore.activePlan?.assessmentId == target.id {
                let built = buildCurrentActions(from: planStore.actions)
                if !built.payload.isEmpty {
                    currentActions = built.payload
                    keyMap = built.keyMap
                }
            }

            let generated = try await EdgeFunctionService.generatePlan(
                scores: domainScores,
                answers: answerStore.answers,
                questions: questionStore.questions,
                options: questionStore.options,
                durationValue: project.durationValue,
                durationUnit: project.durationUnit?.rawValue,
                currentActions: currentActions
            )
            try await planStore.regenerate(
                assessmentId: target.id,
                plan: PlanStore.translate(generated, keyMap: keyMap)
            )
            // Re-load so the source/plan/scores reflect persisted state.
            // The RPC re-links tasks' plan_action_id to the new plan's rows,
            // so the shared ActionStore must refetch too — otherwise done
            // states resolve against stale ids and render as 0/N klara.
            isLoading = true
            await actionStore.fetch(projectId: project.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
            print("PlanView: generate error: \(error)")
        }
    }

    /// currentActions in the same phase/sort order the list renders, keyed
    /// "a1", "a2", ... with the key→row-id map kept for translation.
    private func buildCurrentActions(from rows: [PlanActionRow]) -> (payload: [CurrentPlanAction], keyMap: [String: UUID]) {
        let ordered = rows.sorted { a, b in
            let ai = Self.phaseIndex(a.phase)
            let bi = Self.phaseIndex(b.phase)
            if ai != bi { return ai < bi }
            return a.sortOrder < b.sortOrder
        }
        var payload: [CurrentPlanAction] = []
        var keyMap: [String: UUID] = [:]
        for (index, row) in ordered.enumerated() {
            let key = "a\(index + 1)"
            keyMap[key] = row.id
            payload.append(CurrentPlanAction(key: key, phase: row.phase, text: row.text, domain: row.domain))
        }
        return (payload, keyMap)
    }
}
