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

// Trimmad kopia av DocumentViews DeleteIntent (endast Övrigt-fallen).
// Avsiktlig, tillfällig duplicering tills DocumentView rensas i nästa steg.
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

    // Ingen sökrad här ännu — filtren behålls oförändrade från DocumentView
    // med en alltid-tom söksträng så en framtida sökrad kan kopplas in direkt.
    @State private var searchText = ""
    @State private var pendingDelete: DeleteIntent? = nil

    // MARK: Filtered

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
