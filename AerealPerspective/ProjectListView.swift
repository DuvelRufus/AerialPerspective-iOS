//
//  ProjectListView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import UIKit
import SwiftUI

struct ProjectListView: View {
    var authStore: AuthStore
    var questionStore: QuestionStore

    @State private var projectStore = ProjectStore()
    @State private var showNewProject = false
    @State private var isCreating = false
    @State private var projectToDelete: Project? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()

                if projectStore.isLoading {
                    ProgressView()
                        .tint(.apOrange)
                } else if projectStore.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("Projekt")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewProject = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.apOrange)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Logga ut") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { try? await authStore.signOut() }
                    }
                    .font(.caption)
                    .foregroundStyle(.apTextTertiary)
                }
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectSheet { name, value, unit in
                    showNewProject = false
                    Task { await createProject(name: name, durationValue: value, durationUnit: unit) }
                }
            }
            .task { await projectStore.fetch() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.apOrange)
            Text("Inga projekt ännu")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            Text("Skapa ditt första projekt för att börja.")
                .font(.caption)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
            APPillButton(title: "Skapa första projekt") {
                showNewProject = true
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    private var projectList: some View {
        List {
            ForEach(projectStore.projects) { project in
                NavigationLink {
                    ProjectTabView(
                        project: project,
                        questionStore: questionStore
                    )
                } label: {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.apOrange)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name)
                                .font(.title3.bold())
                                .foregroundStyle(.apTextPrimary)
                            if let val = project.durationValue,
                               let unit = project.durationUnit {
                                Text(durationLabel(val, unit))
                                    .font(.subheadline)
                                    .foregroundStyle(.apTextSecondary)
                            }
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 20)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.apSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        projectToDelete = project
                    } label: {
                        Label("Radera", systemImage: "trash")
                    }
                    .tint(Color.apRisk)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            projectToDelete.map { "Radera \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                guard let project = projectToDelete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                projectToDelete = nil
                Task { try? await projectStore.delete(project) }
            }
            Button("Avbryt", role: .cancel) {
                projectToDelete = nil
            }
        } message: {
            Text("Projektet och alla dess assessments tas bort permanent.")
        }
    }

    private func durationLabel(_ value: Int, _ unit: DurationUnit) -> String {
        switch unit {
        case .weeks:  return value == 1 ? "1 vecka"  : "\(value) veckor"
        case .months: return value == 1 ? "1 månad"  : "\(value) månader"
        case .years:  return "\(value) år"
        }
    }

    private func createProject(name: String, durationValue: Int?, durationUnit: DurationUnit?) async {
        isCreating = true
        defer { isCreating = false }
        do {
            _ = try await projectStore.create(name: name, durationValue: durationValue, durationUnit: durationUnit)
        } catch {
            projectStore.error = error
            print("createProject error: \(error)")
        }
    }
}

// MARK: - New project sheet

private struct NewProjectSheet: View {
    let onCreate: (String, Int, DurationUnit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var durationUnit: DurationUnit = .months
    @State private var durationValue = 3

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "Projektnamn")
                        TextField("", text: $name)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "Varaktighet")
                        Picker("Enhet", selection: $durationUnit) {
                            Text("Veckor").tag(DurationUnit.weeks)
                            Text("Månader").tag(DurationUnit.months)
                            Text("År").tag(DurationUnit.years)
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Text("\(durationValue) \(unitLabel)")
                            .foregroundStyle(.apTextPrimary)
                        Spacer()
                        Stepper("", value: $durationValue, in: valueRange)
                    }
                    .padding()
                    .background(Color.apSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    let isDisabled = name.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Skapa projekt") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onCreate(trimmed, durationValue, durationUnit)
                    }
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Nytt projekt")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: durationUnit) { _, newUnit in
                switch newUnit {
                case .weeks:  durationValue = 4
                case .months: durationValue = 3
                case .years:  durationValue = 1
                }
            }
        }
    }

    private var valueRange: ClosedRange<Int> {
        switch durationUnit {
        case .weeks:  return 1...52
        case .months: return 1...24
        case .years:  return 1...5
        }
    }

    private var unitLabel: String {
        switch durationUnit {
        case .weeks:  return "veckor"
        case .months: return "månader"
        case .years:  return "år"
        }
    }
}
