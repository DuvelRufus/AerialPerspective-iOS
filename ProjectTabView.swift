//
//  ProjectTabView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-27.
//

import UIKit
import SwiftUI

struct ProjectTabView: View {
    var project: Project
    var questionStore: QuestionStore
    @State private var selectedSection: Int
    @State private var actionStore = ActionStore()
    @State private var notesStore = NotesStore()
    @State private var linksStore = LinksStore()

    private enum Section: Int {
        case assessments = 0
        case tasks = 1
        case resources = 2
    }

    /// initialSection is a raw Section value (0 = Assessments, 1 = Tasks …);
    /// the Tasks lens pushes straight to Tasks, existing callers keep 0.
    init(project: Project, questionStore: QuestionStore, initialSection: Int = 0) {
        self.project = project
        self.questionStore = questionStore
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                APSegmentedControl(selection: $selectedSection, options: ["Assessments", "Tasks", "Resources"])
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                switch Section(rawValue: selectedSection) ?? .assessments {
                case .assessments:
                    AssessmentListView(project: project, questionStore: questionStore)
                case .tasks:
                    PlanView(project: project, questionStore: questionStore, actionStore: actionStore)
                case .resources:
                    OvrigtView(project: project, notesStore: notesStore, linksStore: linksStore)
                }
            }
        }
        .task {
            // Fetch once at the parent so the shared actions survive segment
            // switches; subviews read this instance instead of refetching.
            actionStore.error = nil
            await actionStore.fetch(projectId: project.id)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// APSegmentedControl lives in DesignSystem — shared with OversiktView.
