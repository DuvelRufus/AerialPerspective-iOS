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
    @State private var selectedSection = 0
    @State private var actionStore = ActionStore()
    @State private var noteStore = NoteStore()

    private enum Section: Int {
        case assessments = 0
        case plan = 1
        case actions = 2
        case ovrigt = 3
    }

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                APSegmentedControl(selection: $selectedSection, options: ["Assessments", "Plan", "Åtgärder", "Övrigt"])
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                switch Section(rawValue: selectedSection) ?? .assessments {
                case .assessments:
                    AssessmentListView(project: project, questionStore: questionStore)
                case .plan:
                    PlanView(project: project, questionStore: questionStore, actionStore: actionStore)
                case .actions:
                    DocumentView(project: project, questionStore: questionStore, actionStore: actionStore)
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
