//
//  AuthView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import UIKit
import SwiftUI

private enum AuthField {
    case email, password
}

struct AuthView: View {
    var authStore: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var orbPulsing = false
    @State private var appeared = false
    @FocusState private var focusedField: AuthField?

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            // Animated glowing orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.apOrange.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 210
                    )
                )
                .frame(width: 420, height: 420)
                .scaleEffect(orbPulsing ? 1.20 : 0.80)
                .blur(radius: 45)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: 80)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: orbPulsing)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Text("AP")
                        .font(.system(size: 64, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(.apTextPrimary)
                    VStack(spacing: 6) {
                        Text("Aerial Perspective")
                            .font(.title3)
                            .foregroundStyle(.apTextSecondary)
                        Text("Team assessment för Product Owners and Project Managers")
                            .font(.subheadline)
                            .foregroundStyle(.apTextTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

                Spacer().frame(height: 48)

                // Form
                VStack(spacing: 16) {
                    fieldView(
                        placeholder: "E-post",
                        text: $email,
                        field: .email,
                        secure: false
                    )
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    fieldView(
                        placeholder: "Lösenord",
                        text: $password,
                        field: .password,
                        secure: true
                    )
                    .textContentType(isSignUp ? .newPassword : .password)

                    if let success = successMessage {
                        Text(success)
                            .font(.caption)
                            .foregroundStyle(Color.apStrong)
                            .multilineTextAlignment(.center)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.apRisk)
                            .multilineTextAlignment(.center)
                    }

                    LoadingPillButton(
                        title: isSignUp ? "Skapa konto" : "Logga in",
                        isLoading: isLoading
                    ) {
                        Task { await submit() }
                    }

                    Button(isSignUp ? "Har redan konto? Logga in" : "Inget konto? Skapa ett") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isSignUp.toggle()
                        errorMessage = nil
                        successMessage = nil
                    }
                    .font(.subheadline)
                    .foregroundStyle(.apTextTertiary)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .offset(y: appeared ? 0 : 30)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appeared)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appeared = true
            orbPulsing = true
        }
    }

    @ViewBuilder
    private func fieldView(
        placeholder: String,
        text: Binding<String>,
        field: AuthField,
        secure: Bool
    ) -> some View {
        let isFocused = focusedField == field
        ZStack {
            Capsule()
                .fill(Color.apSurface)
            Capsule()
                .strokeBorder(
                    isFocused ? Color.apOrange : Color.white.opacity(0.06),
                    lineWidth: 1
                )
                .animation(.easeInOut(duration: 0.2), value: isFocused)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .foregroundStyle(Color.apTextPrimary)
            .padding(.horizontal, 20)
            .focused($focusedField, equals: field)
        }
        .frame(height: 52)
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        defer { isLoading = false }
        do {
            if isSignUp {
                try await authStore.signUp(email: email, password: password)
                successMessage = "Konto skapat!"
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    successMessage = "Kolla din e-post för att bekräfta kontot"
                }
            } else {
                try await authStore.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoadingPillButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                Rectangle().fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: "#FF8C42"), location: 0),
                            .init(color: Color(hex: "#F97316"), location: 0.5),
                            .init(color: Color(hex: "#C2410C"), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay(alignment: .top) {
                if !isLoading {
                    LinearGradient(
                        colors: [Color.white.opacity(0.125), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 27)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(Capsule())
        }
        .disabled(isLoading)
    }
}

