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

private struct APSegmentedControl: View {
    @Binding var selection: Int
    let options: [String]
    @Namespace private var ns

    var body: some View {
        // Innehållsbredd i stället för lika flex; skrollar horisontellt
        // om segmenten någonsin inte får plats.
        ViewThatFits(in: .horizontal) {
            pills
            ScrollView(.horizontal, showsIndicators: false) {
                pills
            }
        }
    }

    private var pills: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = i
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(options[i])
                        .font(.subheadline.weight(selection == i ? .semibold : .regular))
                        .foregroundStyle(selection == i ? Color.apTextPrimary : Color.apTextSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if selection == i {
                                Capsule()
                                    .fill(Color.apSurfaceElevated)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.apSurface))
        .overlay(Capsule().strokeBorder(Color.apHairline, lineWidth: 0.5))
    }
}
