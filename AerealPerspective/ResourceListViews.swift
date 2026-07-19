//
//  ResourceListViews.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-19.
//
//  Fulla sektionsvyer för Resources (delsteg 2): alla rader + swipe-delete.
//  Pushas via ren vy-destination-NavigationLink från översiktskorten i
//  OvrigtView — statelöst, inget item-bundet som kan desynca mot back-swipe.
//

import Foundation
import UIKit
import SwiftUI

// MARK: - NotesListView

struct NotesListView: View {
    var project: Project
    var notesStore: NotesStore

    @State private var showAddNote = false
    @State private var pendingDelete: Note? = nil
    @State private var openSwipeId: UUID? = nil
    /// List-ägd så utfällt läge överlever re-renders; vid delete lämnas
    /// id:t kvar i setet — harmlöst, raden renderas aldrig igen.
    @State private var expandedIds: Set<UUID> = []

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if notesStore.notes.isEmpty {
                        ResourceEmptyState(text: "Inga anteckningar ännu")
                    } else {
                        APCard {
                            VStack(spacing: 0) {
                                ForEach(notesStore.notes) { note in
                                    noteRow(note)
                                        .apSwipeActions(id: note.id, openId: $openSwipeId, actions: [
                                            APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                                                pendingDelete = note
                                            }
                                        ])
                                    if note.id != notesStore.notes.last?.id {
                                        Divider().background(Color.apHairline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Anteckningar")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddNote = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.apOrange)
                }
                .haptic(.medium)
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteSheet { title, body in
                Task {
                    do {
                        try await notesStore.add(projectId: project.id, title: title, body: body)
                    } catch {
                        print("NotesListView: addNote error: \(error)")
                    }
                }
            }
        }
        .confirmationDialog(
            pendingDelete.map { "Radera \"\($0.title.isEmpty ? "Utan titel" : $0.title)\"?" } ?? "",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                guard let note = pendingDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDelete = nil
                Task { await notesStore.delete(note) }
            }
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Åtgärden kan inte ångras.")
        }
    }

    /// Cancel eller confirm: spring den öppna swipe-raden igen.
    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: {
                if !$0 {
                    pendingDelete = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        openSwipeId = nil
                    }
                }
            }
        )
    }

    private func noteRow(_ note: Note) -> some View {
        let isExpanded = expandedIds.contains(note.id)
        return VStack(alignment: .leading, spacing: 3) {
            Text(note.title.isEmpty ? "Utan titel" : note.title)
                .font(.subheadline.bold())
                .foregroundStyle(.apTextPrimary)
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.caption)
                    .foregroundStyle(.apTextSecondary)
                    .lineLimit(isExpanded ? nil : 2)
            }
            Text(RelativeDateTimeFormatter().localizedString(for: note.updatedAt, relativeTo: Date()))
                .font(.caption2)
                .foregroundStyle(.apTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // linkRow-prejudikatet: tap samexisterar med apSwipeActions tack
        // vare modifierns riktnings-latch.
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut) {
                if isExpanded {
                    expandedIds.remove(note.id)
                } else {
                    expandedIds.insert(note.id)
                }
            }
        }
    }
}

// MARK: - LinksListView

struct LinksListView: View {
    var project: Project
    var linksStore: LinksStore

    @State private var showAddLink = false
    @State private var pendingDelete: ProjectLink? = nil
    @State private var openSwipeId: UUID? = nil

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if linksStore.links.isEmpty {
                        ResourceEmptyState(text: "Inga länkar ännu")
                    } else {
                        APCard {
                            VStack(spacing: 0) {
                                ForEach(linksStore.links) { link in
                                    linkRow(link)
                                        .apSwipeActions(id: link.id, openId: $openSwipeId, actions: [
                                            APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                                                pendingDelete = link
                                            }
                                        ])
                                    if link.id != linksStore.links.last?.id {
                                        Divider().background(Color.apHairline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Länkar")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddLink = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.apOrange)
                }
                .haptic(.medium)
            }
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkSheet { title, url, category in
                Task {
                    do {
                        try await linksStore.add(projectId: project.id, title: title, url: url, category: category)
                    } catch {
                        print("LinksListView: addLink error: \(error)")
                    }
                }
            }
        }
        .confirmationDialog(
            pendingDelete.map { "Radera \"\($0.title)\"?" } ?? "",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                guard let link = pendingDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDelete = nil
                Task { await linksStore.delete(link) }
            }
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Åtgärden kan inte ångras.")
        }
    }

    /// Cancel eller confirm: spring den öppna swipe-raden igen.
    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: {
                if !$0 {
                    pendingDelete = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        openSwipeId = nil
                    }
                }
            }
        )
    }

    private func linkRow(_ link: ProjectLink) -> some View {
        HStack(spacing: 12) {
            LinkFavicon(link: link, size: 28)
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
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let url = LinkURLPolicy.normalized(from: link.url) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - ContactsListView

struct ContactsListView: View {
    var project: Project
    var contactsStore: ContactsStore

    @State private var showAddContact = false
    @State private var pendingDelete: Contact? = nil
    @State private var openSwipeId: UUID? = nil

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if contactsStore.contacts.isEmpty {
                        ResourceEmptyState(text: "Inga kontakter ännu")
                    } else {
                        APCard {
                            VStack(spacing: 0) {
                                ForEach(contactsStore.contacts) { contact in
                                    contactRow(contact)
                                        .apSwipeActions(id: contact.id, openId: $openSwipeId, actions: [
                                            APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                                                pendingDelete = contact
                                            }
                                        ])
                                    if contact.id != contactsStore.contacts.last?.id {
                                        Divider().background(Color.apHairline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Kontakter")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddContact = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.apOrange)
                }
                .haptic(.medium)
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet { name, role, phone, email in
                Task {
                    do {
                        // avatarColor nil tills färgväljaren byggs.
                        try await contactsStore.add(projectId: project.id, name: name, role: role, phone: phone, email: email, avatarColor: nil)
                    } catch {
                        print("ContactsListView: addContact error: \(error)")
                    }
                }
            }
        }
        .confirmationDialog(
            pendingDelete.map { "Radera \"\($0.name)\"?" } ?? "",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                guard let contact = pendingDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                pendingDelete = nil
                Task { await contactsStore.delete(contact) }
            }
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Åtgärden kan inte ångras.")
        }
    }

    /// Cancel eller confirm: spring den öppna swipe-raden igen.
    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: {
                if !$0 {
                    pendingDelete = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        openSwipeId = nil
                    }
                }
            }
        )
    }

    private func contactRow(_ contact: Contact) -> some View {
        HStack(alignment: .center, spacing: 12) {
            InitialsAvatar(name: contact.name, colorHex: contact.avatarColor, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.apTextPrimary)
                if let role = contact.role, !role.isEmpty {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.apTextSecondary)
                }
            }
            Spacer()
            // CTA-knappar bara för fält som finns — ingen dämpad/inaktiv ikon.
            HStack(spacing: 8) {
                if let phone = contact.phone, !phone.isEmpty {
                    ctaButton(icon: "phone.fill") {
                        openContactURL("tel:" + phone.filter("0123456789+#*".contains))
                    }
                }
                if let email = contact.email, !email.isEmpty {
                    ctaButton(icon: "envelope.fill") {
                        openContactURL("mailto:" + email)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// 40pt cirkel + orange glyph så den läser som knapp, inte dekor.
    /// Egen Button med hit-precedens över radens contentShape; haptik i
    /// closuren, ingen gesture-modifier.
    private func ctaButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Circle()
                .fill(Color.apSurfaceElevated)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.apOrange)
                }
        }
        .buttonStyle(.plain)
        .minTapTarget()
    }

    private func openContactURL(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Empty state

private struct ResourceEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.apTextTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}

// MARK: - Note form

/// Delat formulär för skapa (sheet, tomt) och redigera (push, förifyllt).
/// Vet inget om storen — levererar (titel, body) via onSave; callern väljer
/// add eller update. dismiss() stänger sheeten respektive poppar pushen.
private struct NoteFormView: View {
    let heading: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var noteBody: String

    init(
        heading: String,
        title: String = "",
        body: String = "",
        onSave: @escaping (String, String) -> Void
    ) {
        self.heading = heading
        self.onSave = onSave
        _title = State(initialValue: title)
        _noteBody = State(initialValue: body)
    }

    var body: some View {
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
                    APSectionHeader(title: "ANTECKNING")
                    ZStack(alignment: .topLeading) {
                        if noteBody.isEmpty {
                            Text("Skriv...")
                                .font(.body)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 16)
                                .padding(.leading, 13)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $noteBody)
                            .font(.body)
                            .foregroundStyle(.apTextPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 180)
                    }
                    .background(Color.apSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                APPillButton(title: "Spara", action: {
                    let t = title.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    onSave(t, noteBody)
                    dismiss()
                })
                .opacity(isDisabled ? 0.5 : 1)
                .disabled(isDisabled)

                APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                Spacer()
            }
            .padding()
        }
        .navigationTitle(heading)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Add Note Sheet

/// Skapa-läget: quick-capture-sheet med egen NavigationStack. Redigera-läget
/// pushar NoteFormView direkt i projektstacken i stället.
private struct AddNoteSheet: View {
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            NoteFormView(heading: "Ny anteckning", onSave: onSave)
        }
    }
}
