//
//  ProjectListView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import SwiftUI

struct ProjectListView: View {
    var authStore: AuthStore
    var questionStore: QuestionStore

    @State private var projectStore = ProjectStore()
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if projectStore.isLoading {
                    ProgressView()
                        .tint(.cyan)
                } else if projectStore.projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(.cyan)
                        Text("Inga projekt ännu")
                            .foregroundStyle(.white)
                        Text("Skapa ditt första projekt för att börja.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        ForEach(projectStore.projects) { project in
                            NavigationLink {
                                AssessmentListView(
                                    project: project,
                                    questionStore: questionStore
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name)
                                        .foregroundStyle(.white)
                                        .font(.headline)
                                    if let val = project.durationValue,
                                       let unit = project.durationUnit {
                                        Text("\(val) \(unit.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                        .onDelete { indexSet in
                            Task {
                                for i in indexSet {
                                    try? await projectStore.delete(projectStore.projects[i])
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Projekt")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.cyan)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Logga ut") {
                        Task { try? await authStore.signOut() }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .alert("Nytt projekt", isPresented: $showNewProject) {
                TextField("Projektnamn", text: $newProjectName)
                Button("Skapa") {
                    Task { await createProject() }
                }
                Button("Avbryt", role: .cancel) {
                    newProjectName = ""
                }
            }
            .task { await projectStore.fetch() }
        }
    }

    private func createProject() async {
        guard !newProjectName.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            try await projectStore.create(name: newProjectName)
            newProjectName = ""
        } catch {
            projectStore.error = error
            print("createProject error: \(error)")
        }
    }
}
