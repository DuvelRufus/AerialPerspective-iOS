//
//  AuthView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import SwiftUI

struct AuthView: View {
    var authStore: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Aerial Perspective")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Team assessment för PO:s")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }

                VStack(spacing: 12) {
                    TextField("E-post", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    SecureField("Lösenord", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isSignUp ? "Skapa konto" : "Logga in")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(isLoading)

                    Button(isSignUp ? "Har redan konto? Logga in" : "Inget konto? Skapa ett") {
                        isSignUp.toggle()
                        errorMessage = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 32)
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if isSignUp {
                try await authStore.signUp(email: email, password: password)
            } else {
                try await authStore.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
