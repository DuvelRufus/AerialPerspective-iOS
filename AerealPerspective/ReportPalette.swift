//
//  ReportPalette.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-10-06.
//

import SwiftUI

/// The PDF report's own light palette — paper, not the app's dark theme.
/// Every foreground color is at least 4.5:1 (WCAG AA) against white.
enum ReportPalette {
    static let background    = Color.white
    static let surface       = Color(hex: "#F5F5F4")
    static let hairline      = Color(hex: "#D6D3D1")

    static let textPrimary   = Color(hex: "#1C1917")   // 17.5:1
    static let textSecondary = Color(hex: "#57534E")   // 7.6:1
    static let textTertiary  = Color(hex: "#78716C")   // 4.8:1
    static let accent        = Color(hex: "#C2410C")   // 5.2:1

    static let risk          = Color(hex: "#B91C1C")   // 6.5:1
    static let note          = Color(hex: "#B45309")   // 5.0:1
    static let strong        = Color(hex: "#15803D")   // 5.0:1

    /// Radar: the first assessment muted, the latest in the accent.
    static let radarFirst    = textSecondary
    static let radarLatest   = accent
    static let radarGrid     = hairline

    /// Trend chart lines, one per Domain.allCases (total is textPrimary).
    static let series: [Color] = [
        Color(hex: "#2563EB"),   // 5.2:1
        Color(hex: "#0F766E"),   // 5.5:1
        Color(hex: "#C2410C"),   // 5.2:1
        Color(hex: "#7C3AED"),   // 5.7:1
        Color(hex: "#BE185D"),   // 6.0:1
        Color(hex: "#4D7C0F"),   // 5.0:1
    ]

    /// Mirrors Color.apLevel; nil = no score → muted.
    static func level(_ level: ScoreLevel?) -> Color {
        switch level {
        case .strong: return strong
        case .note:   return note
        case .risk:   return risk
        case nil:     return textTertiary
        }
    }
}
