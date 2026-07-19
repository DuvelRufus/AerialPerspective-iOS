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
    @State private var editingNote: Note? = nil

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
        // Mekanism d på den stabila containern (AssessmentListView-prejudikatet):
        // pencil-knappen sätter bindingen; SwiftUI nollar den vid pop.
        .navigationDestination(item: $editingNote) { note in
            NoteFormView(
                heading: "Redigera anteckning",
                title: note.title,
                body: note.body,
                tags: note.tags
            ) { newTitle, newBody, newTags in
                var updated = note
                updated.title = newTitle
                updated.body = newBody
                updated.tags = newTags
                Task { await notesStore.update(updated) }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteSheet { title, body, tags in
                Task {
                    do {
                        try await notesStore.add(projectId: project.id, title: title, body: body, tags: tags)
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

    /// Passiv i detta steg — blir filterknapp när sökfältet landar.
    private func tagChip(_ tag: String) -> some View {
        Text(tag)
            .font(.caption2)
            .foregroundStyle(.apTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.apSurfaceElevated)
            .clipShape(Capsule())
    }

    private func noteRow(_ note: Note) -> some View {
        let isExpanded = expandedIds.contains(note.id)
        // Top-alignad så pencil-ikonen ligger still när raden expanderar.
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
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
                if !note.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(note.tags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Egen Button → hit-precedens över radens tap; triggar aldrig
            // inline-expanderingen.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                editingNote = note
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.apTextSecondary)
            }
            .buttonStyle(.plain)
            .minTapTarget()
        }
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
    @State private var editingContact: Contact? = nil

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
        // Mekanism d på den stabila containern (AssessmentListView-prejudikatet):
        // pencil-knappen sätter bindingen; SwiftUI nollar den vid pop.
        .navigationDestination(item: $editingContact) { contact in
            ContactFormView(heading: "Redigera kontakt", contact: contact) { name, role, phone, email, avatarColor in
                var updated = contact
                updated.name = name
                updated.role = role
                updated.phone = phone
                updated.email = email
                updated.avatarColor = avatarColor
                Task { await contactsStore.update(updated) }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet { name, role, phone, email, avatarColor in
                Task {
                    do {
                        try await contactsStore.add(projectId: project.id, name: name, role: role, phone: phone, email: email, avatarColor: avatarColor)
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
                // Egen Button → hit-precedens över radytan, som CTA:erna.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    editingContact = contact
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.apTextSecondary)
                }
                .buttonStyle(.plain)
                .minTapTarget()
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
    let onSave: (String, String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var noteBody: String
    @State private var tags: [String]
    @State private var tagInput = ""

    init(
        heading: String,
        title: String = "",
        body: String = "",
        tags: [String] = [],
        onSave: @escaping (String, String, [String]) -> Void
    ) {
        self.heading = heading
        self.onSave = onSave
        _title = State(initialValue: title)
        _noteBody = State(initialValue: body)
        _tags = State(initialValue: tags)
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

                VStack(alignment: .leading, spacing: 8) {
                    APSectionHeader(title: "TAGGAR (VALFRITT)")
                    HStack(spacing: 8) {
                        TextField("Lägg till tagg...", text: $tagInput)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { addTag() }
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            addTag()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.apOrange)
                        }
                        .buttonStyle(.plain)
                        .minTapTarget()
                    }
                    if !tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                // Hela chipen tar bort taggen; x:et är affordansen.
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.easeInOut) {
                                        tags.removeAll { $0 == tag }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(tag)
                                            .font(.caption2)
                                            .foregroundStyle(.apTextPrimary)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.apTextTertiary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.apSurfaceElevated)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                APPillButton(title: "Spara", action: {
                    let t = title.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    onSave(t, noteBody, tags)
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

    /// Trimmar, ignorerar tomt, dedupar case-insensitive.
    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else {
            tagInput = ""
            return
        }
        withAnimation(.easeInOut) { tags.append(trimmed) }
        tagInput = ""
    }
}

// MARK: - Flow layout

/// Minimal wrap-layout för tagg-chips (formulär + rader): radbryt när nästa
/// chip inte ryms, radhöjd = högsta chip i raden.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Add Note Sheet

/// Skapa-läget: quick-capture-sheet med egen NavigationStack. Redigera-läget
/// pushar NoteFormView direkt i projektstacken i stället.
private struct AddNoteSheet: View {
    let onSave: (String, String, [String]) -> Void

    var body: some View {
        NavigationStack {
            NoteFormView(heading: "Ny anteckning", onSave: onSave)
        }
    }
}
