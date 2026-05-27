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
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AssessmentListView(project: project, questionStore: questionStore)
                .tabItem { Label("Assessments", systemImage: "chart.bar.doc.horizontal") }
                .tag(0)

            DocumentView(project: project)
                .tabItem { Label("Dokument", systemImage: "doc.text") }
                .tag(1)
        }
        .tint(Color.apOrange)
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .tabBar)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: selectedTab) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
