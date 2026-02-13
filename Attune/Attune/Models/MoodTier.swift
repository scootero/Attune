//
//  MoodTier.swift
//  Attune
//
//  Maps numeric mood score (0-10) to discrete tier + display label.
//  Used for Home mood display and Record button halo. Slice A + B.
//

import Foundation
import SwiftUI

/// Discrete tier derived from mood score 0-10.
/// Used for consistent labeling and future tier-based UI (colors, etc.).
enum MoodTier: String {
    case veryLow
    case low
    case neutral
    case good
    case great
}

extension MoodTier {
    
    /// Maps mood score (0-10) to tier. Out-of-range scores are clamped.
    /// - 0-2 → veryLow
    /// - 3-4 → low
    /// - 5-6 → neutral
    /// - 7-8 → good
    /// - 9-10 → great
    static func moodTier(for score: Int) -> MoodTier {
        let clamped = min(10, max(0, score))
        switch clamped {
        case 0...2: return .veryLow
        case 3...4: return .low
        case 5...6: return .neutral
        case 7...8: return .good
        default: return .great
        }
    }
    
    /// Human-readable label for the tier. Optional display below Record button.
    static func moodLabel(for tier: MoodTier) -> String {
        switch tier {
        case .veryLow: return "Stressed"
        case .low: return "Low"
        case .neutral: return "Neutral"
        case .good: return "Good"
        case .great: return "Happy"
        }
    }
    
    /// Slice B: Color for Record button + halo. Positive tiers = teal/green; low = red/orange.
    static func colorForMoodTier(_ tier: MoodTier) -> Color {
        switch tier {
        case .veryLow: return Color(red: 0.9, green: 0.25, blue: 0.2)
        case .low: return Color(red: 0.95, green: 0.5, blue: 0.2)
        case .neutral: return Color(red: 0.9, green: 0.75, blue: 0.2)
        case .good: return Color(red: 0.2, green: 0.75, blue: 0.6)
        case .great: return Color(red: 0.15, green: 0.85, blue: 0.6)
        }
    }
}
