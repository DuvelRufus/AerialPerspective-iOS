//
//  OvrigtView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-07-02.
//

import Foundation
import UIKit
import SwiftUI
import ContactsUI

// MARK: - Delete intent

private enum DeleteIntent {
    case link(ProjectLink)
    case contact(Contact)

    var title: String {
        switch self {
        case .link(let l):    return "Radera \"\(l.title)\"?"
        case .contact(let c): return "Radera \"\(c.name)\"?"
        }
    }
}

struct OvrigtView: View {
    var project: Project
    var notesStore: NotesStore
    var linksStore: LinksStore
    var contactsStore: ContactsStore

    // Sheets
    @State private var showAddLink = false
    @State private var showAddContact = false

    // Expand state
    @State private var notesExpanded = false
    @State private var linksExpanded = false
    @State private var contactsExpanded = false

    @State private var pendingDelete: DeleteIntent? = nil

    // Entrance: cards fade + slide in staggered, same idiom as ResultView.
    // Once per view instance — segment switches recreate the view, so the
    // entrance replays each time the tab becomes visible.
    @State private var cardsRevealed = false

    // Transient per-card glow pulse: flipped true on toggle-tap, auto-reset
    // ~90 ms later by the header action so the flash never lingers.
    @State private var notesPulsing = false
    @State private var linksPulsing = false
    @State private var contactsPulsing = false

    // Swipe-to-delete: id of the link row whose delete affordance is revealed.
    // Parent-owned so opening one row snaps every other row closed.
    @State private var openSwipeLinkId: UUID? = nil
    @State private var openSwipeContactId: UUID? = nil

    // MARK: Body

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    APSectionHeader(title: "ÖVRIGT")
                        .padding(.top, 12)
                    notesSection
                        .modifier(GlowPulse(active: notesPulsing))
                        .modifier(CardEntrance(revealed: cardsRevealed, index: 0))
                    linksSection
                        .modifier(GlowPulse(active: linksPulsing))
                        .modifier(CardEntrance(revealed: cardsRevealed, index: 1))
                    contactsSection
                        .modifier(GlowPulse(active: contactsPulsing))
                        .modifier(CardEntrance(revealed: cardsRevealed, index: 2))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onAppear { cardsRevealed = true }
            }
            .refreshable {
                await notesStore.fetch(projectId: project.id)
                await linksStore.fetch(projectId: project.id)
                await contactsStore.fetch(projectId: project.id)
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await notesStore.fetch(projectId: project.id)
            await linksStore.fetch(projectId: project.id)
            await contactsStore.fetch(projectId: project.id)
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkSheet { title, url, category in
                Task {
                    do {
                        try await linksStore.add(projectId: project.id, title: title, url: url, category: category)
                    } catch {
                        print("OvrigtView: addLink error: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet { name, role, info in
                Task {
                    do {
                        // avatarColor nil tills färgväljaren i layout-steget.
                        try await contactsStore.add(projectId: project.id, name: name, role: role, contactInfo: info, avatarColor: nil)
                    } catch {
                        print("OvrigtView: addContact error: \(error)")
                    }
                }
            }
        }
        .confirmationDialog(
            pendingDelete?.title ?? "",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                        // Cancel or confirm: spring any revealed swipe row shut.
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            openSwipeLinkId = nil
                            openSwipeContactId = nil
                        }
                    }
                }
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
        pulse: Binding<Bool>,
        onAdd: (() -> Void)?,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button {
            // Haptic + pulse live in the toggle action: once per completed
            // tap, and the nested +-knappen (own action, hit-testing
            // precedence) can never trigger them.
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pulse.wrappedValue = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onToggle()
            }
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                pulse.wrappedValue = false
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
        .minTapTarget()
    }

    // MARK: - Notes section

    /// Temporär stub tills layout-steget: titel-lista, ingen add-knapp.
    /// Den riktiga fleranteckning-UI:n (kort, add-sheet, delete) byggs där.
    private var notesSection: some View {
        glassSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "ANTECKNINGAR",
                    icon: "note.text",
                    count: notesStore.notes.isEmpty ? nil : notesStore.notes.count,
                    isExpanded: notesExpanded,
                    pulse: $notesPulsing,
                    onAdd: nil
                ) { notesExpanded.toggle() }

                if notesExpanded {
                    // Same layout-identical wrapper + fade as links/contacts so
                    // all three cards reveal identically.
                    VStack(alignment: .leading, spacing: 0) {
                        if notesStore.notes.isEmpty {
                            Text("Inga anteckningar ännu")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 12)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(notesStore.notes) { note in
                                    noteRow(note)
                                    if note.id != notesStore.notes.last?.id {
                                        Divider().background(Color.apHairline)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        Text(note.title.isEmpty ? "Utan titel" : note.title)
            .font(.subheadline.bold())
            .foregroundStyle(.apTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // MARK: - Links section

    private var linksSection: some View {
        glassSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "LÄNKAR",
                    icon: "link",
                    count: linksStore.links.isEmpty ? nil : linksStore.links.count,
                    isExpanded: linksExpanded,
                    pulse: $linksPulsing,
                    onAdd: { showAddLink = true }
                ) { linksExpanded.toggle() }

                if linksExpanded {
                    // Same layout-identical wrapper + fade as Anteckningar so
                    // all three cards reveal identically.
                    VStack(alignment: .leading, spacing: 0) {
                        if linksStore.links.isEmpty {
                            Text("Inga länkar ännu")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 12)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(linksStore.links) { link in
                                    linkRow(link)
                                        .apSwipeActions(id: link.id, openId: $openSwipeLinkId, actions: [
                                            APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                                                pendingDelete = .link(link)
                                            }
                                        ])
                                    if link.id != linksStore.links.last?.id {
                                        Divider().background(Color.apHairline)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// S7: only http(s) ever reaches UIApplication.open — delegates to the
    /// policy shared with AddLinkSheet's save path so the two can't diverge.
    private func validatedLinkURL(from raw: String) -> URL? {
        LinkURLPolicy.normalized(from: raw)
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
            guard let url = validatedLinkURL(from: link.url) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Contacts section

    private var contactsSection: some View {
        glassSection {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "KONTAKTER",
                    icon: "person.2.fill",
                    count: contactsStore.contacts.isEmpty ? nil : contactsStore.contacts.count,
                    isExpanded: contactsExpanded,
                    pulse: $contactsPulsing,
                    onAdd: { showAddContact = true }
                ) { contactsExpanded.toggle() }

                if contactsExpanded {
                    // Same layout-identical wrapper + fade as Anteckningar so
                    // all three cards reveal identically.
                    VStack(alignment: .leading, spacing: 0) {
                        if contactsStore.contacts.isEmpty {
                            Text("Inga kontakter ännu")
                                .font(.caption)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 12)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(contactsStore.contacts) { contact in
                                    contactRow(contact)
                                        .apSwipeActions(id: contact.id, openId: $openSwipeContactId, actions: [
                                            APSwipeAction(title: "Ta bort", systemImage: "trash", color: .apRisk) {
                                                pendingDelete = .contact(contact)
                                            }
                                        ])
                                    if contact.id != contactsStore.contacts.last?.id {
                                        Divider().background(Color.apHairline)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .transition(.opacity)
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
    }

    // MARK: - Delete

    private func performDelete(_ intent: DeleteIntent) async {
        // Storarna äger optimistisk removal + rollback; ingen gren kastar.
        switch intent {
        case .link(let l):    await linksStore.delete(l)
        case .contact(let c): await contactsStore.delete(c)
        }
    }
}

// MARK: - Glow pulse

/// One soft apOrange flash tied to a toggle tap: quick ease-in rise while the
/// transient flag is true, ease-out decay when the header action resets it.
/// Keyed to its own value so the expand spring can't capture the shadow.
private struct GlowPulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .shadow(color: Color.apOrange.opacity(active ? 0.3 : 0), radius: 12)
            .animation(active ? .easeIn(duration: 0.08) : .easeOut(duration: 0.25), value: active)
    }
}

// MARK: - Card entrance

/// Staggered fade + slide-up, same values as ResultView's bento reveal
/// (offset 14, spring 0.45/0.8, 60 ms step) so the two screens feel identical.
private struct CardEntrance: ViewModifier {
    let revealed: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.8)
                    .delay(0.05 + Double(index) * 0.06),
                value: revealed
            )
    }
}

// MARK: - Link URL policy

/// S7 policy shared by open (linkRow) and save (AddLinkSheet): http(s) only,
/// scheme-less input ("www.hira.se") normalized to https, everything else nil.
private enum LinkURLPolicy {
    static func normalized(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        if let scheme = url.scheme?.lowercased() {
            return (scheme == "http" || scheme == "https") ? url : nil
        }
        return URL(string: "https://" + trimmed)
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

                    // Invalid URL gets the same treatment empty input always
                    // had: dimmed, disabled Spara. Normalized on save so the
                    // open-side guard is a pure backstop.
                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                        || LinkURLPolicy.normalized(from: url) == nil
                    APPillButton(title: "Spara", action: {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty,
                              let normalized = LinkURLPolicy.normalized(from: url) else { return }
                        onSave(t, normalized.absoluteString, category.rawValue)
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

// MARK: - Contact picker

/// CNContactPickerViewController kör out-of-process och kräver därför varken
/// NSContactsUsageDescription eller Contacts-behörighet — appen ser bara den
/// kontakt användaren aktivt väljer.
private struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
        // Cancel: pickern stänger sig själv; SwiftUI-sheeten följer med.
    }
}

// MARK: - Add Contact Sheet

private struct AddContactSheet: View {
    let onSave: (String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var contactInfo = ""
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    Button {
                        showPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("Välj från kontakter")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Color.apOrange)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.apSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .haptic(.light)

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
            .sheet(isPresented: $showPicker) {
                ContactPicker { contact in
                    // Autofyll — allt förblir redigerbart efteråt. role finns
                    // inte i systemkontakten och lämnas orörd.
                    let fullName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    if !fullName.isEmpty { name = fullName }
                    if let phone = contact.phoneNumbers.first?.value.stringValue {
                        contactInfo = phone
                    } else if let email = contact.emailAddresses.first?.value {
                        contactInfo = email as String
                    }
                    showPicker = false
                }
            }
        }
    }
}
