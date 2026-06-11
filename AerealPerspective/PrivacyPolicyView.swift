//
//  PrivacyPolicyView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-30.
//

import SwiftUI

struct PrivacyPolicyView: View {
    let onAccept: () -> Void

    private let policyText = """
Senast uppdaterad: juni 2026

VAD VI SAMLAR IN
E-postadress för inloggning.
Projektnamn, assessmentsvar samt
AI-genererade insikter och planer.

VAR DATA LAGRAS
Supabase (EU-region). Din data
är åtkomlig endast för dig via
autentiserad inloggning.

TREDJEPARTSTJÄNSTER
Anonymiserade assessmentsvar och
domänpoäng skickas till Anthropic
API för att generera insikter och
30-60-90-planer. Ingen annan
tredjepartsdelning förekommer.

ANNONSERING
Ingen.

RADERING
Skicka en förfrågan till
aerialapp@icloud.com för permanent
radering av ditt konto och
all associerad data.

KONTAKT
aerialapp@icloud.com
"""

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AERIAL PERSPECTIVE")
                            .font(.caption.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(.apTextSecondary)

                        Text("Integritetspolicy")
                            .font(.title2.bold())
                            .foregroundStyle(.apTextPrimary)
                    }

                    Text(policyText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.apTextSecondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.apSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom) {
            APPillButton(title: "Fortsätt") {
                onAccept()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.apBackground)
        }
    }
}
