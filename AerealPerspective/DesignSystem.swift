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
    /// Pågår (TaskState.doing) — distinct from waiting blue and prio orange.
    static let apDoing            = Color(hex: "#8B5CF6")

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
    static var apDoing:           Color { Color.apDoing }
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
    /// 0 för rader/celler som äger sin egen padding eller har full-bleed-
    /// innehåll (dividers, accent-bars); default 16 för fristående kort.
    var padding: CGFloat
    let content: () -> Content

    init(padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.apSurface)
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

// MARK: - Avatar palette

/// De 8 kurerade avatarfärgerna. Färgväljaren (Resources delsteg 4) skriver
/// vald hex till contacts.avatar_color; kontakter utan vald färg får
/// hash-fallbacken.
enum AvatarPalette {
    static let hexes = ["#6B5DD3", "#2A9D8F", "#E76F51", "#4A8FBD",
                        "#E9A23B", "#C05780", "#5B8C5A", "#8A7A9B"]

    /// Deterministisk: samma namn → samma färg, stabilt mellan renders OCH
    /// appstarter. Swifts hashValue är seedad per process och duger inte —
    /// därför egen stabil hash över unicode-skalärerna.
    static func fallbackHex(for name: String) -> String {
        let h = name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
        return hexes[abs(h) % hexes.count]
    }
}

// MARK: - InitialsAvatar

/// Variant C: mörk kärna (färgen mörkad ~85 %), 2 px färgad ring, initialer
/// i färgen ljusad ~35 % för kontrast mot kärnan.
struct InitialsAvatar: View {
    let name: String
    let colorHex: String?
    var size: CGFloat = 32

    var body: some View {
        let rgb = Self.rgb(from: colorHex ?? AvatarPalette.fallbackHex(for: name))
        let core = Color(.sRGB, red: rgb.r * 0.15, green: rgb.g * 0.15, blue: rgb.b * 0.15)
        let ring = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
        let text = Color(.sRGB, red: rgb.r + (1 - rgb.r) * 0.35,
                         green: rgb.g + (1 - rgb.g) * 0.35,
                         blue: rgb.b + (1 - rgb.b) * 0.35)
        ZStack {
            Circle().fill(core)
            Circle().strokeBorder(ring, lineWidth: 2)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(text)
        }
        .frame(width: size, height: size)
    }

    /// Första bokstaven i upp till två namndelar; tomt namn → "?".
    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "?" : String(parts).uppercased()
    }

    /// Hex → (r,g,b) 0–1, samma Scanner-idiom som Color(hex:).
    /// Ogiltig hex → neutral grå så inget kraschar.
    private static func rgb(from hex: String) -> (r: Double, g: Double, b: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&int) else {
            return (0.5, 0.5, 0.5)
        }
        return (Double(int >> 16 & 0xFF) / 255,
                Double(int >> 8 & 0xFF) / 255,
                Double(int & 0xFF) / 255)
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

// MARK: - APGenerationSteps

/// The real steps of a generation pipeline and where it is right now. The
/// caller moves `begin(_:)` only at actual code boundaries (fetch, edge
/// call, insert) — never on a timer — so the list never claims progress
/// that hasn't happened.
struct APGenerationSteps: Equatable {
    private(set) var titles: [String]
    private(set) var index = 0
    private(set) var failed = false

    init(_ titles: [String]) {
        self.titles = titles
    }

    var total: Int { titles.count }
    var current: String? { titles.indices.contains(index) ? titles[index] : nil }

    /// Makes `title` the active step; everything before it reads as done.
    mutating func begin(_ title: String) {
        guard let i = titles.firstIndex(of: title) else { return }
        index = i
        failed = false
    }

    /// Marks the active step as the one that failed.
    mutating func fail() {
        failed = true
    }
}

// MARK: - APGenerationStepsView

/// Loading state for AI generation: a vertical list of the pipeline's real
/// steps — done (check), active (filled marker), upcoming (dimmed). Moves
/// only when `steps` moves; nothing loops. When `errorMessage` is set the
/// failed step is marked and retry/skip actions follow the list — never a
/// dead end.
struct APGenerationStepsView: View {
    var steps: APGenerationSteps
    var errorMessage: String? = nil
    var onRetry: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum RowState {
        case done, active, upcoming, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(steps.titles.enumerated()), id: \.element) { i, title in
                    row(title, index: i, state: state(at: i))
                }
            }
            if errorMessage != nil {
                errorContent
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85),
            value: steps
        )
        .onChange(of: announcement) { _, new in
            guard let new else { return }
            AccessibilityNotification.Announcement(new).post()
        }
    }

    private func state(at i: Int) -> RowState {
        if i < steps.index { return .done }
        if i > steps.index { return .upcoming }
        return steps.failed ? .failed : .active
    }

    /// Spoken on every step change (and on failure) — the list moving is
    /// otherwise silent to VoiceOver.
    private var announcement: String? {
        guard let current = steps.current else { return nil }
        return steps.failed ? "Misslyckades: \(current)" : current
    }

    private func row(_ title: String, index i: Int, state: RowState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            marker(state)
                .frame(width: 20)
                .id(state)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            Text(title)
                .font(.subheadline.weight(state == .active || state == .failed ? .semibold : .regular))
                .foregroundStyle(textColor(state))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(title, index: i, state: state))
    }

    @ViewBuilder
    private func marker(_ state: RowState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.apStrong)
        case .active:
            // Static glow: it marks what is happening now, so it doesn't pulse.
            Circle()
                .fill(Color.apOrange)
                .frame(width: 10, height: 10)
                .shadow(color: Color.apOrange.opacity(0.8), radius: 6)
        case .upcoming:
            Circle()
                .strokeBorder(Color.apTextTertiary, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.apRisk)
        }
    }

    private func textColor(_ state: RowState) -> Color {
        switch state {
        case .done:     return .apTextSecondary
        case .active:   return .apTextPrimary
        case .upcoming: return .apTextTertiary
        case .failed:   return .apRisk
        }
    }

    private func accessibilityLabel(_ title: String, index i: Int, state: RowState) -> String {
        let position = "steg \(i + 1) av \(steps.total)"
        switch state {
        case .done:     return "Klart: \(title), \(position)"
        case .active:   return "Pågår: \(title), \(position)"
        case .upcoming: return "Kommande: \(title), \(position)"
        case .failed:   return "Misslyckades: \(title), \(position)"
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
            if let onRetry {
                APPillButton(title: "Försök igen", action: onRetry)
            }
            if let onSkip {
                APPillButton(title: "Visa resultat ändå", action: onSkip, style: .secondary)
            }
        }
        .frame(maxWidth: .infinity)
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
