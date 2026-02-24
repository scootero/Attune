//
//  MomentumWeekChartView.swift
//  Attune
//
//  Weekly momentum chart: 7 day columns, multiple bars per day (one per intention).
//

import SwiftUI // Import SwiftUI for drawing and layout.

/// Renders a 7-day momentum chart with multiple intention bars per day.
struct MomentumWeekChartView: View { // View container for the weekly chart.
    let days: [WeekDayChartData] // Input data: per-day columns with intention bars.
    let yAxisMax: Double // Axis cap (100 or 150) to scale bar heights.
    
    var body: some View { // Main view body.
        GeometryReader { geometry in // Use geometry to adapt to available size.
            Canvas { context, size in // Draw custom shapes in a Canvas.
                let leftPadding: CGFloat = 24 // Space for Y-axis ticks/labels (minimal).
                let bottomPadding: CGFloat = 26 // Space for day labels.
                let chartWidth = size.width - leftPadding // Usable width for columns.
                let chartHeight = size.height - bottomPadding // Usable height for bars.
                let dayCount = max(days.count, 1) // Prevent divide-by-zero when no data.
                let dayWidth = chartWidth / CGFloat(dayCount) // Width per day column.
                let gridLineCount = 5 // Number of subtle horizontal guide lines behind bars.
                let perspectiveLineCount = 6 // Number of faint vertical perspective guides.
                
                // Draw distant horizontal grid lines behind bars.
                for lineIndex in 0...gridLineCount { // Iterate from baseline to top guide.
                    let ratio = CGFloat(lineIndex) / CGFloat(gridLineCount) // Normalize the current guide position.
                    let y = chartHeight - (ratio * chartHeight) // Convert normalized position into canvas y-space.
                    var horizontalGuide = Path() // Build a path for this horizontal guide.
                    horizontalGuide.move(to: CGPoint(x: leftPadding, y: y)) // Start at the left edge of the chart area.
                    horizontalGuide.addLine(to: CGPoint(x: size.width, y: y)) // End at the right edge of the chart area.
                    let guideOpacity = 0.035 + Double(ratio) * 0.035 // Fade guides slightly stronger toward the top for depth.
                    context.stroke( // Stroke this guide with a dashed, low-contrast style.
                        horizontalGuide, // Path for the horizontal guide line.
                        with: .color(Color.white.opacity(guideOpacity)), // Very subtle white tint.
                        style: StrokeStyle(lineWidth: 0.6, lineCap: .round, dash: [2.5, 3.5]) // Light dashed treatment for a distant look.
                    )
                }
                
                // Draw faint perspective lines that converge upward to suggest distance.
                for lineIndex in 0...perspectiveLineCount { // Iterate across the chart width.
                    let ratio = CGFloat(lineIndex) / CGFloat(perspectiveLineCount) // Normalize horizontal guide placement.
                    let startX = leftPadding + (ratio * chartWidth) // Evenly distribute start points on baseline.
                    let endX = leftPadding + (chartWidth * 0.5) + ((ratio - 0.5) * chartWidth * 0.32) // Pull endpoints inward to mimic perspective convergence.
                    var perspectiveGuide = Path() // Build a path for this perspective line.
                    perspectiveGuide.move(to: CGPoint(x: startX, y: chartHeight)) // Start at baseline.
                    perspectiveGuide.addLine(to: CGPoint(x: endX, y: 4)) // End near the top, inside the chart area.
                    context.stroke( // Stroke each perspective line subtly.
                        perspectiveGuide, // Path for the perspective guide.
                        with: .color(Color.white.opacity(0.03)), // Very low opacity to avoid distracting from bars.
                        style: StrokeStyle(lineWidth: 0.5) // Thin line for background-only effect.
                    )
                }
                
                // Draw horizontal baseline
                var baseline = Path() // Path for baseline.
                baseline.move(to: CGPoint(x: leftPadding, y: chartHeight)) // Start at left-bottom.
                baseline.addLine(to: CGPoint(x: size.width, y: chartHeight)) // Extend to right-bottom.
                context.stroke(baseline, with: .color(Color.white.opacity(0.15)), lineWidth: 0.5) // Subtle baseline stroke.
                
                // Draw day labels under each column
                for (idx, day) in days.enumerated() { // Iterate day columns.
                    let dayLeft = leftPadding + (CGFloat(idx) * dayWidth) // Left edge of this column.
                    let labelX = dayLeft + (dayWidth / 2) // Center label under column.
                    let labelY = chartHeight + 6 // Position label just below baseline.
                    var textContext = context // Create text drawing context.
                    textContext.translateBy(x: labelX, y: labelY) // Move to label position.
                    textContext.draw( // Draw weekday letter.
                        Text(day.weekdayLetter) // Use single-letter label.
                            .font(.system(size: 11, weight: .medium)) // Compact font for labels.
                            .foregroundColor(.gray), // Subtle color.
                        at: .zero, // Draw at translated origin.
                        anchor: .center // Center align text.
                    )
                }
                
                // Draw bars for each day/intentions
                for (idx, day) in days.enumerated() { // Iterate day columns.
                    let dayLeft = leftPadding + (CGFloat(idx) * dayWidth) // Left boundary for this column.
                    let innerWidth = dayWidth * 0.6 // Inner width for slotting bars with padding.
                    let innerOffset = (dayWidth - innerWidth) / 2 // Center inner area within column.
                    let barWidth = max(8, innerWidth * 0.22) // Bar width scaled to inner area with a minimum for visibility.
                    let barDepth = min(max(2.5, barWidth * 0.34), 7) // Horizontal extrusion depth for 3D right face.
                    let topRise = barDepth * 0.58 // Vertical rise of the back edge for top-face perspective.
                    
                    for bar in day.bars { // Iterate bars within this day.
                        let clamped = min(bar.percent, yAxisMax) // Clamp percent to axis max.
                        let heightRatio = CGFloat(clamped / yAxisMax) // Normalize height ratio.
                        let barHeight = heightRatio * chartHeight // Actual bar height in pixels.
                        let xCenter = dayLeft + innerOffset + CGFloat(bar.slot) * innerWidth // Slot position across inner width.
                        let x = xCenter - (barWidth / 2) // Left x for rectangle.
                        let y = chartHeight - barHeight // Top y (bars grow upward from baseline).
                        
                        var frontFace = Path() // Path for the front face rectangle.
                        frontFace.addRect(CGRect(x: x, y: y, width: barWidth, height: barHeight)) // Define front face geometry.
                        
                        var topFace = Path() // Path for the top face polygon.
                        topFace.move(to: CGPoint(x: x, y: y)) // Front-left top corner.
                        topFace.addLine(to: CGPoint(x: x + barDepth, y: y - topRise)) // Back-left top corner.
                        topFace.addLine(to: CGPoint(x: x + barWidth + barDepth, y: y - topRise)) // Back-right top corner.
                        topFace.addLine(to: CGPoint(x: x + barWidth, y: y)) // Front-right top corner.
                        topFace.closeSubpath() // Close top face polygon.
                        
                        var sideFace = Path() // Path for the right side face polygon.
                        sideFace.move(to: CGPoint(x: x + barWidth, y: y)) // Front-right top corner.
                        sideFace.addLine(to: CGPoint(x: x + barWidth + barDepth, y: y - topRise)) // Back-right top corner.
                        sideFace.addLine(to: CGPoint(x: x + barWidth + barDepth, y: chartHeight - topRise)) // Back-right bottom corner.
                        sideFace.addLine(to: CGPoint(x: x + barWidth, y: chartHeight)) // Front-right bottom corner.
                        sideFace.closeSubpath() // Close right side polygon.
                        
                        let color = MomentumPalette.color(forIndex: bar.colorIndex) // Fetch palette color for intention.
                        let frontTop = color.opacity(0.98) // Slightly brighter tone for upper front-face shading.
                        let frontBottom = color.opacity(0.74) // Darker tone for lower front-face shading.
                        let sideShade = color.opacity(0.56) // Darker side to reinforce 3D depth.
                        let topShade = color.opacity(0.9) // Slightly brighter top face for light hit.
                        
                        context.fill( // Fill front face with a subtle vertical gradient.
                            frontFace, // Front rectangle path.
                            with: .linearGradient( // Use linear gradient to emulate realistic light falloff.
                                Gradient(colors: [frontTop, frontBottom]), // Brighter top, darker bottom.
                                startPoint: CGPoint(x: x, y: y), // Gradient starts at bar top.
                                endPoint: CGPoint(x: x, y: chartHeight) // Gradient ends at baseline.
                            )
                        )
                        context.fill(topFace, with: .color(topShade)) // Fill top face with brighter solid tint.
                        context.fill(sideFace, with: .color(sideShade)) // Fill right side with darker solid tint.
                        
                        context.stroke(topFace, with: .color(Color.white.opacity(0.15)), lineWidth: 0.7) // Add a light edge highlight on top face.
                        context.stroke(sideFace, with: .color(Color.black.opacity(0.2)), lineWidth: 0.7) // Add a darker side edge for separation.
                        
                        // Add a small shadow/glow for depth
                        context.drawLayer { layer in // Draw shadow in separate layer.
                            layer.addFilter(.shadow(color: color.opacity(0.5), radius: 4, x: 0, y: 2)) // Soft glow/shadow.
                            layer.fill(frontFace, with: .color(color.opacity(0.9))) // Refill front face softly inside shadow layer.
                        }
                    }
                }
            }
        }
        .frame(height: 220) // Match height of day chart for consistency.
    }
}

#Preview {
    MomentumWeekChartView(days: [], yAxisMax: 100) // Preview with empty data.
        .padding() // Add padding for preview framing.
}
