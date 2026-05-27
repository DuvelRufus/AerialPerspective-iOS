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

private struct ProjectDocument: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var content: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case content
        case updatedAt = "updated_at"
    }
}

private struct NewDocument: Encodable {
    let project_id: UUID
    let content: String
}

private struct UpdateDocument: Encodable {
    let content: String
}

struct DocumentView: View {
    var project: Project

    @State private var content: String = ""
    @State private var isSaving: Bool = false
    @State private var lastSaved: Date? = nil
    @State private var documentId: UUID? = nil
    @State private var saveTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                APCard {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("Skriv projektdokumentation, beslut, arkitektur...")
                                .font(.body)
                                .foregroundStyle(.apTextTertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $content)
                            .font(.body)
                            .foregroundStyle(.apTextPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 400)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }
        }
        .navigationTitle("Dokument")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveStatus
            }
        }
        .task { await fetchDocument() }
        .onChange(of: content) { _, _ in scheduleSave() }
        .onDisappear { saveTask?.cancel() }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if isSaving {
            Text("Sparar...")
                .font(.caption)
                .foregroundStyle(.apTextTertiary)
        } else if let saved = lastSaved {
            Text("Sparat \(saved.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.apTextTertiary)
        }
    }

    private func fetchDocument() async {
        do {
            let docs: [ProjectDocument] = try await supabase
                .from("documents")
                .select()
                .eq("project_id", value: project.id)
                .limit(1)
                .execute()
                .value
            if let doc = docs.first {
                content = doc.content
                documentId = doc.id
            }
        } catch {
            print("DocumentView: fetch error: \(error)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let existingId = documentId {
                try await supabase
                    .from("documents")
                    .update(UpdateDocument(content: content))
                    .eq("id", value: existingId)
                    .execute()
            } else {
                let inserted: ProjectDocument = try await supabase
                    .from("documents")
                    .insert(NewDocument(project_id: project.id, content: content))
                    .select()
                    .single()
                    .execute()
                    .value
                documentId = inserted.id
            }
            lastSaved = Date()
        } catch {
            print("DocumentView: save error: \(error)")
        }
    }
}
