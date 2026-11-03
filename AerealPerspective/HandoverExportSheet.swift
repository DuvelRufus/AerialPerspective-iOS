//
//  HandoverExportSheet.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-11-03.
//

import SwiftUI
import Supabase   // error types only (AuthError, HTTPError, PostgrestError); no query is made here

/// Internal handover ("Överlämning"): pick projects, load them with
/// HandoverLoader, check the result, share the Markdown file written by
/// HandoverMarkdown. Read-only. Not anonymized by design; the notice at the
/// top says so.
///
/// All state lives in HandoverExportModel below. The view only draws it and
/// forwards taps; the model only calls HandoverLoader and HandoverMarkdown.
///
/// QuestionStore is passed through to the loader and never read here. The
/// sheet does not trigger QuestionStore.fetch() when it opens (the app
/// already does that once after sign-in); HandoverLoader.load fetches it
/// itself when "Skapa" is pressed and judges success from the store's state.
struct HandoverExportSheet: View {
    let questionStore: QuestionStore

    @Environment(\.dismiss) private var dismiss
    @State private var model = HandoverExportModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    notice
                    content
                }
                .padding()
            }
            .navigationTitle("Överlämning")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .task { model.start() }
        // Swipe-down and the Stäng button both end up here: a running load is
        // cancelled and nothing is written (files are written only after a
        // finished load).
        .onDisappear { model.cancel() }
    }

    // MARK: Notice

    private var notice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.apOrange)
                .accessibilityHidden(true)
            Text("Internt underlag. Innehåller projektnamn och åtgärdstexter. Ej anonymiserat.")
                .font(.footnote)
                .foregroundStyle(Color.apTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.apSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    // MARK: Phases

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loadingProjects:
            VStack(spacing: 16) {
                ProgressView().tint(.apOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Hämtar projekt")
                createButton
                closeButton
            }
        case .projectsFailed(let message):
            VStack(spacing: 16) {
                APErrorState(message: message, retryTitle: "Försök igen") { model.reloadProjects() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                createButton
                closeButton
            }
        case .empty:
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.apOrange)
                    Text("Inga projekt att lämna över")
                        .font(.headline)
                        .foregroundStyle(Color.apTextPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                createButton
                closeButton
            }
        case .picking:
            VStack(spacing: 16) {
                projectList
                createButton
                closeButton
            }
        case .creating:
            creatingView
        case .failed(let message):
            VStack(spacing: 16) {
                APErrorState(message: message, retryTitle: "Försök igen") { model.retryLast() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                closeButton
            }
        case .result:
            resultView
        }
    }

    // MARK: Picking

    private var projectList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 {
                        Rectangle().fill(Color.apHairline).frame(height: 0.5).padding(.leading, 52)
                    }
                    projectRow(candidate)
                }
            }
            .background(Color.apSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func projectRow(_ candidate: HandoverProjectCandidate) -> some View {
        let isOn = model.selected.contains(candidate.id)
        return Button {
            model.toggle(candidate.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.apOrange : Color.apTextTertiary)
                Text(candidate.name)
                    .font(.body)
                    .foregroundStyle(Color.apTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if candidate.ownedBySomeoneElse {
                    Text("annan ägare")
                        .font(.caption)
                        .foregroundStyle(Color.apNote)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.ownedBySomeoneElse ? "\(candidate.name), annan ägare" : candidate.name)
        .accessibilityValue(isOn ? "Vald" : "Inte vald")
        .accessibilityAddTraits(.isToggle)
    }

    private var createButton: some View {
        APPillButton(title: "Skapa") { model.create(questionStore: questionStore) }
            .disabled(!model.canCreate)
            .opacity(model.canCreate ? 1 : 0.4)
    }

    private var closeButton: some View {
        APPillButton(title: "Stäng", action: { dismiss() }, style: .secondary)
    }

    // MARK: Creating

    private var creatingView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 16) {
                ProgressView(value: model.progressFraction)
                    .tint(.apOrange)
                Text(model.progressText)
                    .font(.body)
                    .foregroundStyle(Color.apTextPrimary)
                    .multilineTextAlignment(.center)
                if model.isRetryingFailedOnly {
                    Text("Bara de team som saknas hämtas på nytt.")
                        .font(.caption)
                        .foregroundStyle(Color.apTextSecondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            APPillButton(title: "Avbryt", action: { model.cancel() }, style: .secondary)
        }
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let data = model.data {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hämtade \(data.loadedCount) av \(data.requestedCount) team")
                            .font(.headline)
                            .foregroundStyle(Color.apTextPrimary)

                        if !data.isComplete {
                            incompleteBanner(data)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(data.teams.enumerated()), id: \.element.id) { index, team in
                                if index > 0 {
                                    Rectangle().fill(Color.apHairline).frame(height: 0.5).padding(.leading, 16)
                                }
                                teamRow(team)
                            }
                        }
                        .background(Color.apSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text("Totalt \(Self.openActionsText(model.totalOpenActions)) i dokumentet")
                            .font(.caption)
                            .foregroundStyle(Color.apTextSecondary)
                    }
                }

                if !data.isComplete {
                    APPillButton(title: "Försök igen", action: { model.retryFailed(questionStore: questionStore) }, style: .secondary)
                        .accessibilityHint("Hämtar bara de team som saknas")
                }
                if let url = model.fileURL {
                    // A file URL needs no explicit type: the .md extension carries it. The
                    // preview only fixes the title the share sheet shows to the file name.
                    ShareLink(item: url, preview: SharePreview(url.lastPathComponent)) {
                        Label(data.isComplete ? "Dela fil" : "Dela ofullständig fil", systemImage: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Capsule().fill(Color.apOrange))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(data.isComplete ? "Dela överlämningsfilen" : "Dela ofullständig överlämningsfil")
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(Color.apTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                closeButton
            }
        }
    }

    /// The design system's warning style: apNote (the amber of the "note"
    /// score level) as a tinted panel. Not apRisk red.
    private func incompleteBanner(_ data: HandoverData) -> some View {
        let missing = data.requestedCount - data.loadedCount
        let failed: [String] = data.teams.compactMap { team in
            if case .failed(let reason) = team.outcome { return "\(team.name): \(reason)" }
            return nil
        }
        return VStack(alignment: .leading, spacing: 6) {
            Label("OFULLSTÄNDIG: \(missing) av \(data.requestedCount) team saknas", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.apNote)
            ForEach(Array(failed.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Color.apTextPrimary)
            }
            Text("Dokumentet säger OFULLSTÄNDIG och listar de saknade teamen. Det är inte en komplett överlämning.")
                .font(.caption)
                .foregroundStyle(Color.apTextSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.apNote.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.apNote.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func teamRow(_ team: HandoverTeam) -> some View {
        let detail: String
        let isFailed: Bool
        switch team.outcome {
        case .loaded(let data):
            detail = Self.openActionsText(data.openCounts.total)
            isFailed = false
        case .failed(let reason):
            detail = "kunde inte hämtas (\(reason))"
            isFailed = true
        }
        return HStack(spacing: 12) {
            Text(team.name)
                .font(.body)
                .foregroundStyle(Color.apTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(isFailed ? Color.apNote : Color.apTextSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private static func openActionsText(_ count: Int) -> String {
        count == 1 ? "1 öppen åtgärd" : "\(count) öppna åtgärder"
    }
}

// MARK: - Model

@MainActor
@Observable
final class HandoverExportModel {

    enum Phase: Equatable {
        case loadingProjects
        case projectsFailed(String)
        case empty
        case picking
        case creating
        case failed(String)
        case result
    }

    private(set) var phase: Phase = .loadingProjects
    private(set) var candidates: [HandoverProjectCandidate] = []
    private(set) var selected: Set<UUID> = []

    private(set) var progressIndex = 0
    private(set) var progressTotal = 0
    private(set) var progressName = ""
    private(set) var isRetryingFailedOnly = false

    private(set) var data: HandoverData?
    private(set) var fileURL: URL?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped on every start and cancel; a finishing task whose number is
    /// stale (cancelled, or replaced by a newer run) changes nothing.
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var started = false
    /// What "Försök igen" repeats after a failed create.
    @ObservationIgnored private var lastAttempt: (projects: [HandoverProjectCandidate], base: HandoverData?, store: QuestionStore)?

    var canCreate: Bool { phase == .picking && !selected.isEmpty }

    var progressFraction: Double {
        guard progressTotal > 0 else { return 0 }
        return Double(max(progressIndex - 1, 0)) / Double(progressTotal)
    }

    var progressText: String {
        progressIndex == 0 ? "Förbereder…" : "Hämtar team \(progressIndex) av \(progressTotal), \(progressName)"
    }

    var totalOpenActions: Int {
        guard let data else { return 0 }
        return data.teams.reduce(0) { sum, team in
            if case .loaded(let teamData) = team.outcome { return sum + teamData.openCounts.total }
            return sum
        }
    }

    // MARK: Project list

    func start() {
        guard !started else { return }
        started = true
        loadProjects()
    }

    func reloadProjects() {
        loadProjects()
    }

    private func loadProjects() {
        task?.cancel()
        run += 1
        let id = run
        phase = .loadingProjects
        task = Task { [self] in
            do {
                let list = try await HandoverLoader.loadProjects()
                guard run == id, !Task.isCancelled else { return }
                candidates = list
                selected = Set(list.filter(\.isSelectedByDefault).map(\.id))
                phase = list.isEmpty ? .empty : .picking
            } catch {
                guard run == id, !Task.isCancelled, !Self.isCancellation(error) else { return }
                phase = .projectsFailed(Self.message(for: error))
            }
        }
    }

    func toggle(_ id: UUID) {
        guard phase == .picking else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    // MARK: Create

    func create(questionStore: QuestionStore) {
        guard canCreate else { return }
        let chosen = candidates.filter { selected.contains($0.id) }
        data = nil
        fileURL = nil
        begin(projects: chosen, base: nil, questionStore: questionStore)
    }

    /// Reloads only the teams that failed and merges them into the loaded
    /// ones. The loader takes a list of projects, so no loader change is
    /// needed; the document keeps the original requested count.
    func retryFailed(questionStore: QuestionStore) {
        guard phase == .result, let base = data else { return }
        let failedIds: Set<UUID> = Set(base.teams.compactMap { team in
            if case .failed = team.outcome { return team.projectId }
            return nil
        })
        let projects = candidates.filter { failedIds.contains($0.id) }
        guard !projects.isEmpty else { return }
        begin(projects: projects, base: base, questionStore: questionStore)
    }

    func retryLast() {
        guard let last = lastAttempt else { return }
        begin(projects: last.projects, base: last.base, questionStore: last.store)
    }

    private func begin(projects: [HandoverProjectCandidate], base: HandoverData?, questionStore: QuestionStore) {
        task?.cancel()
        run += 1
        let id = run
        lastAttempt = (projects, base, questionStore)
        isRetryingFailedOnly = base != nil
        progressIndex = 0
        progressTotal = projects.count
        progressName = ""
        phase = .creating

        task = Task { [self] in
            do {
                let loaded = try await HandoverLoader.load(
                    projects: projects,
                    questionStore: questionStore,
                    progress: { index, total, name in
                        guard self.run == id else { return }
                        self.progressIndex = index
                        self.progressTotal = total
                        self.progressName = name
                    }
                )
                // Cancelled while the last request was in flight: no file.
                guard run == id, !Task.isCancelled else { return }

                let merged: HandoverData
                if let base {
                    let kept = base.teams.filter { team in
                        if case .loaded = team.outcome { return true }
                        return false
                    }
                    merged = HandoverData(
                        generatedAt: loaded.generatedAt,
                        requestedCount: base.requestedCount,
                        teams: kept + loaded.teams
                    )
                } else {
                    merged = loaded
                }
                // Synchronous: nothing can cancel between the check above and the write.
                let url = try HandoverMarkdown.write(merged)
                data = merged
                fileURL = url
                phase = .result
            } catch {
                guard run == id, !Task.isCancelled, !Self.isCancellation(error) else { return }
                phase = .failed(Self.message(for: error))
            }
        }
    }

    // MARK: Cancel

    /// "Avbryt" and dismissal. Silent: no error text, and since files are
    /// written only after a finished load, nothing is left behind. Safe to
    /// call in any phase.
    func cancel() {
        let wasWorking = phase == .creating || phase == .loadingProjects
        task?.cancel()
        task = nil
        run += 1
        guard wasWorking else { return }
        if phase == .creating {
            phase = data != nil ? .result : .picking
        }
    }

    // MARK: Errors

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Plain Swedish text; never the raw error. An expired session (a thrown
    /// auth error, or a 401/403 from the API) asks for a new sign-in.
    static func message(for error: Error) -> String {
        let session = "Din inloggning har gått ut. Logga in igen och försök på nytt."
        if error is AuthError { return session }
        if let http = error as? HTTPError, [401, 403].contains(http.response.statusCode) { return session }
        if let postgrest = error as? PostgrestError, postgrest.message.localizedCaseInsensitiveContains("jwt") { return session }
        if let loaderError = error as? HandoverLoaderError { return loaderError.errorDescription ?? "Något gick fel. Försök igen." }
        if let readError = error as? HandoverReadError { return readError.errorDescription ?? "Något gick fel. Försök igen." }
        if error is URLError { return "Ingen anslutning. Kontrollera din anslutning och försök igen." }
        if error is CocoaError { return "Filen kunde inte sparas. Försök igen." }
        print("HandoverExportModel: \(type(of: error))")
        return "Något gick fel. Försök igen."
    }
}
