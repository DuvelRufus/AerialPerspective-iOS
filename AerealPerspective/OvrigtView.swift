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

struct OvrigtView: View {
    var project: Project
    var notesStore: NotesStore
    var linksStore: LinksStore
    var contactsStore: ContactsStore

    // Sheets
    @State private var showAddLink = false
    @State private var showAddContact = false

    // Entrance: cards fade + slide in staggered, same idiom as ResultView.
    // Once per view instance — segment switches recreate the view, so the
    // entrance replays each time the tab becomes visible.
    @State private var cardsRevealed = false

    // MARK: Body

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    APSectionHeader(title: "RESOURCES")
                        .padding(.top, 12)
                    notesSection
                        .modifier(CardEntrance(revealed: cardsRevealed, index: 0))
                    linksSection
                        .modifier(CardEntrance(revealed: cardsRevealed, index: 1))
                    contactsSection
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
    }

    // MARK: - Section header

    /// Statisk översiktsheader — accordion borta; chevronen pekar mot den
    /// fulla sektionsvyn (kopplas i delsteg 2). +-knappen har egen Button
    /// med hit-precedens.
    private func sectionHeader(
        title: String,
        icon: String,
        subtitle: String? = nil,
        count: Int?,
        onAdd: (() -> Void)?
    ) -> some View {
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
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notes section

    /// "N anteckningar · senast för 2 dagar sedan" — fetch ordnar
    /// updated_at desc, så first är senast ändrad.
    private var notesSubtitle: String {
        let n = notesStore.notes.count
        guard n > 0, let latest = notesStore.notes.first?.updatedAt else {
            return "Inga anteckningar ännu"
        }
        let rel = RelativeDateTimeFormatter().localizedString(for: latest, relativeTo: Date())
        return "\(n) anteckning\(n == 1 ? "" : "ar") · senast \(rel)"
    }

    private var notesSection: some View {
        // Ren vy-destination-länk (AssessmentListView-prejudikatet): statelöst,
        // pop ägs av systemet — inget item-bundet som kan desynca.
        NavigationLink {
            NotesListView(project: project, notesStore: notesStore)
        } label: {
            APCard {
                sectionHeader(
                    title: "ANTECKNINGAR",
                    icon: "note.text",
                    subtitle: notesSubtitle,
                    count: notesStore.notes.isEmpty ? nil : notesStore.notes.count,
                    onAdd: nil
                )
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
    }

    // MARK: - Links section

    /// Glimten visar max så många chips; resten blir en "+N"-chip —
    /// fulla listan bor i sektionsvyn (delsteg 2).
    private static let maxChips = 8

    private var linksSection: some View {
        NavigationLink {
            LinksListView(project: project, linksStore: linksStore)
        } label: {
            linksCardLabel
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
    }

    private var linksCardLabel: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "LÄNKAR",
                    icon: "link",
                    subtitle: linksStore.links.isEmpty ? "Inga länkar ännu" : nil,
                    count: linksStore.links.isEmpty ? nil : linksStore.links.count,
                    onAdd: { showAddLink = true }
                )

                if !linksStore.links.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(linksStore.links.prefix(Self.maxChips)) { link in
                            linkChip(link)
                        }
                        if linksStore.links.count > Self.maxChips {
                            Text("+\(linksStore.links.count - Self.maxChips)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.apTextSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.apSurfaceElevated)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    /// S7: only http(s) ever reaches UIApplication.open — delegates to the
    /// policy shared with AddLinkSheet's save path so the two can't diverge.
    private func validatedLinkURL(from raw: String) -> URL? {
        LinkURLPolicy.normalized(from: raw)
    }

    private func linkChip(_ link: ProjectLink) -> some View {
        Button {
            guard let url = validatedLinkURL(from: link.url) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                LinkFavicon(link: link)
                Text(link.title)
                    .font(.caption)
                    .foregroundStyle(.apTextPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.apSurfaceElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }


    // MARK: - Contacts section

    /// Glimten visar max så många avatarer; resten blir en "+N"-bubbla.
    private static let maxAvatars = 5

    private var contactsSection: some View {
        NavigationLink {
            ContactsListView(project: project, contactsStore: contactsStore)
        } label: {
            contactsCardLabel
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
    }

    private var contactsCardLabel: some View {
        APCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(
                    title: "KONTAKTER",
                    icon: "person.2.fill",
                    subtitle: contactsStore.contacts.isEmpty ? "Inga kontakter ännu" : nil,
                    count: contactsStore.contacts.isEmpty ? nil : contactsStore.contacts.count,
                    onAdd: { showAddContact = true }
                )

                if !contactsStore.contacts.isEmpty {
                    // Överlappande rad — variantens egen 2px-ring ger separationen.
                    HStack(spacing: -8) {
                        ForEach(contactsStore.contacts.prefix(Self.maxAvatars)) { contact in
                            InitialsAvatar(name: contact.name, colorHex: contact.avatarColor, size: 32)
                        }
                        if contactsStore.contacts.count > Self.maxAvatars {
                            Circle()
                                .fill(Color.apSurfaceElevated)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text("+\(contactsStore.contacts.count - Self.maxAvatars)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.apTextSecondary)
                                }
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
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

// MARK: - Link favicon

/// AsyncImage går via shared URLSession → URLCache cachar favicon-svaren.
/// Fallback (nil-favicon, laddning, fel): bokstavs-ikon i orange. Delas av
/// översiktskortets chips (16pt) och LinksListViews rader (28pt).
struct LinkFavicon: View {
    let link: ProjectLink
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let raw = link.faviconUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(Color.apOrangeTint)
            .overlay {
                if let first = link.title.first {
                    Text(String(first).uppercased())
                        .font(.system(size: size * 0.56, weight: .semibold))
                        .foregroundStyle(Color.apOrange)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(Color.apOrange)
                }
            }
    }
}

// MARK: - Flow layout

/// Minimal wrap-layout för chip-raden: radbryt när nästa chip inte ryms,
/// radhöjd = högsta chip i raden. Privat tills fler ytor behöver wrap.
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

// MARK: - Link URL policy

/// S7 policy shared by open (chips + LinksListView rows) and save
/// (AddLinkSheet): http(s) only, scheme-less input ("www.hira.se")
/// normalized to https, everything else nil.
enum LinkURLPolicy {
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

/// Pickern presenteras via UIKit present() från en osynlig host-VC. Som
/// .sheet-rot bryts den out-of-process-delegatkanalen — didSelect levereras
/// aldrig (verifierad bugg). Via UIKit äger pickern sin egen dismissal och
/// callbacken kommer fram. Behörighetsläget oförändrat: out-of-process,
/// ingen NSContactsUsageDescription.
private struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()   // osynligt ankare i hierarkin, presenterar pickern
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self   // färsk binding/closure varje render
        if isPresented && !context.coordinator.isPresenting {
            context.coordinator.isPresenting = true
            let picker = CNContactPickerViewController()
            picker.delegate = context.coordinator
            host.present(picker, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPickerPresenter
        /// Guard: updateUIViewController körs flera gånger per presentation.
        var isPresenting = false
        init(parent: ContactPickerPresenter) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPick(contact)
            finish()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            finish()   // avbryt nollar också showPicker — pickern kan öppnas igen
        }

        /// Pickern river sin egen presentation; här synkas bara SwiftUI-staten.
        private func finish() {
            isPresenting = false
            parent.isPresented = false
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
            .background {
                ContactPickerPresenter(isPresented: $showPicker) { contact in
                    // Autofyll — allt förblir redigerbart efteråt. role finns
                    // inte i systemkontakten och lämnas orörd.
                    let fullName = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    if !fullName.isEmpty {
                        name = fullName
                    } else if !contact.organizationName.isEmpty {
                        // Företagskontakt utan person-namn: organisationen är namnet.
                        name = contact.organizationName
                    }
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
