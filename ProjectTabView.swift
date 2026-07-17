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
    @State private var noteStore = NoteStore()

    private enum Section: Int {
        case assessments = 0
        case plan = 1
        case ovrigt = 2
    }

    /// initialSection is a raw Section value (0 = Assessments, 1 = Plan …);
    /// the Tasks lens pushes straight to Plan, existing callers keep 0.
    init(project: Project, questionStore: QuestionStore, initialSection: Int = 0) {
        self.project = project
        self.questionStore = questionStore
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                APSegmentedControl(selection: $selectedSection, options: ["Assessments", "Plan", "Övrigt"])
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                switch Section(rawValue: selectedSection) ?? .assessments {
                case .assessments:
                    AssessmentListView(project: project, questionStore: questionStore)
                case .plan:
                    PlanView(project: project, questionStore: questionStore, actionStore: actionStore)
                case .ovrigt:
                    OvrigtView(project: project, noteStore: noteStore)
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
