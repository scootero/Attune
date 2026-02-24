//
//  MomentumChartView.swift
//  Attune
//
//  Chart card for Momentum detail page: bars showing % accomplished per intention
//  at check-in times. Uses Swift Charts. Bars at same time overlap with small offsets.
//

import SwiftUI
import Charts

/// Chart view: X = time of day, Y = % accomplished. Supports >100% with expanded axis.
struct MomentumChartView: View {

    /// Data points for the selected day
    let points: [MomentumPoint]

    /// Y-axis max (100 or 150 when any point exceeds 100%)
    let yAxisMax: Double

    /// Selected date (start of day local) for X-axis domain 00:00–23:59
    let selectedDate: Date

    var body: some View {
        let _ = logChartReceive() // Debug: emit chart input summary when body evaluates
        VStack(alignment: .center, spacing: 16) { // Center alignment for the entire card content
            // Chart area
            if points.isEmpty {
                // Empty state when no check-ins or no progress
                emptyChartView
            } else {
                chartContent
            }

            // Legend hidden: bars now use progress-based color (red→yellow→green), so intention-color legend would be misleading
        }
        .padding(16)
        .glassCard()
    }

    /// 3D Chart with perspective view from upper left corner. Bars have 6px depth, grid lines are 3D.
    private var chartContent: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // 3D perspective settings: viewing from upper left corner
                let depthOffset: CGFloat = 60 // Increase depth 10x so grid lines and bars project much further back into space for a stronger 3D effect.
                let perspectiveAngle: CGFloat = 0.32 // Slightly steeper angle so the extended depth remains visible without flattening.
                
                // Calculate chart dimensions with padding for axes
                let leftPadding: CGFloat = 40 // Space for Y-axis labels
                let bottomPadding: CGFloat = 30 // Space for X-axis labels
                let chartWidth = size.width - leftPadding - 20
                let chartHeight = size.height - bottomPadding - 10
                
                // Draw 3D grid lines (behind bars) with depth perspective
                drawGridLines3D(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding, depthOffset: depthOffset, perspectiveAngle: perspectiveAngle)
                
                // Draw Y-axis labels
                drawYAxisLabels(context: context, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding)
                
                // Draw X-axis labels
                drawXAxisLabels(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding)
                
                // Draw 3D bars with depth
                draw3DBars(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding, depthOffset: depthOffset, perspectiveAngle: perspectiveAngle)
            }
            .frame(height: 220)
        }
        .frame(height: 220)
    }
    
    /// Draws 3D grid lines with depth perspective (looking from upper left corner)
    private func drawGridLines3D(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat, depthOffset: CGFloat, perspectiveAngle: CGFloat) {
        let gridColor = Color.white.opacity(0.15) // Subtle grid lines
        let depthGridColor = Color.white.opacity(0.08) // Even more subtle for depth lines
        let depthFadeSteps = 3 // Number of trailing depth layers to draw so lines fade as they recede.
        let depthFadeScale: CGFloat = 0.5 // Opacity multiplier per step to create a fading effect on each successive depth layer.
        
        // Draw horizontal grid lines (Y-axis) with 3D depth
        let ySteps = Int(yAxisMax / 50) + 1 // Grid lines every 50%
        for i in 0...ySteps {
            let yValue = Double(i) * 50.0
            if yValue <= yAxisMax {
                let yPos = chartHeight - (CGFloat(yValue / yAxisMax) * chartHeight) + 10
                
                // Front grid line (main line)
                var frontPath = Path()
                frontPath.move(to: CGPoint(x: leftPadding, y: yPos))
                frontPath.addLine(to: CGPoint(x: leftPadding + chartWidth, y: yPos))
                context.stroke(frontPath, with: .color(gridColor), lineWidth: 0.5)
                
                // Back grid line (depth line, offset to show 3D space)
                var backPath = Path()
                let backYOffset = -depthOffset * perspectiveAngle // Offset upward for upper-left perspective
                let backXOffset = -depthOffset // Offset left for depth
                backPath.move(to: CGPoint(x: leftPadding + backXOffset, y: yPos + backYOffset))
                backPath.addLine(to: CGPoint(x: leftPadding + chartWidth + backXOffset, y: yPos + backYOffset))
                context.stroke(backPath, with: .color(depthGridColor), lineWidth: 0.5)
                
                // Connect front to back (left side connector)
                var connectorPath = Path()
                connectorPath.move(to: CGPoint(x: leftPadding, y: yPos))
                connectorPath.addLine(to: CGPoint(x: leftPadding + backXOffset, y: yPos + backYOffset))
                context.stroke(connectorPath, with: .color(depthGridColor), lineWidth: 0.5)
                
                for step in 1...depthFadeSteps { // Draw additional receding lines so the grid appears to stretch further back.
                    let fadeFactor = pow(depthFadeScale, CGFloat(step)) // Reduce opacity for each step to create a fading trail.
                    let stepOffset = CGFloat(step + 1) // Incremental multiplier to push each line farther into depth.
                    let stepX = -depthOffset * stepOffset // Move the line further left to deepen perspective.
                    let stepY = -depthOffset * perspectiveAngle * stepOffset // Move the line upward proportionally to match the viewing angle.
                    
                    var trailingPath = Path() // Path for the trailing depth line.
                    trailingPath.move(to: CGPoint(x: leftPadding + stepX, y: yPos + stepY)) // Start at the left with applied depth offset.
                    trailingPath.addLine(to: CGPoint(x: leftPadding + chartWidth + stepX, y: yPos + stepY)) // Extend to the right with the same offset.
                    context.stroke(trailingPath, with: .color(depthGridColor.opacity(fadeFactor)), lineWidth: 0.5) // Stroke with fading opacity to suggest distance.
                    
                    var trailingConnector = Path() // Connector from the previous layer to the new trailing layer.
                    trailingConnector.move(to: CGPoint(x: leftPadding + backXOffset * stepOffset, y: yPos + backYOffset * stepOffset)) // Start at the prior depth layer.
                    trailingConnector.addLine(to: CGPoint(x: leftPadding + stepX, y: yPos + stepY)) // Connect to the current trailing line to keep the 3D scaffold coherent.
                    context.stroke(trailingConnector, with: .color(depthGridColor.opacity(fadeFactor)), lineWidth: 0.5) // Stroke connector with matching fade so the trail tapers naturally.
                }
            }
        }
        
        // Draw vertical grid lines (X-axis time markers) with 3D depth - every 3 hours
        let hoursInDay = 24
        let xSteps = hoursInDay / 3 // Grid lines every 3 hours
        for i in 0...xSteps {
            let xPos = leftPadding + (CGFloat(i) / CGFloat(xSteps)) * chartWidth
            
            // Front grid line
            var frontPath = Path()
            frontPath.move(to: CGPoint(x: xPos, y: 10))
            frontPath.addLine(to: CGPoint(x: xPos, y: chartHeight + 10))
            context.stroke(frontPath, with: .color(gridColor), lineWidth: 0.5)
            
            // Back grid line (depth line)
            var backPath = Path()
            let backYOffset = -depthOffset * perspectiveAngle
            let backXOffset = -depthOffset
            backPath.move(to: CGPoint(x: xPos + backXOffset, y: 10 + backYOffset))
            backPath.addLine(to: CGPoint(x: xPos + backXOffset, y: chartHeight + 10 + backYOffset))
            context.stroke(backPath, with: .color(depthGridColor), lineWidth: 0.5)
            
            for step in 1...depthFadeSteps { // Extend vertical lines deeper to reinforce the longer tunnel effect.
                let fadeFactor = pow(depthFadeScale, CGFloat(step)) // Compute fading for this trailing step.
                let stepOffset = CGFloat(step + 1) // Depth multiplier for this step.
                let stepX = -depthOffset * stepOffset // Horizontal offset to push the line further back.
                let stepY = -depthOffset * perspectiveAngle * stepOffset // Vertical offset to align with the viewing angle.
                
                var trailingPath = Path() // Path for the trailing vertical line.
                trailingPath.move(to: CGPoint(x: xPos + stepX, y: 10 + stepY)) // Start at the adjusted top point.
                trailingPath.addLine(to: CGPoint(x: xPos + stepX, y: chartHeight + 10 + stepY)) // Extend to the adjusted bottom point.
                context.stroke(trailingPath, with: .color(depthGridColor.opacity(fadeFactor)), lineWidth: 0.5) // Stroke with fading opacity to show distance.
            }
        }
    }
    
    /// Draws Y-axis labels (percentage values)
    private func drawYAxisLabels(context: GraphicsContext, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat) {
        let ySteps = Int(yAxisMax / 50) + 1
        for i in 0...ySteps {
            let yValue = Double(i) * 50.0
            if yValue <= yAxisMax {
                let yPos = chartHeight - (CGFloat(yValue / yAxisMax) * chartHeight) + 10
                let label = "\(Int(yValue))%"
                
                // Draw text label on left side
                var textContext = context
                textContext.translateBy(x: leftPadding - 35, y: yPos)
                textContext.draw(
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(.gray),
                    at: .zero,
                    anchor: .leading
                )
            }
        }
    }
    
    /// Draws X-axis labels (time values)
    private func drawXAxisLabels(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat) {
        let hoursInDay = 24
        let xSteps = hoursInDay / 3 // Labels every 3 hours
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        
        for i in 0...xSteps {
            let hour = i * 3
            let xPos = leftPadding + (CGFloat(i) / CGFloat(xSteps)) * chartWidth
            let timeDate = dayStart.addingTimeInterval(Double(hour) * 3600)
            let label = formatter.string(from: timeDate)
            
            // Draw time label below chart
            var textContext = context
            textContext.translateBy(x: xPos, y: chartHeight + 20)
            textContext.draw(
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.gray),
                at: .zero,
                anchor: .center
            )
        }
    }
    
    /// Draws 3D bars with cube-like depth. Collision layout: median centered, smaller left, larger right; draw order: right first, left second, median last (median on top).
    private func draw3DBars(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat, depthOffset: CGFloat, perspectiveAngle: CGFloat) {
        let barWidth: CGFloat = 24 // Width of each bar (also used for stagger: barWidth * 0.5)
        let barDepth: CGFloat = barWidth
        let dayDuration = dayEnd.timeIntervalSince(dayStart)
        let staggerPixels = barWidth * 0.5 // Minimum horizontal separation when bars share same minute bucket

        // Compute layout: group by minute bucket, assign offsetPixels and drawOrder for collision handling
        let laidOut = layoutBarsForCollision(points: points, dayStart: dayStart, staggerPixels: staggerPixels)

        // Sort for draw order: right (larger) first (back), left (smaller) second, median last (front so median on top)
        let drawOrdered = laidOut.sorted { a, b in
            if a.drawOrder != b.drawOrder { return a.drawOrder < b.drawOrder }
            return a.point.date < b.point.date
        }

        for item in drawOrdered {
            let point = item.point
            let offsetPixels = item.offsetPixels

            // X position: time of day + pixel offset (converted to chart position via ratio)
            let timeOffset = point.date.timeIntervalSince(dayStart)
            let xRatio = CGFloat(timeOffset / dayDuration)
            var xPos = leftPadding + (xRatio * chartWidth) - (barWidth / 2)
            xPos += offsetPixels

            // Y position and height from percent
            let barHeightRatio = CGFloat(min(point.percent, yAxisMax) / yAxisMax)
            let barHeight = barHeightRatio * chartHeight
            let yPos = chartHeight - barHeight + 10

            // Bar color from progress percent (red→yellow→green); do not use colorIndex for fill
            let barColor = MomentumPalette.colorForProgress(point.percent)
            
            // Artificial light from above: top face brightest, front lit, side and back in shadow so edges and depth are visible.
            let backShade = Color.black.opacity(0.5)   // Back face darkest (furthest from light)
            let sideShade = Color.black.opacity(0.35)  // Left side in shadow
            let topShade = Color.black.opacity(0.12)  // Top face slightly shaded (tilted away from vertical light)
            let frontShade = Color.black.opacity(0.05) // Front face receives most light, subtle shade for edge definition
            
            // Draw 3D bar with depth (back, side, top, front) — each face filled with base color then darkened overlay
            let backXOffset = -barDepth
            let backYOffset = -barDepth * perspectiveAngle
            
            // 1. Back face — drawn first for layering, darkest (light from above doesn't reach it)
            var backFace = Path()
            backFace.addRect(CGRect(x: xPos + backXOffset, y: yPos + backYOffset, width: barWidth, height: barHeight))
            context.fill(backFace, with: .color(barColor))
            context.fill(backFace, with: .color(backShade)) // Shade overlay so back edge is visible
            
            // 2. Left side face — in shadow, defines the depth edge
            var leftSide = Path()
            leftSide.move(to: CGPoint(x: xPos, y: yPos))
            leftSide.addLine(to: CGPoint(x: xPos + backXOffset, y: yPos + backYOffset))
            leftSide.addLine(to: CGPoint(x: xPos + backXOffset, y: yPos + backYOffset + barHeight))
            leftSide.addLine(to: CGPoint(x: xPos, y: yPos + barHeight))
            leftSide.closeSubpath()
            context.fill(leftSide, with: .color(barColor))
            context.fill(leftSide, with: .color(sideShade)) // Shade overlay so depth edge is visible
            
            // 3. Top face — lit from above (light source), brightest
            var topFace = Path()
            topFace.move(to: CGPoint(x: xPos, y: yPos))
            topFace.addLine(to: CGPoint(x: xPos + backXOffset, y: yPos + backYOffset))
            topFace.addLine(to: CGPoint(x: xPos + backXOffset + barWidth, y: yPos + backYOffset))
            topFace.addLine(to: CGPoint(x: xPos + barWidth, y: yPos))
            topFace.closeSubpath()
            context.fill(topFace, with: .color(barColor))
            context.fill(topFace, with: .color(topShade)) // Light shade so top edge is defined
            
            // 4. Front face — main view, well lit
            var frontFace = Path()
            frontFace.addRect(CGRect(x: xPos, y: yPos, width: barWidth, height: barHeight))
            context.fill(frontFace, with: .color(barColor))
            context.fill(frontFace, with: .color(frontShade)) // Slight shade so edges are visible
            
            // Add glow effect to front face
            context.drawLayer { layerContext in
                layerContext.addFilter(.shadow(color: barColor.opacity(0.6), radius: 4, x: 0, y: 2))
                layerContext.fill(frontFace, with: .color(barColor))
            }
            
            context.drawLayer { layerContext in // Extra shadow layer to simulate taller bars behind casting onto shorter ones in front.
                layerContext.addFilter(.shadow(color: Color.black.opacity(0.2), radius: 10, x: -6, y: 12)) // Offset shadow diagonally to mimic light from the upper-left, so taller rear bars cast forward.
                layerContext.fill(frontFace, with: .color(barColor.opacity(0.0001))) // Fill with nearly transparent color so only the shadow is visible without changing bar color.
            }
            
            let isOverflow = point.percent > yAxisMax // Check if the actual percent is higher than the visible axis cap so we know when to show an overflow cue.
            if isOverflow { // Only draw the arrow and label when the bar exceeds the current y-axis maximum to keep the chart clean otherwise.
                let arrowHeight: CGFloat = 8 // Small arrow height to keep the indicator subtle while still noticeable.
                let arrowWidth: CGFloat = 10 // Arrow width sized to sit neatly centered atop the bar without overhanging too much.
                let arrowSpacing: CGFloat = 4 // Gap between the top of the bar and the arrow so the shapes do not visually merge.
                let labelSpacing: CGFloat = 6 // Gap between the arrow and the text label for readability and to avoid overlap.
                let arrowTopY = max(yPos - arrowSpacing - arrowHeight, 0) // Position the arrow above the bar while ensuring it does not move outside the canvas bounds.
                let arrowCenterX = xPos + (barWidth / 2) // Center the arrow horizontally over the bar so the cue clearly relates to that bar.
                
                var arrowPath = Path() // Path object to draw a simple upward-pointing triangle arrow.
                arrowPath.move(to: CGPoint(x: arrowCenterX, y: arrowTopY)) // Start at the arrow tip so it points upward, signaling overflow.
                arrowPath.addLine(to: CGPoint(x: arrowCenterX - (arrowWidth / 2), y: arrowTopY + arrowHeight)) // Draw to the left base of the triangle to form one side of the arrow.
                arrowPath.addLine(to: CGPoint(x: arrowCenterX + (arrowWidth / 2), y: arrowTopY + arrowHeight)) // Draw to the right base of the triangle to complete the base edge.
                arrowPath.closeSubpath() // Close the triangle path so it can be filled correctly.
                context.fill(arrowPath, with: .color(barColor)) // Fill the arrow with the bar color so the indicator matches the related bar.
                
                let percentLabel = String(format: "%.0f%%", point.percent) // Format the full percent value so users see exactly how much they exceeded the cap.
                var labelContext = context // Create a mutable copy of the context to position the label independently of other elements.
                labelContext.translateBy(x: arrowCenterX, y: arrowTopY - labelSpacing) // Move the context to the spot above the arrow tip where the label should appear.
                labelContext.draw( // Draw the overflow percent label to communicate the precise over-cap value.
                    Text(percentLabel) // Use the formatted percent string as the label content.
                        .font(.system(size: 10, weight: .semibold)) // Use a small, semi-bold font to stay legible without dominating the chart.
                        .foregroundColor(barColor), // Match the label color to the bar to maintain visual association.
                    at: .zero, // Draw at the translated origin because we already positioned the context.
                    anchor: .center // Center the text relative to the arrow for balanced alignment.
                )
            } // Close overflow indicator block so we only run it for bars exceeding the cap.
        }
    }

    /// Collects points into minute buckets, computes offset and draw order for collision layout.
    /// When N>1 bars share a bucket: sort by percent ascending; median bar centered (offset 0);
    /// smaller bars left (negative offset); larger bars right (positive offset). Stagger = barWidth*0.5.
    private func layoutBarsForCollision(points: [MomentumPoint], dayStart: Date, staggerPixels: CGFloat) -> [(point: MomentumPoint, offsetPixels: CGFloat, drawOrder: Int)] {
        let cal = Calendar.current
        var bucketToPoints: [Int: [MomentumPoint]] = [:]
        for point in points {
            let minuteOfDay = Int(point.date.timeIntervalSince(dayStart) / 60)
            bucketToPoints[minuteOfDay, default: []].append(point)
        }
        var result: [(MomentumPoint, CGFloat, Int)] = []
        for (_, group) in bucketToPoints {
            if group.count == 1 {
                result.append((group[0], 0, 1)) // Single bar: no offset, draw in middle layer
            } else {
                let sorted = group.sorted { $0.percent < $1.percent }
                let n = sorted.count
                let medianIndex = n / 2
                for (i, point) in sorted.enumerated() {
                    let offsetUnits = i - medianIndex
                    let offsetPixels = CGFloat(offsetUnits) * staggerPixels
                    let drawOrder: Int // 0=back (right/larger), 1=mid (left/smaller), 2=front (median)
                    if i > medianIndex { drawOrder = 0 }
                    else if i < medianIndex { drawOrder = 1 }
                    else { drawOrder = 2 }
                    result.append((point, offsetPixels, drawOrder))
                }
            }
        }
        return result
    }

    /// Start of selected day (00:00 local)
    private var dayStart: Date {
        Calendar.current.startOfDay(for: selectedDate)
    }

    /// End of selected day (23:59:59 local)
    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
    }

    /// Empty state when no momentum data for the selected day
    private var emptyChartView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar") // Use valid SF Symbol to avoid runtime symbol error
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No momentum data for this day")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Record a check-in to see progress over time")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    /// Logs a brief summary of what the chart receives so we can confirm data flow
    @discardableResult
    private func logChartReceive() -> Bool {
        let formatter = DateFormatter() // Debug: create formatter for human-readable times
        formatter.dateFormat = "HH:mm" // Debug: show hour and minute
        formatter.timeZone = TimeZone.current // Debug: use local timezone to match chart domain
        let limitedPoints = points.prefix(5) // Debug: avoid log spam by limiting to first few points
        let pointSummaries = limitedPoints.map { point in // Debug: format each point
            let timeString = formatter.string(from: point.date) // Debug: formatted time for point
            let percentString = String(format: "%.1f", point.percent) // Debug: percent with one decimal
            return "\(point.intentionTitle)@\(timeString)=\(percentString)%" // Debug: combined summary
        }
        print("[Momentum] chart receive count=\(points.count) samples=\(pointSummaries)") // Debug: emit chart input overview
        return true // Debug: allow use in let _ = logChartReceive()
    }
}

#Preview {
    MomentumChartView(
        points: [],
        yAxisMax: 100,
        selectedDate: Date()
    )
    .padding()
}
