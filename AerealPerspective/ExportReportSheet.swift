//
//  ExportReportSheet.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-10-06.
//

import SwiftUI

/// Builds the project PDF report on demand and hands it to the share
/// sheet. Read-only: loads via ProjectReportLoader, writes only a temp file.
struct ExportReportSheet: View {
    let project: Project
    let questionStore: QuestionStore

    @Environment(\.dismiss) private var dismiss
    @State private var anonymize = true
    @State private var hideTexts = true
    @State private var isGenerating = false
    @State private var reportURL: URL? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "RAPPORT")
                        VStack(spacing: 0) {
                            Toggle("Anonymisera projektnamn", isOn: $anonymize)
                                .padding()
                            Rectangle()
                                .fill(Color.apHairline)
                                .frame(height: 0.5)
                                .padding(.leading)
                            Toggle("Dölj uppgifts- och insiktstexter", isOn: $hideTexts)
                                .padding()
                        }
                        .tint(.apOrange)
                        .foregroundStyle(.apTextPrimary)
                        .background(Color.apSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .disabled(isGenerating)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.apRisk)
                            .multilineTextAlignment(.center)
                    }

                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label("Dela PDF", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(Color.apOrange))
                        }
                        .buttonStyle(.plain)
                        Text(reportURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        APPillButton(title: "Skapa rapport", action: {
                            Task { await generate() }
                        }, isLoading: isGenerating)
                        .disabled(isGenerating)
                    }

                    APPillButton(title: "Stäng", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Exportera rapport")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        // A built file reflects the toggles it was made with — drop it
        // so a flipped toggle can't share the other variant.
        .onChange(of: anonymize) {
            reportURL = nil
            errorMessage = nil
        }
        .onChange(of: hideTexts) {
            reportURL = nil
            errorMessage = nil
        }
    }

    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let data = try await ProjectReportLoader.load(
                project: project,
                questionStore: questionStore,
                anonymized: anonymize,
                hideTexts: hideTexts
            )
            reportURL = try ProjectReportPDF.render(data)
        } catch {
            errorMessage = error.localizedDescription
            print("ExportReportSheet: generate error: \(error)")
        }
    }
}
