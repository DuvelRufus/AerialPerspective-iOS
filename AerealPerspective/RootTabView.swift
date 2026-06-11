//
//  RootTabView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-06-11.
//

import UIKit
import SwiftUI

struct RootTabView: View {
    var authStore: AuthStore
    var questionStore: QuestionStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ProjectListView(authStore: authStore, questionStore: questionStore)
                .tabItem { Label("Projekt", systemImage: "folder") }
                .tag(0)

            NavigationStack {
                OversiktView(questionStore: questionStore)
            }
            .tint(.apOrange)
            .tabItem { Label("Översikt", systemImage: "square.grid.3x3") }
            .tag(1)
        }
        .tint(Color.apOrange)
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: selectedTab) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
