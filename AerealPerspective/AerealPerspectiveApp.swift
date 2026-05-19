//
//  AerealPerspectiveApp.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import SwiftUI

@main
struct AerealPerspectiveApp: App {
    @State private var authStore = AuthStore()
    @State private var questionStore = QuestionStore()

    var body: some Scene {
        WindowGroup {
            if authStore.isLoading {
                ProgressView()
            } else if authStore.user == nil {
                AuthView(authStore: authStore)
            } else {
                ProjectListView(
                    authStore: authStore,
                    questionStore: questionStore
                )
                .task { await questionStore.fetch() }
            }
        }
    }
}
