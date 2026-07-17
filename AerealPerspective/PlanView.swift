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

/// One row in the unified list: a plan_actions item (possibly with a
/// linked action) or an unlinked action (manual / insight-created).
/// The id spaces are disjoint — plan_actions.id vs actions.id — so a
/// single UUID identity is safe for ForEach/swipe/confirm state.
private enum PlanRow: Identifiable {
    case planItem(PlanItem)
    case action(ProjectAction)

    var id: UUID {
        switch self {
        case .planItem(let item): return item.id
        case .action(let action): return action.id
        }
    }
}

struct PlanView: View {
    var project: Project
    var questionStore: QuestionStore
    var actionStore: ActionStore

    // Source assessment context
    @State private var sourceAssessment: Assessment? = nil
    /// The team's newest assessment regardless of plan — FAB fallback and
    /// plan-less context that must survive load()'s scope. sourceAssessment
    /// keeps meaning "the plan's source" and gates the plan artifacts.
    @State private var latestAssessment: Assessment? = nil
    /// Built once per load() — from plan_actions rows, or from the legacy
    /// JSONB fallback. Non-empty exactly when sourceAssessment != nil.
    @State private var items: [PlanItem] = []
    @State private var planStore = PlanStore()
    @State private var domainScores: [DomainScore] = []
    @State private var answerStore = AnswerStore()

    @State private var showReplaceConfirm = false

    // Row state
    /// The row whose swipe actions are revealed, if any.
    @State private var openSwipeId: UUID? = nil
    // Section expansion: waiting is deliberately-deferred ACTIVE work and
    // stays visible by default; only finished work starts collapsed.
    @State private var waitingExpanded = true
    @State private var doneExpanded = false
    /// What the delete confirm operates on: a plan item (SET NULL — a
    /// linked task survives) or an unlinked action (hard delete).
    private enum PendingDelete {
        case plan(PlanItem)
        case action(ProjectAction)
    }
    @State private var pendingDelete: PendingDelete? = nil
    /// Plan item ids whose done-marked action is being inserted — renders as
    /// done before the row lands in actionStore.actions.
    @State private var pendingPlanIds: Set<UUID> = []

    // View state
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var errorMessage: String? = nil
    @State private var showAddSheet = false

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
            deleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ta bort", role: .destructive) {
                guard let intent = pendingDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDelete = nil
                switch intent {
                case .plan(let item):
                    deleteFromPlan(item)
                case .action(let action):
                    Task { await actionStore.delete(action) }
                }
            }
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet(defaultDomain: weakestDomain) { domain, title in
                Task { await addManualAction(domain: domain, title: title) }
            }
        }
    }

    private var deleteTitle: String {
        switch pendingDelete {
        case .action: return "Ta bort uppgift?"
        default:      return "Ta bort ur planen?"
        }
    }

    private var deleteMessage: String {
        switch pendingDelete {
        case .action:
            return "Uppgiften tas bort permanent. Åtgärden kan inte ångras."
        case .plan(let item):
            return linkedAction(item) != nil
                ? "Åtgärden och dess kopplade uppgift tas bort permanent. Det kan inte ångras."
                : "Åtgärden tas bort ur planen. Det kan inte ångras."
        case nil:
            return ""
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
        } else if sourceAssessment != nil || hasAnyRows {
            // Plan is a task view: any row (plan-linked or unlinked) shows
            // the list. The sourceAssessment side keeps the emptied-plan
            // corner intact — an active plan with zero rows still shows the
            // header and the regenerate button.
            todoList
        } else {
            emptyState
        }
    }

    /// Cheap row-existence check — no makeSections cost: any plan item or
    /// any unlinked action makes the task list worth showing.
    private var hasAnyRows: Bool {
        !items.isEmpty || actionStore.actions.contains { $0.planActionId == nil }
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
            Text("Inga tasks ännu")
                .foregroundStyle(.apTextPrimary)
                .font(.headline)
            // Första planen genereras fortfarande automatiskt när en
            // assessment slutförs (ResultView) — härifrån skapas tasks
            // via insikter eller FAB:en.
            Text("Skapa tasks från insikter eller lägg till egna med plusknappen.")
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
        // Anchor to the screen corner, not the centered VStack, so the
        // first manual task can be created from the empty state too.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            addButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - To-do list

    private var todoList: some View {
        let sections = makeSections()
        // Both row kinds count — the header tracks the whole unified list.
        let total = sections.prio.count + sections.open.count
            + sections.waiting.count + sections.done.count
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
            // Spring rows between sections when membership changes (swipe
            // Prio/Vänta, circle Klar) — keyed to section membership, not the
            // store array, so in-place mutations and refetch value-diffs
            // can't re-animate rows under an in-flight swipe gesture.
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sectionSignature(sections))
        }
        .refreshable {
            actionStore.error = nil
            await actionStore.fetch(projectId: project.id)
            await load()
        }
        // Sibling layer on the ScrollView — outside the section VStack, so
        // the sectionSignature animation subtree is untouched. Shows with or
        // without a plan; addManualAction falls back to latestAssessment.
        .overlay(alignment: .bottomTrailing) {
            addButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Add task

    private var addButton: some View {
        // Haptic fires in the action closure — a stacked .haptic gesture
        // starves ButtonStyle's isPressed and kills the press feedback.
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.apOrange))
        }
        .buttonStyle(APFabPressStyle())
    }

    /// Default for the sheet's domain picker: the current weakest domain.
    private var weakestDomain: Domain {
        domainScores.min { $0.score < $1.score }?.domain
            ?? Domain.allCases.first
            ?? .team
    }

    /// Manual creation, moved here from Åtgärder (phase 1b). No planActionId
    /// — the row lands as an unlinked open action, rendered by the .action
    /// branch. add inserts into the shared store's array, so makeSections
    /// picks it up without a refetch.
    private func addManualAction(domain: Domain, title: String) async {
        do {
            try await actionStore.add(
                projectId: project.id,
                domain: domain.rawValue,
                title: title,
                // Plan-less teams tie the task to the newest assessment;
                // nil (no assessments at all) is allowed by add.
                assessmentId: sourceAssessment?.id ?? latestAssessment?.id,
                createdFromScore: domainScores.first { $0.domain == domain }?.score
            )
        } catch {
            errorMessage = error.localizedDescription
            print("PlanView: addManualAction error: \(error)")
        }
    }

    // MARK: - Sections

    private struct PlanSections {
        var prio: [PlanRow] = []
        var open: [PlanRow] = []
        var waiting: [PlanRow] = []
        var done: [PlanRow] = []

        mutating func append(_ row: PlanRow, state: TaskState) {
            switch state {
            case .prio:    prio.append(row)
            case .open:    open.append(row)
            case .waiting: waiting.append(row)
            case .done:    done.append(row)
            }
        }
    }

    private func itemState(_ item: PlanItem) -> TaskState {
        if let action = linkedAction(item) { return action.taskState }
        return pendingPlanIds.contains(item.id) ? .done : .open
    }

    /// Lower domain score = more urgent. Items without a resolvable domain
    /// sort last within their section.
    private func urgency(_ item: PlanItem) -> Int {
        guard let raw = item.domain,
              let domain = Domain(caseInsensitive: raw),
              let score = domainScores.first(where: { $0.domain == domain })?.score
        else { return Int.max }
        return score
    }

    /// The same urgency key for both row kinds: the current score of the
    /// row's domain; unresolvable sorts last.
    private func rowUrgency(_ row: PlanRow) -> Int {
        switch row {
        case .planItem(let item):
            return urgency(item)
        case .action(let action):
            guard let domain = Domain(caseInsensitive: action.domain),
                  let score = domainScores.first(where: { $0.domain == domain })?.score
            else { return Int.max }
            return score
        }
    }

    private func sortedByUrgency(_ list: [PlanRow]) -> [PlanRow] {
        list.sorted { a, b in
            let ua = rowUrgency(a)
            let ub = rowUrgency(b)
            if ua != ub { return ua < ub }
            // Ties: plan items keep their flat plan order; unlinked actions
            // have no plan order and break newest-first (as the global Tasks
            // lens); mixed pairs put the plan item first — plan rows are
            // the spine of the list.
            switch (a, b) {
            case (.planItem(let x), .planItem(let y)): return x.order < y.order
            case (.action(let x), .action(let y)):     return x.createdAt > y.createdAt
            case (.planItem, .action):                 return true
            case (.action, .planItem):                 return false
            }
        }
    }

    private func makeSections() -> PlanSections {
        var sections = PlanSections()
        for item in items {
            sections.append(.planItem(item), state: itemState(item))
        }
        // Unlinked actions (manual / insight-created); a linked action is
        // already owned by its plan item above, so no row can double.
        for action in actionStore.actions where action.planActionId == nil {
            sections.append(.action(action), state: action.taskState)
        }
        sections.prio = sortedByUrgency(sections.prio)
        sections.open = sortedByUrgency(sections.open)
        sections.waiting = sortedByUrgency(sections.waiting)
        sections.done = sortedByUrgency(sections.done)
        return sections
    }

    /// Animation key for the section VStack: row ids grouped per section in
    /// render order. Changes exactly when a row moves section, appears,
    /// disappears, or reorders — NOT when an action's fields mutate in place
    /// or a refetch replaces the array with membership-equal rows, so an
    /// array-wide animation can never fire under an active swipe drag.
    /// pendingPlanIds is covered too: itemState reads it, so an optimistic
    /// done-flip moves the row and thereby the signature.
    private func sectionSignature(_ sections: PlanSections) -> [[UUID]] {
        [
            sections.prio.map(\.id),
            sections.open.map(\.id),
            sections.waiting.map(\.id),
            sections.done.map(\.id)
        ]
    }

    private func planSection(title: String, tint: Color?, list: [PlanRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .tracking(1.5)
                .foregroundStyle(tint ?? Color.apTextSecondary)
            itemCard(list)
        }
    }

    private func collapsibleSection(title: String, countTint: Color, list: [PlanRow], expanded: Binding<Bool>) -> some View {
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

    private func itemCard(_ list: [PlanRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                rowView(row)
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

    @ViewBuilder
    private func rowView(_ row: PlanRow) -> some View {
        switch row {
        case .planItem(let item): itemRow(item)
        case .action(let action): actionRow(action)
        }
    }

    private func itemRow(_ item: PlanItem) -> some View {
        // Prio/Vänta write the linked action's state, creating the link when
        // none exists. Ta bort deletes the plan_actions row AND its linked
        // action behind a confirm (deleteFromPlan) — gone means gone.
        // Klar stays on the circle tap.
        rowContent(item)
            .apSwipeActions(id: item.id, openId: $openSwipeId, actions: [
                APSwipeAction(title: "Prio", systemImage: "flag.fill", color: .apOrange) {
                    setLinkedState(item, to: .prio)
                },
                APSwipeAction(title: "Vänta", systemImage: "clock", color: .apWaiting) {
                    setLinkedState(item, to: .waiting)
                },
                APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                    pendingDelete = .plan(item)
                }
            ])
    }

    /// Unlinked action row (manual / insight-created). Prio/Vänta write the
    /// action's OWN state — never create a linked action — and Ta bort is a
    /// hard delete behind its own confirm (no plan_actions row to SET NULL).
    private func actionRow(_ action: ProjectAction) -> some View {
        actionRowContent(action)
            .apSwipeActions(id: action.id, openId: $openSwipeId, actions: [
                APSwipeAction(title: "Prio", systemImage: "flag.fill", color: .apOrange) {
                    Task { await actionStore.setState(action, to: .prio) }
                },
                APSwipeAction(title: "Vänta", systemImage: "clock", color: .apWaiting) {
                    Task { await actionStore.setState(action, to: .waiting) }
                },
                APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                    pendingDelete = .action(action)
                }
            ])
    }

    private func deleteFromPlan(_ item: PlanItem) {
        // Capture the link BEFORE the optimistic removal — the lookup reads
        // live store state that later steps mutate.
        let linked = linkedAction(item)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            _ = items.remove(at: index)
        }
        Task {
            // A linked action is hard-deleted FIRST: once it is gone from the
            // DB, neither the FK's SET NULL nor any refetch can resurrect it
            // as an unlinked row. ActionStore.delete swallows its error and
            // rolls its array back — failure is detected by reappearance.
            if let linked {
                await actionStore.delete(linked)
                if actionStore.actions.contains(where: { $0.id == linked.id }) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        items.insert(item, at: min(index, items.count))
                    }
                    errorMessage = "Kunde inte ta bort uppgiften. Försök igen."
                    return
                }
            }
            do {
                try await planStore.deletePlanAction(item.id)
                // Safe by ordering: a linked action was deleted from the DB
                // above, so this refetch cannot re-import it.
                await actionStore.fetch(projectId: project.id)
            } catch {
                // The plan row survived; an already-deleted linked action is
                // gone for good — the row returns as an unlinked plan item.
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
                // Domain pill (score-band colored) first, then the state tag
                // that keeps Prio/Väntar legible away from the section
                // header. ATT GÖRA and KLART rows carry no state tag.
                // The phase is data-only, never shown.
                if stateTag(item) != nil || domainLabel(item) != nil {
                    HStack(spacing: 6) {
                        if let domain = domainLabel(item) {
                            if let band = domainBandColor(item) {
                                Text(domain)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(band)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(band.opacity(0.15))
                                    .clipShape(Capsule())
                            } else {
                                // No score for the domain: plain, no pill.
                                Text(domain)
                                    .font(.caption)
                                    .foregroundStyle(Color.apTextTertiary)
                            }
                        }
                        if let tag = stateTag(item) {
                            Text(tag.word)
                                .font(.caption)
                                .foregroundStyle(tag.color)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(done ? 0.6 : 1)
    }

    /// Mirrors rowContent's template, reading title/domain/state from the
    /// action itself instead of a plan item.
    private func actionRowContent(_ action: ProjectAction) -> some View {
        let done = action.isDone

        return HStack(alignment: .top, spacing: 12) {
            actionStatusCircle(action)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                    .font(.subheadline)
                    .strikethrough(done)
                    .foregroundStyle(done ? Color.apTextTertiary : Color.apTextPrimary)
                    .multilineTextAlignment(.leading)
                if let domain = Domain(caseInsensitive: action.domain) {
                    HStack(spacing: 6) {
                        if let score = domainScores.first(where: { $0.domain == domain })?.score {
                            Text(domain.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.apScore(score))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.apScore(score).opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            // No score for the domain: plain, no pill.
                            Text(domain.rawValue)
                                .font(.caption)
                                .foregroundStyle(Color.apTextTertiary)
                        }
                        if let tag = actionStateTag(action) {
                            Text(tag.word)
                                .font(.caption)
                                .foregroundStyle(tag.color)
                        }
                    }
                } else if let tag = actionStateTag(action) {
                    Text(tag.word)
                        .font(.caption)
                        .foregroundStyle(tag.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(done ? 0.6 : 1)
    }

    /// Toggles the action's own open<->done — never creates a linked action.
    private func actionStatusCircle(_ action: ProjectAction) -> some View {
        Button {
            Task { await actionStore.toggle(action) }
        } label: {
            Group {
                if action.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.apStrong)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.apTextTertiary)
                }
            }
            .font(.title3)
            .contentTransition(.symbolEffect(.replace))
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: action.isDone)
        }
        .buttonStyle(.plain)
        .haptic(.light)
        .minTapTarget()
    }

    private func actionStateTag(_ action: ProjectAction) -> (word: String, color: Color)? {
        switch action.taskState {
        case .prio:    return ("Prio", Color.apOrange)
        case .waiting: return ("Väntar", Color.apWaiting)
        default:       return nil
        }
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
        // Case-insensitive, displayed in the enum's canonical casing.
        guard let raw = item.domain, let domain = Domain(caseInsensitive: raw) else { return nil }
        return domain.rawValue
    }

    /// Score-band color for the item's domain via the shared helper;
    /// nil (unknown domain or no score) falls back to plain text.
    private func domainBandColor(_ item: PlanItem) -> Color? {
        guard let raw = item.domain,
              let domain = Domain(caseInsensitive: raw),
              let score = domainScores.first(where: { $0.domain == domain })?.score
        else { return nil }
        return Color.apScore(score)
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
        if let raw = item.domain, let resolved = Domain(caseInsensitive: raw) {
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
        latestAssessment = byNewest.first

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
            // an assessment is completed (ResultView), never from here. The
            // task list still shows any unlinked actions, so scores come
            // from the plan-less fallback.
            sourceAssessment = nil
            items = []
            await loadFallbackScores()
        }

        isLoading = false
    }

    /// Plan-less path: domainScores from the team's latest COMPLETED
    /// assessment via the shared loader, filtered to this project. No
    /// completed assessment → [] (urgency Int.max, plain pills — degrades,
    /// never crashes).
    private func loadFallbackScores() async {
        do {
            let data = try await AssessmentScoresLoader.load(questionStore: questionStore)
            domainScores = data.completedByProject[project.id]?.first
                .map(data.scores(for:)) ?? []
        } catch {
            domainScores = []
            print("PlanView: loadFallbackScores error: \(error)")
        }
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

/// FAB press, the APRowPressStyle pattern: reads isPressed only — no
/// stacked gesture can swallow the press state. One shadow carries both
/// the resting elevation glow and the press glow, so the two states are
/// a single animated transition.
private struct APFabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .shadow(
                color: Color.apOrange.opacity(configuration.isPressed ? 0.55 : 0.25),
                radius: configuration.isPressed ? 16 : 10,
                y: 4
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Add Task Sheet

/// Manual task creation: domain chips with the weakest domain preselected,
/// plus a trim-validated free-text title.
private struct AddTaskSheet: View {
    let defaultDomain: Domain
    let onSave: (Domain, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selected: Domain

    init(defaultDomain: Domain, onSave: @escaping (Domain, String) -> Void) {
        self.defaultDomain = defaultDomain
        self.onSave = onSave
        _selected = State(initialValue: defaultDomain)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "DOMÄN")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(Domain.allCases, id: \.self) { domain in
                                domainChip(domain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "ÅTGÄRD")
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(selected, trimmed)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Ny uppgift")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }

    private func domainChip(_ domain: Domain) -> some View {
        Button {
            selected = domain
        } label: {
            Text(domain.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected == domain ? .white : Color.apTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(selected == domain ? Color.apOrange : Color.apSurface)
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected == domain ? Color.clear : Color.apHairline,
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
        .haptic(.light)
    }
}
