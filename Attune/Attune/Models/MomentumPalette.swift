//
//  MomentumPalette.swift
//  Attune
//
//  Central color palette for momentum-related UI (chart bars, legends).
//  Maps intention index → stable color. Shared for consistency across
//  Home momentum card and Momentum detail chart (future).
//

import SwiftUI

/// Fixed color palette for intentions in momentum charts.
/// Index-based: intention at index 0 gets colors[0], etc. Wraps if more intentions than colors.
struct MomentumPalette {

    /// Colors for up to ~8 intentions (teal, orange, purple, pink, etc.)
    static let intentionColors: [Color] = [
        Color(red: 0.2, green: 0.8, blue: 0.7),   // Teal (matches NeonPalette.neonTeal)
        Color(red: 0.95, green: 0.5, blue: 0.2),     // Orange
        Color(red: 0.6, green: 0.4, blue: 0.9),     // Purple
        Color(red: 0.95, green: 0.4, blue: 0.6),     // Pink
        Color(red: 0.3, green: 0.7, blue: 0.5),     // Green
        Color(red: 0.4, green: 0.6, blue: 0.95),    // Blue
        Color(red: 0.9, green: 0.7, blue: 0.2),     // Amber
        Color(red: 0.5, green: 0.85, blue: 0.7),    // Mint
    ]

    /// Returns color for intention at given index. Wraps around if index >= colors.count.
    static func color(forIndex index: Int) -> Color {
        let safeIndex = index % intentionColors.count
        return intentionColors[safeIndex]
    }

    // MARK: - Progress-based color (Day chart only)

    /// Returns color from progress percent (0–100+). Clamps >100 to 100 for mapping.
    /// 0%→red, 50%→yellow, 50%+→green. Bar fill comes from point.percent in the view (colorIndex unchanged).
    static func colorForProgress(_ pct: Double) -> Color {
        let t = min(pct / 100.0, 1.0) // Clamp for color mapping
        if t <= 0.5 {
            // 0.0–0.5: red → yellow
            let u = t / 0.5
            return Color(
                red: 0.95, // Red and yellow share same R
                green: 0.25 + u * 0.5, // 0.25 → 0.75
                blue: 0.2
            )
        } else {
            // 0.5–1.0: yellow → green
            let u = (t - 0.5) / 0.5
            return Color(
                red: 0.95 - u * 0.65, // 0.95 → 0.3
                green: 0.75 + u * 0.05, // 0.75 → 0.8
                blue: 0.2 + u * 0.2   // 0.2 → 0.4
            )
        }
    }
}
