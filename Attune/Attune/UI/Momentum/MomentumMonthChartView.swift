//
//  MomentumMonthChartView.swift
//  Attune
//
//  Monthly momentum chart: one aggregate bar per day of the month.
//

import SwiftUI // Import SwiftUI for drawing and layout.

/// Renders a month-long momentum chart with one aggregate bar per day.
struct MomentumMonthChartView: View { // View container for the month chart.
    let bars: [MonthDayBar] // Per-day aggregate data.
    
    var body: some View { // Main view body.
        ScrollView(.horizontal, showsIndicators: false) { // Horizontal scroll to fit 28–31 days.
            HStack(alignment: .bottom, spacing: 8) { // Stack bars along X-axis with bottom alignment.
                ForEach(bars) { bar in // Iterate each day bar.
                    VStack(spacing: 6) { // Stack bar and day label.
                        ZStack(alignment: .bottom) { // Container to align bar to bottom.
                            Rectangle() // Empty container to keep layout stable.
                                .fill(Color.clear) // Transparent fill.
                                .frame(width: 10, height: 80) // Fixed size for consistent heights.
                            
                            if let ratio = bar.ratio, let tier = bar.tier, !bar.isFutureDay { // Render only when data exists and not future.
                                let barHeight = max(6, CGFloat(ratio) * 80) // Scale height by ratio, ensure a minimal stub.
                                let barColor = colorForTier(tier) // Map tier to color.
                                
                                ZStack { // Draw glow + bar.
                                    RoundedRectangle(cornerRadius: 3, style: .continuous) // Glow shape.
                                        .fill(barColor) // Glow uses same hue.
                                        .blur(radius: 4) // Soft blur for glow.
                                        .opacity(0.45) // Subtle glow opacity.
                                    
                                    RoundedRectangle(cornerRadius: 3, style: .continuous) // Main bar shape.
                                        .fill(barColor) // Fill with tier color.
                                        .shadow(color: barColor.opacity(0.5), radius: 4, x: 0, y: 2) // Drop shadow for depth.
                                }
                                .frame(width: 10, height: barHeight) // Apply computed bar size.
                            }
                        }
                        
                        Text(dayNumber(for: bar.date)) // Day-of-month label.
                            .font(.system(size: 10, weight: .medium)) // Compact font.
                            .foregroundColor(.gray) // Subtle label color.
                    }
                }
            }
            .padding(.vertical, 8) // Vertical padding around bars.
            .padding(.horizontal, 4) // Horizontal padding for scroll edges.
        }
        .frame(height: 120) // Overall height for the month chart.
    }
    
    /// Convert date to day-of-month string.
    private func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter() // Formatter for day number.
        formatter.dateFormat = "d" // Day only (1–31).
        formatter.timeZone = TimeZone.current // Local timezone.
        return formatter.string(from: date) // Render string.
    }
    
    /// Map tier to color (mirrors weekly momentum palette).
    private func colorForTier(_ tier: MomentumTier) -> Color {
        switch tier { // Use tiers to pick colors.
        case .veryLow:
            return NeonPalette.moodLowRed // Red for very low.
        case .low:
            return NeonPalette.moodLowOrange // Orange for low.
        case .neutral:
            return Color.gray // Gray for neutral.
        case .good:
            return Color(red: 0.3, green: 0.7, blue: 0.5) // Greenish for good.
        case .great:
            return NeonPalette.neonTeal // Bright teal for great.
        }
    }
}

#Preview {
    MomentumMonthChartView(bars: []) // Preview with no data.
        .padding() // Add padding for preview framing.
}
