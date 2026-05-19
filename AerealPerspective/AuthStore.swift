//
//  AuthStore.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import Supabase

@MainActor
@Observable
class AuthStore {
    var user: User? = nil
    var isLoading = true

    init() {
        Task { await listenToAuth() }
    }

    private func listenToAuth() async {
        for await (_, session) in supabase.auth.authStateChanges {
            self.user = session?.user
            self.isLoading = false
        }
    }

    func signUp(email: String, password: String) async throws {
        try await supabase.auth.signUp(email: email, password: password)
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }
}
