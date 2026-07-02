//
//  DocumentView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-27.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

// MARK: - Public models

struct Decision: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var title: String
    var description: String?
    var decidedAt: String
    var createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, title, description
        case projectId = "project_id"
        case decidedAt = "decided_at"
        case createdAt = "created_at"
    }
}

struct ProjectLink: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var title: String
    var url: String
    var category: String
    var createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, title, url, category
        case projectId = "project_id"
        case createdAt = "created_at"
    }
}

struct Contact: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var name: String
    var role: String?
    var contactInfo: String?
    var createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, name, role
        case projectId = "project_id"
        case contactInfo = "contact_info"
        case createdAt = "created_at"
    }
}

// MARK: - Private DB models

struct NewLink: Encodable {
    let project_id: UUID
    let title: String
    let url: String
    let category: String
}

struct NewContact: Encodable {
    let project_id: UUID
    let name: String
    let role: String?
    let contact_info: String?
}

// MARK: - Delete intent

private enum DeleteIntent {
    case decision(Decision)
    case link(ProjectLink)
    case contact(Contact)
    case action(ProjectAction)
    case note

    var title: String {
        switch self {
        case .decision(let d): return "Radera \"\(d.title)\"?"
        case .link(let l):     return "Radera \"\(l.title)\"?"
        case .contact(let c):  return "Radera \"\(c.name)\"?"
        case .action(let a):   return "Radera \"\(a.title)\"?"
        case .note:            return "Rensa anteckningen?"
        }
    }
}

// MARK: - Add action target

private struct AddActionTarget: Identifiable {
    let domain: Domain
    let score: Int?
    var id: String { domain.rawValue }
}

// MARK: - DocumentView

struct DocumentView: View {
    var project: Project
    var questionStore: QuestionStore
    var actionStore: ActionStore
    @Bindable var noteStore: NoteStore

    // Assessment context
    @State private var latestAssessment: Assessment? = nil
    @State private var domainScores: [Domain: DomainScore] = [:]

    // Actions
    @State private var addActionTarget: AddActionTarget? = nil

    // Data
    @State private var decisions: [Decision] = []
    @State private var links: [ProjectLink] = []
    @State private var contacts: [Contact] = []

    // Sheets
    @State private var showAddLink = false
    @State private var showAddContact = false

    // Expand state
    @State private var notesExpanded = false
    @State private var decisionsExpanded = false
    @State private var linksExpanded = false
    @State private var contactsExpanded = false

    // View state
    @State private var isLoading = true

    // Search & delete
    @State private var searchText = ""
    @State private var pendingDelete: DeleteIntent? = nil

    // MARK: Filtered

    private func actionsFor(_ domain: Domain) -> [ProjectAction] {
        actionStore.actions.filter {
            $0.domain == domain.rawValue &&
            (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var filteredDecisions: [Decision] {
        guard !searchText.isEmpty else { return decisions }
        return decisions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredLinks: [ProjectLink] {
        guard !searchText.isEmpty else { return links }
        return links.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.url.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredContacts: [Contact] {
        guard !searchText.isEmpty else { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.role?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // MARK: Domain ordering

    private var sortedDomains: [Domain] {
        Domain.allCases.sorted { sortKey($0) < sortKey($1) }
    }

    private func sortKey(_ domain: Domain) -> (Int, Int) {
        guard let ds = domainScores[domain] else { return (3, 0) }
        switch ds.level {
        case .risk:   return (0, ds.score)
        case .note:   return (1, ds.score)
        case .strong: return (2, ds.score)
        }
    }

    private func hasActions(_ domain: Domain) -> Bool {
        actionStore.actions.contains { $0.domain == domain.rawValue }
    }

    private func isCompact(_ domain: Domain) -> Bool {
        domainScores[domain]?.level == .strong && !hasActions(domain)
    }

    private var fullCardDomains: [Domain] {
        sortedDomains.filter { !isCompact($0) }
    }

    private var compactDomains: [Domain] {
        sortedDomains.filter { isCompact($0) }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            if isLoading {
                ProgressView()
                    .tint(.apOrange)
            } else if actionStore.error != nil {
                APErrorState {
                    Task {
                        actionStore.error = nil
                        await actionStore.fetch(projectId: project.id)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    searchBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if latestAssessment == nil {
                                noAssessmentState
                            } else {
                                ForEach(fullCardDomains, id: \.self) { domain in
                                    domainCard(domain)
                                }
                                if !compactDomains.isEmpty {
                                    APSectionHeader(title: "STARKA DOMÄNER")
                                        .padding(.top, 12)
                                    ForEach(compactDomains, id: \.self) { domain in
                                        compactDomainRow(domain)
                                    }
                                }
                            }

                            APSectionHeader(title: "ÖVRIGT")
                                .padding(.top, 12)
                            notesSection
                            if !decisions.isEmpty {
                                decisionsSection
                            }
                            linksSection
                            contactsSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        actionStore.error = nil
                        await actionStore.fetch(projectId: project.id)
                        await fetchAll()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await fetchAll() }
        .onChange(of: noteStore.content) { _, _ in
            guard noteStore.isLoaded else { return }
            noteStore.scheduleSave()
        }
        .sheet(item: $addActionTarget) { target in
            AddActionSheet(domainName: target.domain.rawValue) { title in
                Task { await addAction(domain: target.domain, score: target.score, title: title) }
            }
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkSheet { title, url, category in
                Task { await addLink(title: title, url: url, category: category) }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet { name, role, info in
                Task { await addContact(name: name, role: role, contactInfo: info) }
            }
        }
        .confirmationDialog(
            pendingDelete?.title ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                guard let intent = pendingDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDelete = nil
                Task { await performDelete(intent) }
            }
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Åtgärden kan inte ångras.")
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.apTextTertiary)
                .font(.subheadline)
            TextField("Sök...", text: $searchText)
                .foregroundStyle(.apTextPrimary)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.apSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - No assessment state

    private var noAssessmentState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(.apOrange)
            Text("Kör en assessment först")
                .font(.subheadline)
                .foregroundStyle(.apTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Domain cards

    private func domainCard(_ domain: Domain) -> some View {
        let ds = domainScores[domain]
        let domainActions = actionsFor(domain)
        let isWeak = ds.map { $0.level != .strong } ?? false

        return HStack(spacing: 0) {
            Rectangle()
                .fill(levelColor(ds?.level))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(domain.rawValue.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.apTextSecondary)
                    Spacer()
                    Text(ds.map { "\($0.score)" } ?? "–")
                        .font(.title2.bold())
                        .foregroundStyle(.apTextPrimary)
                    if let ds {
                        levelPill(ds.level)
                    }
                }

                if isWeak || !domainActions.isEmpty {
                    if !domainActions.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(domainActions) { action in
                                actionRow(action)
                            }
                        }
                    }

                    if isWeak {
                        Button {
                            addActionTarget = AddActionTarget(domain: domain, score: ds?.score)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Lägg till åtgärd")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.apOrange)
                        }
                        .buttonStyle(.plain)
                        .haptic(.medium)
                        .minTapTarget()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func compactDomainRow(_ domain: Domain) -> some View {
        let ds = domainScores[domain]
        return HStack(spacing: 0) {
            Rectangle()
                .fill(levelColor(ds?.level))
                .frame(width: 4)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(domain.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apTextSecondary)
                Spacer()
                Text(ds.map { "\($0.score)" } ?? "–")
                    .font(.title2.bold())
                    .foregroundStyle(.apTextPrimary)
                if let ds {
                    levelPill(ds.level)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(Color.apSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.apHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func actionRow(_ action: ProjectAction) -> some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await actionStore.toggle(action) }
            } label: {
                Image(systemName: action.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(action.isDone ? Color.apStrong : Color.apTextTertiary)
            }
            .buttonStyle(.plain)
            .minTapTarget()

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.subheadline)
                    .strikethrough(action.isDone)
                    .foregroundStyle(action.isDone ? Color.apTextTertiary : Color.apTextPrimary)
                if let score = action.createdFromScore {
                    Text("Skapad vid \(score) poäng")
                        .font(.caption)
                        .foregroundStyle(.apTextTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .action(action)
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
    }

    private func levelColor(_ level: ScoreLevel?) -> Color {
        switch level {
        case .risk:   return .apRisk
        case .note:   return .apNote
        case .strong: return .apStrong
        case nil:     return .apTextTertiary
        }
    }

    private func levelPill(_ level: ScoreLevel) -> some View {
        Text(levelLabel(level))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(levelColor(level))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(levelColor(level).opacity(0.15))
            .clipShape(Capsule())
    }

    private func levelLabel(_ level: ScoreLevel) -> String {
        switch level {
        case .risk:   return "risk"
        case .note:   return "bevaka"
        case .strong: return "starkt"
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(
        title: String,
        count: Int?,
        isExpanded: Bool,
        onAdd: (() -> Void)?,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onToggle()
            }
        } label: {
            HStack(spacing: 8) {
                APSectionHeader(title: title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.apOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.apOrangeTint)
                        .clipShape(Capsule())
                }
                Spacer()
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .foregroundStyle(.apOrange)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .haptic(.medium)
                    .minTapTarget()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.apTextTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .haptic(.light)
        .minTapTarget()
    }

    // MARK: - Notes section

    private var notesSection: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "ANTECKNINGAR",
                    count: nil,
                    isExpanded: notesExpanded,
                    onAdd: nil
                ) { notesExpanded.toggle() }
                .contextMenu {
                    Button(role: .destructive) {
                        pendingDelete = .note
                    } label: {
                        Label("Rensa anteckning", systemImage: "trash")
                    }
                }

                if notesExpanded {
                    Divider()
                        .background(Color.apHairline)
                        .padding(.vertical, 10)

                    ZStack(alignment: .topLeading) {
                        if noteStore.content.isEmpty {
                            Text("Skriv projektdokumentation, beslut, arkitektur...")
                                .font(.body)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $noteStore.content)
                            .font(.body)
                            .foregroundStyle(.apTextPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(height: 220)
                    }

                    HStack {
                        Spacer()
                        switch noteStore.status {
                        case .idle:
                            EmptyView()
                        case .saving:
                            Text("Sparar...")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                        case .saved(let date):
                            Text("Sparat \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                        case .failed:
                            Text("Kunde inte spara – ändringar osparade")
                                .font(.caption)
                                .foregroundStyle(.apRisk)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Decisions section (legacy, read-only)

    private var decisionsSection: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "BESLUT",
                    count: filteredDecisions.isEmpty ? nil : filteredDecisions.count,
                    isExpanded: decisionsExpanded,
                    onAdd: nil
                ) { decisionsExpanded.toggle() }

                if decisionsExpanded {
                    if filteredDecisions.isEmpty {
                        Text("Inga träffar")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredDecisions) { decision in
                                decisionRow(decision)
                                if decision.id != filteredDecisions.last?.id {
                                    Divider().background(Color.apHairline)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private func decisionRow(_ decision: Decision) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(decision.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.apTextPrimary)
                Text(decision.decidedAt)
                    .font(.caption)
                    .foregroundStyle(.apTextSecondary)
                if let desc = decision.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.apTextSecondary)
                        .padding(.top, 1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .decision(decision)
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
    }

    // MARK: - Links section

    private var linksSection: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "LÄNKAR",
                    count: filteredLinks.isEmpty ? nil : filteredLinks.count,
                    isExpanded: linksExpanded,
                    onAdd: { showAddLink = true }
                ) { linksExpanded.toggle() }

                if linksExpanded {
                    if filteredLinks.isEmpty {
                        Text(searchText.isEmpty ? "Inga länkar ännu" : "Inga träffar")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredLinks) { link in
                                linkRow(link)
                                if link.id != filteredLinks.last?.id {
                                    Divider().background(Color.apHairline)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private func linkRow(_ link: ProjectLink) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.apOrange)
                Text(link.url)
                    .font(.caption)
                    .foregroundStyle(.apTextTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(link.category)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.apOrange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.apOrangeTint)
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: link.url) {
                UIApplication.shared.open(url)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .link(link)
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
    }

    // MARK: - Contacts section

    private var contactsSection: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "KONTAKTER",
                    count: filteredContacts.isEmpty ? nil : filteredContacts.count,
                    isExpanded: contactsExpanded,
                    onAdd: { showAddContact = true }
                ) { contactsExpanded.toggle() }

                if contactsExpanded {
                    if filteredContacts.isEmpty {
                        Text(searchText.isEmpty ? "Inga kontakter ännu" : "Inga träffar")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredContacts) { contact in
                                contactRow(contact)
                                if contact.id != filteredContacts.last?.id {
                                    Divider().background(Color.apHairline)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.apTextPrimary)
                if let role = contact.role, !role.isEmpty {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.apTextSecondary)
                }
                if let info = contact.contactInfo, !info.isEmpty {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.apTextTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = .contact(contact)
            } label: {
                Label("Radera", systemImage: "trash")
            }
        }
    }

    // MARK: - Fetch

    private func fetchAll() async {
        // Actions are fetched once at ProjectTabView and shared; this loads
        // only DocumentView's own per-view data.
        await loadAssessmentContext()
        if !noteStore.isLoaded {
            await noteStore.fetch(projectId: project.id)
        }
        await fetchDecisions()
        await fetchLinks()
        await fetchContacts()
        isLoading = false
    }

    private func loadAssessmentContext() async {
        let assessmentStore = AssessmentStore()
        await assessmentStore.fetch(projectId: project.id)
        if questionStore.questions.isEmpty {
            await questionStore.fetch()
        }
        let questions = questionStore.questions
        let options = questionStore.options

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
            latestAssessment = assessment
            domainScores = byDomain
            return
        }
        latestAssessment = nil
        domainScores = [:]
    }

    private func fetchDecisions() async {
        do {
            decisions = try await supabase
                .from("decisions")
                .select()
                .eq("project_id", value: project.id)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            print("DocumentView: fetchDecisions error: \(error)")
        }
    }

    private func fetchLinks() async {
        do {
            links = try await supabase
                .from("links")
                .select()
                .eq("project_id", value: project.id)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            print("DocumentView: fetchLinks error: \(error)")
        }
    }

    private func fetchContacts() async {
        do {
            contacts = try await supabase
                .from("contacts")
                .select()
                .eq("project_id", value: project.id)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            print("DocumentView: fetchContacts error: \(error)")
        }
    }

    // MARK: - Add

    private func addAction(domain: Domain, score: Int?, title: String) async {
        do {
            try await actionStore.add(
                projectId: project.id,
                domain: domain.rawValue,
                title: title,
                assessmentId: latestAssessment?.id,
                createdFromScore: score
            )
        } catch {
            print("DocumentView: addAction error: \(error)")
        }
    }

    private func addLink(title: String, url: String, category: String) async {
        do {
            let inserted: ProjectLink = try await supabase
                .from("links")
                .insert(NewLink(project_id: project.id, title: title, url: url, category: category))
                .select()
                .single()
                .execute()
                .value
            links.insert(inserted, at: 0)
        } catch {
            print("DocumentView: addLink error: \(error)")
        }
    }

    private func addContact(name: String, role: String?, contactInfo: String?) async {
        do {
            let inserted: Contact = try await supabase
                .from("contacts")
                .insert(NewContact(project_id: project.id, name: name, role: role, contact_info: contactInfo))
                .select()
                .single()
                .execute()
                .value
            contacts.insert(inserted, at: 0)
        } catch {
            print("DocumentView: addContact error: \(error)")
        }
    }

    // MARK: - Delete

    private func performDelete(_ intent: DeleteIntent) async {
        do {
            switch intent {
            case .decision(let d):
                try await supabase.from("decisions").delete().eq("id", value: d.id).execute()
                decisions.removeAll { $0.id == d.id }
            case .link(let l):
                try await supabase.from("links").delete().eq("id", value: l.id).execute()
                links.removeAll { $0.id == l.id }
            case .contact(let c):
                try await supabase.from("contacts").delete().eq("id", value: c.id).execute()
                contacts.removeAll { $0.id == c.id }
            case .action(let a):
                try await actionStore.delete(a)
            case .note:
                await noteStore.clear()
            }
        } catch {
            print("DocumentView: delete error: \(error)")
        }
    }
}

// MARK: - Add Action Sheet

private struct AddActionSheet: View {
    let domainName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "ÅTGÄRD – \(domainName.uppercased())")
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
                        onSave(trimmed)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Ny åtgärd")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add Link Sheet

enum LinkCategory: String, CaseIterable {
    case jira = "Jira"
    case figma = "Figma"
    case github = "GitHub"
    case confluence = "Confluence"
    case annat = "Annat"
}

struct AddLinkSheet: View {
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var category: LinkCategory = .annat

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "TITEL")
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "URL")
                        TextField("https://", text: $url)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "KATEGORI")
                        Picker("Kategori", selection: $category) {
                            ForEach(LinkCategory.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        let u = url.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, !u.isEmpty else { return }
                        onSave(t, u, category.rawValue)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Ny länk")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Add Contact Sheet

struct AddContactSheet: View {
    let onSave: (String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var contactInfo = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "NAMN")
                        TextField("", text: $name)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "ROLL (VALFRITT)")
                        TextField("", text: $role)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "KONTAKTINFO (VALFRITT)")
                        TextField("E-post, telefon...", text: $contactInfo)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let isDisabled = name.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, role.isEmpty ? nil : role, contactInfo.isEmpty ? nil : contactInfo)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Ny kontakt")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
