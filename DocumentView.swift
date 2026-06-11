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

private struct ProjectDocument: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var content: String
    var type: String
    var updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, content, type
        case projectId = "project_id"
        case updatedAt = "updated_at"
    }
}

private struct NewNote: Encodable {
    let project_id: UUID
    let content: String
    let type: String
}

private struct UpdateNote: Encodable {
    let content: String
}

private struct NewDecision: Encodable {
    let project_id: UUID
    let title: String
    let description: String?
    let decided_at: String
}

private struct NewLink: Encodable {
    let project_id: UUID
    let title: String
    let url: String
    let category: String
}

private struct NewContact: Encodable {
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

    var title: String {
        switch self {
        case .decision(let d): return "Radera \"\(d.title)\"?"
        case .link(let l):     return "Radera \"\(l.title)\"?"
        case .contact(let c):  return "Radera \"\(c.name)\"?"
        }
    }
}

// MARK: - DocumentView

struct DocumentView: View {
    var project: Project

    // Notes
    @State private var noteContent = ""
    @State private var noteDocumentId: UUID? = nil
    @State private var noteSaveTask: Task<Void, Never>? = nil
    @State private var isSavingNote = false
    @State private var noteLastSaved: Date? = nil
    @State private var noteLoaded = false

    // Data
    @State private var decisions: [Decision] = []
    @State private var links: [ProjectLink] = []
    @State private var contacts: [Contact] = []

    // Sheets
    @State private var showAddDecision = false
    @State private var showAddLink = false
    @State private var showAddContact = false

    // Expand state
    @State private var notesExpanded = false
    @State private var decisionsExpanded = false
    @State private var linksExpanded = false
    @State private var contactsExpanded = false

    // Search & delete
    @State private var searchText = ""
    @State private var pendingDelete: DeleteIntent? = nil

    // MARK: Filtered

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

    // MARK: Body

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                searchBar
                ScrollView {
                    VStack(spacing: 12) {
                        notesSection
                        decisionsSection
                        linksSection
                        contactsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Dokument")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await fetchAll() }
        .onChange(of: noteContent) { _, _ in
            guard noteLoaded else { return }
            scheduleNoteSave()
        }
        .onDisappear { noteSaveTask?.cancel() }
        .sheet(isPresented: $showAddDecision) {
            AddDecisionSheet { title, desc, date in
                Task { await addDecision(title: title, description: desc, date: date) }
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

                if notesExpanded {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.vertical, 10)

                    ZStack(alignment: .topLeading) {
                        if noteContent.isEmpty {
                            Text("Skriv projektdokumentation, beslut, arkitektur...")
                                .font(.body)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $noteContent)
                            .font(.body)
                            .foregroundStyle(.apTextPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(height: 220)
                    }

                    HStack {
                        Spacer()
                        if isSavingNote {
                            Text("Sparar...")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                        } else if let saved = noteLastSaved {
                            Text("Sparat \(saved.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Decisions section

    private var decisionsSection: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "BESLUT",
                    count: filteredDecisions.isEmpty ? nil : filteredDecisions.count,
                    isExpanded: decisionsExpanded,
                    onAdd: { showAddDecision = true }
                ) { decisionsExpanded.toggle() }

                if decisionsExpanded {
                    if filteredDecisions.isEmpty {
                        Text(searchText.isEmpty ? "Inga beslut ännu" : "Inga träffar")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredDecisions) { decision in
                                decisionRow(decision)
                                if decision.id != filteredDecisions.last?.id {
                                    Divider().background(Color.white.opacity(0.05))
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
            Button { pendingDelete = .decision(decision) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.apRisk.opacity(0.6))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .minTapTarget()
        }
        .padding(.vertical, 8)
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
                                    Divider().background(Color.white.opacity(0.05))
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
            Button { pendingDelete = .link(link) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.apRisk.opacity(0.6))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .minTapTarget()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: link.url) {
                UIApplication.shared.open(url)
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
                                    Divider().background(Color.white.opacity(0.05))
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
            Button { pendingDelete = .contact(contact) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.apRisk.opacity(0.6))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .minTapTarget()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Fetch

    private func fetchAll() async {
        await fetchNote()
        await fetchDecisions()
        await fetchLinks()
        await fetchContacts()
    }

    private func fetchNote() async {
        do {
            let docs: [ProjectDocument] = try await supabase
                .from("documents")
                .select()
                .eq("project_id", value: project.id)
                .eq("type", value: "note")
                .limit(1)
                .execute()
                .value
            if let doc = docs.first {
                noteContent = doc.content
                noteDocumentId = doc.id
            }
        } catch {
            print("DocumentView: fetchNote error: \(error)")
        }
        noteLoaded = true
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

    // MARK: - Note save

    private func scheduleNoteSave() {
        noteSaveTask?.cancel()
        noteSaveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await saveNote()
        }
    }

    private func saveNote() async {
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            if let existingId = noteDocumentId {
                try await supabase
                    .from("documents")
                    .update(UpdateNote(content: noteContent))
                    .eq("id", value: existingId)
                    .execute()
            } else {
                let inserted: ProjectDocument = try await supabase
                    .from("documents")
                    .insert(NewNote(project_id: project.id, content: noteContent, type: "note"))
                    .select()
                    .single()
                    .execute()
                    .value
                noteDocumentId = inserted.id
            }
            noteLastSaved = Date()
        } catch {
            print("DocumentView: saveNote error: \(error)")
        }
    }

    // MARK: - Add

    private func addDecision(title: String, description: String?, date: Date) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        do {
            let inserted: Decision = try await supabase
                .from("decisions")
                .insert(NewDecision(
                    project_id: project.id,
                    title: title,
                    description: description,
                    decided_at: formatter.string(from: date)
                ))
                .select()
                .single()
                .execute()
                .value
            decisions.insert(inserted, at: 0)
        } catch {
            print("DocumentView: addDecision error: \(error)")
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
            }
        } catch {
            print("DocumentView: delete error: \(error)")
        }
    }
}

// MARK: - Add Decision Sheet

private struct AddDecisionSheet: View {
    let onSave: (String, String?, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var decidedAt = Date()

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
                        APSectionHeader(title: "BESKRIVNING (VALFRITT)")
                        TextField("", text: $description)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "DATUM")
                        DatePicker("", selection: $decidedAt, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, description.isEmpty ? nil : description, decidedAt)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Nytt beslut")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Add Link Sheet

private enum LinkCategory: String, CaseIterable {
    case jira = "Jira"
    case figma = "Figma"
    case github = "GitHub"
    case confluence = "Confluence"
    case annat = "Annat"
}

private struct AddLinkSheet: View {
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

private struct AddContactSheet: View {
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
