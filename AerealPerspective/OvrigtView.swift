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
    }

    // MARK: - Section header

    /// Statisk översiktsheader per mockupen — neutral ikon-tile, titel i
    /// gemener, chevron mot den fulla sektionsvyn. Ingen count-pill, ingen
    /// quick-add: add bor i sektionsvyns toolbar.
    private func sectionHeader(
        title: String,
        icon: String,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.apSurfaceElevated)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.apTextSecondary)
                }
            VStack(alignment: .leading, spacing: 2) {
                // Gemener per mockupen — APSectionHeader versaliserar, därav Text.
                Text(title)
                    .font(.caption)
                    .tracking(1.5)
                    .foregroundStyle(Color.apTextSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.apTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.apTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notes section

    /// "Senast: <senaste anteckningens titel>" — notes.first är senast ändrad
    /// (fetch ordnar updated_at desc). Titel-fallback: första raden av body,
    /// annars "Utan titel".
    private var notesSubtitle: String {
        guard let latest = notesStore.notes.first else { return "Inga anteckningar ännu" }
        let title = latest.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return "Senast: \(title)" }
        let firstBodyLine = latest.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        return "Senast: \(firstBodyLine.isEmpty ? "Utan titel" : firstBodyLine)"
    }

    private var notesSection: some View {
        // Ren vy-destination-länk (AssessmentListView-prejudikatet): statelöst,
        // pop ägs av systemet — inget item-bundet som kan desynca.
        NavigationLink {
            NotesListView(project: project, notesStore: notesStore)
        } label: {
            APCard {
                sectionHeader(
                    title: "Anteckningar",
                    icon: "note.text",
                    subtitle: notesSubtitle
                )
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
    }

    // MARK: - Links section

    /// Glimten visar max så många favicon-tiles; resten blir en "+N"-tile —
    /// fulla listan bor i sektionsvyn.
    private static let maxChips = 4

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
                    title: "Länkar",
                    icon: "link",
                    subtitle: linksStore.links.isEmpty ? "Inga länkar ännu" : nil
                )

                if !linksStore.links.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(linksStore.links.prefix(Self.maxChips)) { link in
                            faviconTile(link)
                        }
                        if linksStore.links.count > Self.maxChips {
                            overflowTile(count: linksStore.links.count - Self.maxChips)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    /// Favicon-only tile per mockupen — passiv: länk-öppning bor i
    /// sektionsvyns rader, glimten navigerar bara via kortets NavigationLink.
    private func faviconTile(_ link: ProjectLink) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.apSurfaceElevated)
            .frame(width: 32, height: 32)
            .overlay { LinkFavicon(link: link) }
    }

    private func overflowTile(count: Int) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.apSurfaceElevated)
            .frame(width: 32, height: 32)
            .overlay {
                Text("+\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.apTextTertiary)
            }
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
                    title: "Kontakter",
                    icon: "person.2.fill",
                    subtitle: contactsStore.contacts.isEmpty ? "Inga kontakter ännu" : nil
                )

                if !contactsStore.contacts.isEmpty {
                    // Överlappande rad — variantens egen 2px-ring ger separationen.
                    HStack(spacing: -8) {
                        ForEach(contactsStore.contacts.prefix(Self.maxAvatars)) { contact in
                            InitialsAvatar(name: contact.name, colorHex: contact.avatarColor, size: 32)
                        }
                        if contactsStore.contacts.count > Self.maxAvatars {
                            // Cirkulär så den följer avatar-raden; samma
                            // färgidiom som länkarnas overflow-tile.
                            Circle()
                                .fill(Color.apSurfaceElevated)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Text("+\(contactsStore.contacts.count - Self.maxAvatars)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.apTextTertiary)
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

// MARK: - Contact form

/// Delat formulär för skapa (sheet, tomt, med picker-import) och redigera
/// (push, förifyllt, utan import — beslut). Vet inget om storen: onSave
/// levererar fälten och callern väljer add eller update. Ingen egen
/// NavigationStack — pushbar; dismiss() stänger sheeten resp. poppar pushen.
struct ContactFormView: View {
    let heading: String
    /// nil = skapa-läge; annars förifylls fälten och picker-importen döljs.
    let contact: Contact?
    /// (name, role, phone, email, avatarColor) — tomma valfria fält
    /// levereras som nil; avatarColor nil = namn-hash-fallbacken.
    let onSave: (String, String?, String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: String
    @State private var phone: String
    @State private var email: String
    @State private var avatarColor: String?
    @State private var showPicker = false

    // Flervalsimport: > 1 kandidater i respektive kanal parkeras här och
    // avgörs i varsin confirmationDialog (telefon först, sedan mail).
    @State private var phoneChoices: [String] = []
    @State private var emailChoices: [String] = []
    @State private var showPhoneChoice = false
    @State private var showEmailChoice = false

    init(
        heading: String,
        contact: Contact? = nil,
        onSave: @escaping (String, String?, String?, String?, String?) -> Void
    ) {
        self.heading = heading
        self.contact = contact
        self.onSave = onSave
        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _avatarColor = State(initialValue: contact?.avatarColor)
    }

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if contact == nil {
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
                    }

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
                        APSectionHeader(title: "TELEFON (VALFRITT)")
                        TextField("", text: $phone)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .keyboardType(.phonePad)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "E-POST (VALFRITT)")
                        TextField("", text: $email)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "FÄRG")
                        HStack(spacing: 12) {
                            // Live-preview: nil → hash-fallback som följer namnet
                            // medan man skriver.
                            InitialsAvatar(name: name.isEmpty ? "?" : name, colorHex: avatarColor, size: 40)
                            HStack(spacing: 8) {
                                ForEach(AvatarPalette.hexes, id: \.self) { hex in
                                    colorDot(hex)
                                }
                            }
                        }
                    }

                    let isDisabled = name.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(
                            trimmed,
                            role.isEmpty ? nil : role,
                            phone.isEmpty ? nil : phone,
                            email.isEmpty ? nil : email,
                            avatarColor
                        )
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                }
                .padding()
            }
        }
        .navigationTitle(heading)
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
                // Ett värde → tyst autofyll; flera → dialog per kanal.
                // Dedupe med bevarad ordning — dubblettsträngar skulle
                // kollidera i ForEach(id: \.self).
                let phones = orderedUnique(contact.phoneNumbers.map { $0.value.stringValue })
                let emails = orderedUnique(contact.emailAddresses.map { $0.value as String })
                if phones.count == 1 { phone = phones[0] }
                if emails.count == 1 { email = emails[0] }
                phoneChoices = phones.count > 1 ? phones : []
                emailChoices = emails.count > 1 ? emails : []
                showPicker = false
                if !phoneChoices.isEmpty || !emailChoices.isEmpty {
                    Task {
                        // Vänta ut pickerns självdismissal — en dialog
                        // som presenteras mitt i den animationen svälls.
                        try? await Task.sleep(for: .milliseconds(400))
                        if !phoneChoices.isEmpty {
                            showPhoneChoice = true
                        } else {
                            showEmailChoice = true
                        }
                    }
                }
            }
        }
        .confirmationDialog("Välj telefonnummer", isPresented: $showPhoneChoice, titleVisibility: .visible) {
            ForEach(phoneChoices, id: \.self) { number in
                Button(number) { phone = number }
            }
            Button("Avbryt", role: .cancel) { }   // fältet lämnas orört
        }
        // Kedjningen ligger på false-flanken, inte i knapparna: den
        // träffas av val, Avbryt och tap-utanför likvärdigt, och dialog
        // #2 direkt i en knapp-action svalts av #1:s dismissal.
        .onChange(of: showPhoneChoice) { _, isPresented in
            guard !isPresented else { return }
            phoneChoices = []
            if !emailChoices.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    showEmailChoice = true
                }
            }
        }
        .confirmationDialog("Välj e-postadress", isPresented: $showEmailChoice, titleVisibility: .visible) {
            ForEach(emailChoices, id: \.self) { address in
                Button(address) { email = address }
            }
            Button("Avbryt", role: .cancel) { }   // fältet lämnas orört
        }
        .onChange(of: showEmailChoice) { _, isPresented in
            if !isPresented { emailChoices = [] }
        }
    }

    /// Tap väljer; tap på redan vald prick avmarkerar → tillbaka till
    /// namn-hash-fallbacken (beslut).
    private func colorDot(_ hex: String) -> some View {
        let isSelected = avatarColor == hex
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                avatarColor = isSelected ? nil : hex
            }
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 24, height: 24)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.apTextPrimary, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .scaleEffect(isSelected ? 1.15 : 1)
        }
        .buttonStyle(.plain)
    }

    /// Behåller första förekomsten av varje värde, i ursprunglig ordning.
    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

// MARK: - Add Contact Sheet

/// Skapa-läget: quick-capture-sheet med egen NavigationStack. Redigera-läget
/// pushar ContactFormView direkt i projektstacken i stället.
struct AddContactSheet: View {
    let onSave: (String, String?, String?, String?, String?) -> Void

    var body: some View {
        NavigationStack {
            ContactFormView(heading: "Ny kontakt", onSave: onSave)
        }
    }
}
