//
//  DesignSystem.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-19.
//

import Foundation
import UIKit
import SwiftUI

// MARK: - Color palette

extension Color {
    // Backgrounds
    static let apBackground       = Color(hex: "#0F0E0C")
    static let apSurface          = Color(hex: "#232019")
    static let apSurfaceElevated  = Color(hex: "#332F2A")

    // Orange accent
    static let apOrange           = Color(hex: "#F97316")
    static let apOrangePressed    = Color(hex: "#EA6B0A")
    static let apOrangeTint       = Color(hex: "#431407")

    // Text
    static let apTextPrimary      = Color(hex: "#F2EDE4")
    static let apTextSecondary    = Color(hex: "#ABA193")
    static let apTextTertiary     = Color(hex: "#837A6F")

    // Semantic
    static let apRisk             = Color(hex: "#EF4444")
    static let apNote             = Color(hex: "#F59E0B")
    static let apStrong           = Color(hex: "#22C55E")

    // Borders & dividers
    static let apHairline         = Color.white.opacity(0.08)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// Enables .foregroundStyle(.apOrange) shorthand (mirrors how SwiftUI exposes .red, .blue, etc.)
extension ShapeStyle where Self == Color {
    static var apBackground:      Color { Color.apBackground }
    static var apSurface:         Color { Color.apSurface }
    static var apSurfaceElevated: Color { Color.apSurfaceElevated }
    static var apOrange:          Color { Color.apOrange }
    static var apOrangePressed:   Color { Color.apOrangePressed }
    static var apOrangeTint:      Color { Color.apOrangeTint }
    static var apTextPrimary:     Color { Color.apTextPrimary }
    static var apTextSecondary:   Color { Color.apTextSecondary }
    static var apTextTertiary:    Color { Color.apTextTertiary }
    static var apRisk:            Color { Color.apRisk }
    static var apNote:            Color { Color.apNote }
    static var apStrong:          Color { Color.apStrong }
    static var apHairline:        Color { Color.apHairline }
}

// MARK: - Gradients

extension LinearGradient {
    static let apOrangeGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#FF8C42"), location: 0),
            .init(color: Color(hex: "#F97316"), location: 0.5),
            .init(color: Color(hex: "#C2410C"), location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - APAmbientBackground

/// Full-screen background for main screens: the flat base color plus a
/// barely-there orange glow bleeding down from the top, so screens read as
/// lit rather than flat. Sheets keep plain apBackground for modal contrast.
struct APAmbientBackground: View {
    var body: some View {
        ZStack {
            Color.apBackground
            RadialGradient(
                colors: [Color.apOrange.opacity(0.09), .clear],
                center: UnitPoint(x: 0.5, y: -0.2),
                startRadius: 0,
                endRadius: 450
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - APPillButton

enum APPillButtonStyle {
    case primary, secondary, destructive
}

private struct APButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Press feedback for navigating list rows. Reads isPressed only — no gestures,
// so it cannot swallow NavigationLink taps (List rows broke with simultaneousGesture).
struct APRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .shadow(color: configuration.isPressed ? Color.apOrange.opacity(0.25) : .clear, radius: 10)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct APPillButton: View {
    let title: String
    let action: () -> Void
    var style: APPillButtonStyle = .primary
    var isLoading: Bool = false
    var haptic: UIImpactFeedbackGenerator.FeedbackStyle = .medium

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(labelColor)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background { Rectangle().fill(background) }
            .overlay(alignment: .top) {
                if style == .primary && !isLoading {
                    LinearGradient(
                        colors: [Color.white.opacity(0.125), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 27)
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(APButtonPressStyle())
        .disabled(isLoading)
        .haptic(haptic)
    }

    private var labelColor: Color {
        switch style {
        case .primary:     return .white
        case .secondary:   return .apTextPrimary
        case .destructive: return .white
        }
    }

    private var background: AnyShapeStyle {
        switch style {
        case .primary:
            return AnyShapeStyle(LinearGradient.apOrangeGradient)
        case .secondary:
            return AnyShapeStyle(Color.apSurfaceElevated)
        case .destructive:
            return AnyShapeStyle(Color.apRisk)
        }
    }

    private var borderColor: Color {
        style == .secondary ? Color.apHairline : .clear
    }

    private var borderWidth: CGFloat {
        style == .secondary ? 1 : 0
    }
}

// MARK: - APCard

struct APCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.apHairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - APScorePill

struct APScorePill: View {
    let score: Int
    let level: ScoreLevel
    var label: String? = nil

    var body: some View {
        Text(label ?? "\(score)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(textColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var textColor: Color {
        switch level {
        case .risk:   return .apRisk
        case .note:   return .apNote
        case .strong: return .apStrong
        }
    }
}

// MARK: - APSectionHeader

struct APSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption)
            .tracking(1.5)
            .foregroundStyle(Color.apTextSecondary)
    }
}

// MARK: - Shimmer

// Sweeps a soft highlight band across the modified view's glyphs (masked to
// the content, so it never spills outside text).
private struct APShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.65), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

extension View {
    func apShimmer() -> some View {
        modifier(APShimmerModifier())
    }
}

// MARK: - APGeneratingState

/// Loading state for AI generation: a pulsing sparkles icon over status
/// phrases that cycle with a shimmer, so the wait reads as deliberate work.
struct APGeneratingState: View {
    var phrases: [String]
    var interval: Double = 1.8

    @State private var index = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.apOrange)
                .symbolEffect(.pulse)
            ZStack {
                Text(phrases[index % max(phrases.count, 1)])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.apTextSecondary)
                    .apShimmer()
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))
            }
            .frame(height: 22)
            .clipped()
        }
        .task {
            guard phrases.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                withAnimation(.easeInOut(duration: 0.4)) { index += 1 }
            }
        }
    }
}

// MARK: - APErrorState

struct APErrorState: View {
    var message: String = "Något gick fel. Kontrollera din anslutning."
    var retryTitle: String = "Försök igen"
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.apOrange)
            Text("Kunde inte ladda")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.apTextSecondary)
                .multilineTextAlignment(.center)
            APPillButton(title: retryTitle) { onRetry() }
                .padding(.horizontal, 40)
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Haptic Modifier

struct HapticModifier: ViewModifier {
    var style: UIImpactFeedbackGenerator.FeedbackStyle = .light

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: style).impactOccurred()
                }
            )
    }
}

extension View {
    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) -> some View {
        modifier(HapticModifier(style: style))
    }
}

// MARK: - Minimum Tap Target
struct MinTapTargetModifier: ViewModifier {
    var minSize: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
    }
}

extension View {
    func minTapTarget(_ size: CGFloat = 44) -> some View {
        modifier(MinTapTargetModifier(minSize: size))
    }
}
