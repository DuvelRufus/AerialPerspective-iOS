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
    static let apWaiting          = Color(hex: "#3B82F6")

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
    static var apWaiting:         Color { Color.apWaiting }
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

/// Full-screen background for main screens: the flat base color plus a warm
/// orange glow rising from the bottom edge, radial falloff to black so the
/// upper half stays effectively pure black (OLED/dark-first). Sheets keep
/// plain apBackground for modal contrast.
struct APAmbientBackground: View {
    var body: some View {
        ZStack {
            Color.apBackground
            RadialGradient(
                colors: [Color.apOrange.opacity(0.20), Color.apOrange.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 1.15),
                startRadius: 0,
                endRadius: 520
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

// MARK: - APGenerationLoadingView

/// Full-screen loading for the completion auto-generation pipeline: a
/// breathing orange orb (same glow language as GlowBurst/radar) over ONE
/// rolling status line at a time, drawn from `phrases` in random order and
/// reshuffled each cycle so repeats feel fresh. When `errorMessage` is set
/// the orb dims and retry/skip actions replace the rolling text — never a
/// dead end.
struct APGenerationLoadingView: View {
    var phrases: [String]
    var errorMessage: String? = nil
    var onRetry: () -> Void
    var onSkip: () -> Void

    @State private var shuffled: [String] = []
    @State private var index = 0
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 44) {
            orb
            if errorMessage != nil {
                errorContent
            } else {
                rollingText
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var orb: some View {
        ZStack {
            Circle()
                .fill(Color.apOrange.opacity(0.12))
                .frame(width: 160, height: 160)
                .blur(radius: 24)
                .scaleEffect(breathe ? 1.25 : 0.9)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.apOrange.opacity(0.55), Color.apOrange.opacity(0.05)],
                        center: .center,
                        startRadius: 4,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(breathe ? 1.1 : 0.92)
            Circle()
                .fill(LinearGradient.apOrangeGradient)
                .frame(width: 26, height: 26)
                .blur(radius: 1)
                .shadow(color: Color.apOrange.opacity(0.8), radius: breathe ? 22 : 10)
                .scaleEffect(breathe ? 1.15 : 0.9)
        }
        .opacity(errorMessage == nil ? 1 : 0.35)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var currentPhrase: String? {
        shuffled.isEmpty ? phrases.first : shuffled[index % shuffled.count]
    }

    private var rollingText: some View {
        ZStack {
            if let phrase = currentPhrase {
                Text(phrase)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.apTextSecondary)
                    .multilineTextAlignment(.center)
                    .id(index)
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .bottom),
                            removal: .push(from: .top)
                        )
                        .combined(with: .opacity)
                    )
            }
        }
        .frame(minHeight: 80, alignment: .top)
        .task {
            if shuffled.isEmpty { shuffled = phrases.shuffled() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { break }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    if index + 1 >= shuffled.count {
                        // New cycle: reshuffle, but never show the line we
                        // just left twice in a row across the seam.
                        var next = phrases.shuffled()
                        if next.count > 1, next.first == currentPhrase {
                            next.swapAt(0, 1)
                        }
                        shuffled = next
                        index = 0
                    } else {
                        index += 1
                    }
                }
            }
        }
    }

    private var errorContent: some View {
        VStack(spacing: 16) {
            Text("Genereringen misslyckades")
                .font(.headline)
                .foregroundStyle(.apTextPrimary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.apTextSecondary)
                    .multilineTextAlignment(.center)
            }
            APPillButton(title: "Försök igen", action: onRetry)
            APPillButton(title: "Visa resultat ändå", action: onSkip, style: .secondary)
        }
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

// MARK: - APSegmentedControl

/// Capsule pill selector (lifted from ProjectTabView so Översikt's
/// Team | Tasks lens shares it). Content-width pills; scrolls
/// horizontally if the segments ever don't fit.
struct APSegmentedControl: View {
    @Binding var selection: Int
    let options: [String]
    @Namespace private var ns

    var body: some View {
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

// MARK: - Score band colors

extension Color {
    /// THE level→color mapping (Resultat cards, Åtgärder domain headers,
    /// Plan domain tags) — one copy, no local twins. nil = no score → muted.
    static func apLevel(_ level: ScoreLevel?) -> Color {
        switch level {
        case .strong: return .apStrong
        case .note:   return .apNote
        case .risk:   return .apRisk
        case nil:     return .apTextTertiary
        }
    }

    /// Band color for a 0–100 score, thresholds owned by ScoringService.
    static func apScore(_ score: Int) -> Color {
        apLevel(ScoringService.level(for: score))
    }
}

// MARK: - Swipe Actions

/// One labeled, colored button revealed by apSwipeActions.
struct APSwipeAction {
    let title: String
    let systemImage: String
    let color: Color
    let handler: () -> Void
}

/// Reusable trailing swipe for rows in ScrollViews (no List, so native
/// .swipeActions is unavailable). Left-swipe reveals one or more labeled,
/// colored buttons with rubber-band resistance. Release past the open
/// threshold snaps OPEN — the swipe itself never commits an action, so a
/// destructive button always costs a deliberate tap. Parent-owned openId
/// keeps at most one row revealed per list.
///
/// The direction latch is deferred and three-state: while undecided it is
/// re-evaluated every sample (never decided once from the noisy activation
/// sample); decisively horizontal in the reveal direction latches active,
/// decisively vertical or wrong-direction latches dead for the touch, so
/// scrolling and the system back-swipe always fall through untouched.
struct APSwipeActionsModifier: ViewModifier {
    let id: UUID
    let enabled: Bool
    @Binding var openId: UUID?
    let actions: [APSwipeAction]

    /// Live finger translation; 0 when no drag is in flight.
    @State private var dragTranslation: CGFloat = 0
    /// nil = undecided, true = tracking this drag, false = dead this touch.
    @State private var latch: Bool? = nil

    private static let actionWidth: CGFloat = 72
    private static let actionSpacing: CGFloat = 4
    // 0.85 damping kills the overshoot tail (~0.6s at 0.7) that kept the
    // gesture arbiter busy after a swipe and delayed the next scroll pan;
    // 0.25 response keeps the snap quick. One small bounce survives.
    private static let snapSpring: Animation = .spring(response: 0.25, dampingFraction: 0.85)

    private var revealWidth: CGFloat {
        CGFloat(actions.count) * Self.actionWidth
            + CGFloat(max(0, actions.count - 1)) * Self.actionSpacing
    }
    private var openThreshold: CGFloat { revealWidth / 2 }

    private var isOpen: Bool { openId == id }

    /// Base position plus finger translation, clamped right at 0 and
    /// rubber-banded (excess ÷ 3) past the reveal width.
    private var currentOffset: CGFloat {
        let base: CGFloat = isOpen ? -revealWidth : 0
        var offset = base + dragTranslation
        if offset > 0 { offset = 0 }
        if offset < -revealWidth {
            offset = -revealWidth + (offset + revealWidth) / 3
        }
        return offset
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: Self.actionSpacing) {
                ForEach(actions.indices, id: \.self) { index in
                    actionButton(actions[index])
                }
            }
            .allowsHitTesting(isOpen)
            // Rows can be translucent, so occlusion can't hide the buttons:
            // mask them to the strip the row has vacated — invisible at
            // rest, revealed exactly where the row slid away.
            .mask(alignment: .trailing) {
                Rectangle()
                    .frame(width: max(0, -currentOffset))
            }

            content
                .overlay {
                    // Only while revealed: first tap snaps closed instead of
                    // triggering the row's own controls. Applied BEFORE
                    // .offset so it translates with the row.
                    if isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(Self.snapSpring) { openId = nil }
                            }
                    }
                }
                // The whole row rectangle is hit-testable for the drag —
                // without this, sparse content (a short title at the leading
                // edge) leaves transparent gaps that drop the swipe through
                // to the ScrollView.
                .contentShape(Rectangle())
                .offset(x: currentOffset)
                .gesture(drag)
        }
        .clipped()
        .animation(Self.snapSpring, value: openId)
    }

    private func actionButton(_ action: APSwipeAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(Self.snapSpring) { openId = nil }
            action.handler()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(action.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: Self.actionWidth)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(action.color))
        }
        .buttonStyle(.plain)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if latch == nil {
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) > abs(dy) * 1.5 {
                        // Decisively horizontal: claim only the reveal
                        // direction (leftward; either direction while open,
                        // so drag-to-close works) — a wrong-direction drag
                        // dies here and the system back-swipe keeps it.
                        latch = (dx < 0 || isOpen)
                    } else if abs(dy) > abs(dx) * 1.5 {
                        // Decisively vertical: the ScrollView owns it.
                        latch = false
                    }
                    // Ambiguous: stay undecided and re-evaluate next sample.
                }
                guard latch == true, enabled else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { _ in
                defer { latch = nil }
                guard latch == true, enabled else { return }
                let released = currentOffset
                withAnimation(Self.snapSpring) {
                    dragTranslation = 0
                    openId = released < -openThreshold ? id : nil
                }
            }
    }
}

extension View {
    func apSwipeActions(
        id: UUID,
        enabled: Bool = true,
        openId: Binding<UUID?>,
        actions: [APSwipeAction]
    ) -> some View {
        modifier(APSwipeActionsModifier(id: id, enabled: enabled, openId: openId, actions: actions))
    }
}
