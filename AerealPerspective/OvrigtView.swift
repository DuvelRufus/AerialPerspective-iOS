//
//  OvrigtView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-02.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

// MARK: - Models

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

// MARK: - Insert payloads

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
    case link(ProjectLink)
    case contact(Contact)
    case note

    var title: String {
        switch self {
        case .link(let l):    return "Radera \"\(l.title)\"?"
        case .contact(let c): return "Radera \"\(c.name)\"?"
        case .note:           return "Rensa anteckningen?"
        }
    }
}

struct OvrigtView: View {
    var project: Project
    @Bindable var noteStore: NoteStore

    // Data
    @State private var links: [ProjectLink] = []
    @State private var contacts: [Contact] = []

    // Sheets
    @State private var showAddLink = false
    @State private var showAddContact = false

    // Expand state
    @State private var notesExpanded = false
    @State private var linksExpanded = false
    @State private var contactsExpanded = false

    @State private var pendingDelete: DeleteIntent? = nil

    // MARK: Body

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    APSectionHeader(title: "ÖVRIGT")
                        .padding(.top, 12)
                    notesSection
                    linksSection
                    contactsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await fetchLinks()
                await fetchContacts()
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if !noteStore.isLoaded {
                await noteStore.fetch(projectId: project.id)
            }
            await fetchLinks()
            await fetchContacts()
        }
        .onChange(of: noteStore.content) { _, _ in
            guard noteStore.isLoaded else { return }
            noteStore.scheduleSave()
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

    // MARK: - Glass card chrome

    /// APCard plus a thin top-edge light line, shared by all three sections
    /// so they stay on the exact same glass idiom.
    private func glassSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // APCard's stored closure is @escaping; capture the built view, not
        // the non-escaping parameter.
        let built = content()
        return APCard { built }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.clear, Color.apOrange.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, 20) // inset so the line sits inside the corner radius
                .allowsHitTesting(false)
            }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(
        title: String,
        icon: String,
        subtitle: String? = nil,
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
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.apOrange.opacity(0.14))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.apOrange)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    APSectionHeader(title: title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                    }
                }
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.apTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
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

    /// "senast ändrad HH:MM" — only when a save has happened this session;
    /// NoteStore doesn't expose the persisted updated_at, so no value = no text.
    private var noteSubtitle: String? {
        if case .saved(let date) = noteStore.status {
            return "senast ändrad \(date.formatted(date: .omitted, time: .shortened))"
        }
        return nil
    }

    private var notesSection: some View {
        glassSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "ANTECKNINGAR",
                    icon: "note.text",
                    subtitle: noteSubtitle,
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

    // MARK: - Links section

    private var linksSection: some View {
        glassSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "LÄNKAR",
                    icon: "link",
                    count: links.isEmpty ? nil : links.count,
                    isExpanded: linksExpanded,
                    onAdd: { showAddLink = true }
                ) { linksExpanded.toggle() }

                if linksExpanded {
                    if links.isEmpty {
                        Text("Inga länkar ännu")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(links) { link in
                                linkRow(link)
                                if link.id != links.last?.id {
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
        glassSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "KONTAKTER",
                    icon: "person.2.fill",
                    count: contacts.isEmpty ? nil : contacts.count,
                    isExpanded: contactsExpanded,
                    onAdd: { showAddContact = true }
                ) { contactsExpanded.toggle() }

                if contactsExpanded {
                    if contacts.isEmpty {
                        Text("Inga kontakter ännu")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(contacts) { contact in
                                contactRow(contact)
                                if contact.id != contacts.last?.id {
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
            print("OvrigtView: fetchLinks error: \(error)")
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
            print("OvrigtView: fetchContacts error: \(error)")
        }
    }

    // MARK: - Add

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
            print("OvrigtView: addLink error: \(error)")
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
            print("OvrigtView: addContact error: \(error)")
        }
    }

    // MARK: - Delete

    private func performDelete(_ intent: DeleteIntent) async {
        do {
            switch intent {
            case .link(let l):
                try await supabase.from("links").delete().eq("id", value: l.id).execute()
                links.removeAll { $0.id == l.id }
            case .contact(let c):
                try await supabase.from("contacts").delete().eq("id", value: c.id).execute()
                contacts.removeAll { $0.id == c.id }
            case .note:
                await noteStore.clear()
            }
        } catch {
            print("OvrigtView: delete error: \(error)")
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
