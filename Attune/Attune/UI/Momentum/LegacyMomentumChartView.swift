//
//  LegacyMomentumChartView.swift
//  Attune
//
//  Preserved from commit 1573e22 for side-by-side chart comparison.
//
//  Chart card for Momentum detail page: bars showing % accomplished per intention
//  at check-in times. Uses Swift Charts. Bars at same time overlap with small offsets.
//

import SwiftUI
import Charts

private enum LegacyMomentumChartStyle: String, CaseIterable {
    case bar = "Bar"
    case line = "Line"
}

/// A short left-to-right wave driven by an underdamped spring response. The
/// clock stops once every bar has settled, so the chart does no idle animation.
enum MomentumBarEntranceAnimation {
    private static let settleDuration = 1.25
    private static let maximumWaveDuration = 0.65

    static func totalDuration(barCount: Int) -> Double {
        settleDuration + stagger(barCount: barCount) * Double(max(0, barCount - 1))
    }

    static func scale(
        clock: Double,
        index: Int,
        barCount: Int,
        reduceMotion: Bool
    ) -> Double {
        guard !reduceMotion else { return 1 }

        let localTime = clock - (Double(index) * stagger(barCount: barCount))
        guard localTime > 0 else { return 0 }

        let time = localTime / settleDuration
        guard time < 1 else { return 1 }

        // Closed-form underdamped spring with zero initial velocity. It rises
        // quickly, overshoots once, then makes one smaller correction to rest.
        let damping = 4.8
        let angularFrequency = 10.5
        let decay = exp(-damping * time)
        let response = 1 - decay * (
            cos(angularFrequency * time)
            + (damping / angularFrequency) * sin(angularFrequency * time)
        )
        return min(1.12, max(0, response))
    }

    private static func stagger(barCount: Int) -> Double {
        guard barCount > 1 else { return 0 }
        return min(0.075, maximumWaveDuration / Double(barCount - 1))
    }
}

/// One deterministic, chart-wide layout pass for the daily 3D bars.
/// Every bar keeps one consistent width. Same-minute bars fan out around their
/// timestamp and neighboring clusters shift just enough to keep front faces apart.
struct DailyMomentumBarLayout {
    struct Item {
        let point: MomentumPoint
        let centerX: CGFloat
        let barWidth: CGFloat

        var footprintLeft: CGFloat { centerX - (barWidth * 1.05) }
        var footprintRight: CGFloat { centerX + (barWidth * 0.5) }
    }

    private struct Cluster {
        let points: [MomentumPoint]
        let anchorX: CGFloat
        var centerX: CGFloat
        let memberWidth: CGFloat

        var leftReach: CGFloat {
            frontHalfWidth + (memberWidth * 0.55)
        }

        var rightReach: CGFloat {
            frontHalfWidth
        }

        var frontHalfWidth: CGFloat {
            let step = memberWidth + 4
            return (CGFloat(max(0, points.count - 1)) * step + memberWidth) / 2
        }
    }

    static func makeItems(
        points: [MomentumPoint],
        dayStart: Date,
        dayDuration: TimeInterval,
        chartWidth: CGFloat,
        baseBarWidth: CGFloat = 24,
        minimumBarWidth: CGFloat = 6,
        clusterGap: CGFloat = 2
    ) -> [Item] {
        guard dayDuration > 0, chartWidth > 0, !points.isEmpty else { return [] }

        var pointsByMinute: [Int: [MomentumPoint]] = [:]
        for point in points {
            let minute = Int(floor(point.date.timeIntervalSince(dayStart) / 60))
            pointsByMinute[minute, default: []].append(point)
        }

        var clusters = pointsByMinute.map { minute, minutePoints -> Cluster in
            let sorted = minutePoints.sorted {
                if $0.percent != $1.percent { return $0.percent < $1.percent }
                return $0.intentionId < $1.intentionId
            }
            let minuteOffset = TimeInterval(minute * 60)
            let anchorX = CGFloat(minuteOffset / dayDuration) * chartWidth
            let width = max(minimumBarWidth, baseBarWidth)
            return Cluster(points: sorted, anchorX: anchorX, centerX: anchorX, memberWidth: width)
        }
        .sorted { $0.anchorX < $1.anchorX }

        // Preserve widths and resolve crowding by moving clusters, never by making
        // some activities visually less important with thinner bars.
        for index in clusters.indices {
            let minimumCenter = index == clusters.startIndex
                ? clusters[index].leftReach
                : clusters[index - 1].centerX + clusters[index - 1].rightReach + clusters[index].leftReach + clusterGap
            clusters[index].centerX = max(clusters[index].anchorX, minimumCenter)
        }

        if let lastIndex = clusters.indices.last {
            let overflow = clusters[lastIndex].centerX + clusters[lastIndex].rightReach - chartWidth
            if overflow > 0 {
                for index in clusters.indices { clusters[index].centerX -= overflow }
            }

            for index in stride(from: lastIndex, through: clusters.startIndex, by: -1) {
                let maximumCenter = index == lastIndex
                    ? chartWidth - clusters[index].rightReach
                    : clusters[index + 1].centerX - clusters[index].rightReach - clusters[index + 1].leftReach - clusterGap
                clusters[index].centerX = min(clusters[index].centerX, maximumCenter)
            }
        }

        return clusters.flatMap { cluster in
            let centerIndex = CGFloat(cluster.points.count - 1) / 2
            let memberStep = cluster.memberWidth + 4
            return cluster.points.enumerated().map { index, point in
                Item(
                    point: point,
                    centerX: cluster.centerX + (CGFloat(index) - centerIndex) * memberStep,
                    barWidth: cluster.memberWidth
                )
            }
        }
    }

}

enum DailyMomentumBarStyle {
    /// Preserve the intention color through the first 20%, then progressively
    /// increase the neon treatment at each fifth of the goal.
    static func neonIntensity(for percent: Double) -> Double {
        min(1, max(0, (percent - 20) / 80))
    }
}

/// A readable daily-only time window derived from every point for the day.
/// It keeps filters visually stable because the domain is never based on the
/// currently selected intention alone.
struct DailyMomentumTimeDomain {
    let start: Date
    let end: Date
    let omitsMidnight: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var tickDates: [Date] {
        let coveredHours = max(1, Int(ceil(duration / (60 * 60))))
        let rawStep = Int(ceil(Double(coveredHours) / 4.0))
        let stepHours = [1, 2, 3, 4, 6].first(where: { $0 >= rawStep }) ?? 6
        let step = TimeInterval(stepHours * 60 * 60)
        var result = [start]
        var next = start.addingTimeInterval(step)
        while next < end {
            result.append(next)
            next = next.addingTimeInterval(step)
        }
        if result.last != end { result.append(end) }
        return result
    }

    static func make(
        points: [MomentumPoint],
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> DailyMomentumTimeDomain {
        let midnight = calendar.startOfDay(for: selectedDate)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)
            ?? midnight.addingTimeInterval(24 * 60 * 60)
        let defaultEnd = nextMidnight

        guard let earliest = points.map(\.date).min(),
              let latest = points.map(\.date).max() else {
            return DailyMomentumTimeDomain(start: midnight, end: defaultEnd, omitsMidnight: false)
        }

        let earliestHour = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: earliest)
        ) ?? earliest
        let roundedStart = calendar.date(byAdding: .hour, value: -2, to: earliestHour) ?? earliestHour
        let start = max(midnight, roundedStart)

        let latestHour = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: latest)
        ) ?? latest
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: latestHour) ?? latestHour
        let paddedEnd = calendar.date(byAdding: .hour, value: 2, to: nextHour) ?? nextHour
        let end = min(nextMidnight, paddedEnd)

        return DailyMomentumTimeDomain(
            start: start,
            end: end,
            omitsMidnight: start > midnight
        )
    }
}

/// Chart view: X = time of day, Y = % accomplished. Supports >100% with expanded axis.
struct LegacyMomentumChartView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Data points for the selected day
    let points: [MomentumPoint]

    /// Y-axis max (100 or 150 when any point exceeds 100%)
    let yAxisMax: Double

    /// Selected date used to derive the adaptive daily-only X-axis domain.
    let selectedDate: Date

    /// Optional intention filter matching the current daily chart controls.
    @State private var selectedIntentionId: String?

    /// Preserve the original 3D bars as the default presentation.
    @State private var chartStyle: LegacyMomentumChartStyle = .bar

    @State private var barEntranceStartedAt = Date.distantPast
    @State private var barEntranceComplete = true

    var body: some View {
        let _ = logChartReceive() // Debug: emit chart input summary when body evaluates
        VStack(alignment: .center, spacing: 16) { // Center alignment for the entire card content
            HStack {
                Spacer()
                chartStyleSwitcher
            }

            // Chart area
            if points.isEmpty {
                // Empty state when no check-ins or no progress
                emptyChartView
            } else {
                if chartStyle == .bar {
                    chartContent
                } else {
                    lineChartContent
                }
            }

            if !legendItems.isEmpty {
                intentionSelector
            }

            if !legendItems.isEmpty { // Show intention colors so users can map bars to intentions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(legendItems, id: \.id) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(MomentumPalette.color(forIndex: item.colorIndex))
                                    .frame(width: 10, height: 10)
                                Text(item.title)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .glassCard()
        .onChange(of: points.map(\.intentionId)) { _, intentionIds in
            if let selectedIntentionId, !intentionIds.contains(selectedIntentionId) {
                self.selectedIntentionId = nil
            }
        }
        .task(id: barAnimationIdentity) {
            await runBarEntranceAnimation()
        }
    }

    private var chartStyleSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(LegacyMomentumChartStyle.allCases, id: \.self) { style in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        chartStyle = style
                    }
                } label: {
                    Text(style.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(chartStyle == style ? AttuneTheme.textPrimary : AttuneTheme.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 44)
                        .background(
                            chartStyle == style ? AttuneTheme.surfaceStrong : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chartStyle == style ? .isSelected : [])
            }
        }
        .padding(2)
        .background(AttuneTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(AttuneTheme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart style")
    }

    /// Functional All/intention filters. Compact sizing keeps All plus roughly
    /// four ordinary titles visible on an iPhone, with horizontal scrolling for more.
    private var intentionSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                selectorButton(id: nil, title: "All", colorIndex: nil)
                ForEach(legendItems, id: \.id) { item in
                    selectorButton(id: item.id, title: item.title, colorIndex: item.colorIndex)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func selectorButton(id: String?, title: String, colorIndex: Int?) -> some View {
        let isSelected = selectedIntentionId == id
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedIntentionId = id
            }
        } label: {
            HStack(spacing: 5) {
                if let colorIndex {
                    Image(systemName: MomentumIdentity.symbol(forIndex: colorIndex))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MomentumPalette.color(forIndex: colorIndex))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(isSelected ? AttuneTheme.textPrimary : AttuneTheme.textSecondary)
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .background(isSelected ? AttuneTheme.surfaceStrong : AttuneTheme.surface, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AttuneTheme.accent.opacity(0.75) : AttuneTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(id == nil ? "Show all intentions" : "Show \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var filteredPoints: [MomentumPoint] {
        guard let selectedIntentionId else { return points }
        return points.filter { $0.intentionId == selectedIntentionId }
    }

    /// Collect unique intentions for legend display using stable colorIndex
    private var legendItems: [(id: String, title: String, colorIndex: Int)] {
        var seen = Set<String>()
        var items: [(String, String, Int)] = []
        for point in points {
            if !seen.contains(point.intentionId) {
                seen.insert(point.intentionId)
                items.append((point.intentionId, point.intentionTitle, point.colorIndex))
            }
        }
        return items
    }

    /// 3D Chart with perspective view from upper left corner. Bars have 6px depth, grid lines are 3D.
    private var chartContent: some View {
        let domain = timeDomain
        let hasCompletedBar = filteredPoints.contains { $0.percent >= 100 }
        let entranceDuration = MomentumBarEntranceAnimation.totalDuration(barCount: filteredPoints.count)
        return TimelineView(.animation(
            minimumInterval: barEntranceComplete ? 1.0 / 8.0 : 1.0 / 60.0,
            paused: reduceMotion || (barEntranceComplete && !hasCompletedBar)
        )) { timeline in
            GeometryReader { geometry in
                Canvas { context, size in
                    let seconds = timeline.date.timeIntervalSinceReferenceDate
                    let entranceClock = barEntranceComplete
                        ? entranceDuration
                        : min(entranceDuration, max(0, timeline.date.timeIntervalSince(barEntranceStartedAt)))
                    let completionPulse = reduceMotion
                        ? 1.0
                        : 0.72 + (0.28 * ((sin(seconds * .pi * 2 / 3) + 1) / 2))
                // 3D perspective settings: viewing from upper left corner
                let depthOffset: CGFloat = 60 // Increase depth 10x so grid lines and bars project much further back into space for a stronger 3D effect.
                let perspectiveAngle: CGFloat = 0.32 // Slightly steeper angle so the extended depth remains visible without flattening.
                
                // Calculate chart dimensions with padding for axes
                let leftPadding: CGFloat = 40 // Space for Y-axis labels
                let bottomPadding: CGFloat = 30 // Space for X-axis labels
                let chartWidth = size.width - leftPadding - 20
                let chartHeight = size.height - bottomPadding - 10
                
                // Draw 3D grid lines (behind bars) with depth perspective
                drawGridLines3D(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding, depthOffset: depthOffset, perspectiveAngle: perspectiveAngle, domain: domain)
                
                // Draw Y-axis labels
                drawYAxisLabels(context: context, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding)
                
                // Draw X-axis labels
                drawXAxisLabels(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding, domain: domain)

                // Subtle day boundary markers anchor the waking-to-sleep timeline.
                drawDayBoundarySymbols(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding)
                
                // Draw 3D bars with depth
                draw3DBars(context: context, chartWidth: chartWidth, chartHeight: chartHeight, leftPadding: leftPadding, bottomPadding: bottomPadding, depthOffset: depthOffset, perspectiveAngle: perspectiveAngle, domain: domain, completionPulse: completionPulse, entranceClock: entranceClock)
                }
                .frame(height: 220)
            }
        }
        .frame(height: 220)
    }

    /// Line alternative using the exact same points, manual updates, colors,
    /// selected intention, date domain, and percentage scale as the 3D bars.
    private var lineChartContent: some View {
        let domain = timeDomain
        return Chart {
            if yAxisMax > 100 {
                RuleMark(y: .value("Target", 100))
                    .foregroundStyle(AttuneTheme.success.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(filteredPoints) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Progress", min(point.percent, yAxisMax)),
                    series: .value("Intention", point.intentionId)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Progress", min(point.percent, yAxisMax))
                )
                .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                .symbol {
                    Image(systemName: MomentumIdentity.symbol(forIndex: point.colorIndex))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MomentumPalette.color(forIndex: point.colorIndex))
                }
                .accessibilityLabel(point.intentionTitle)
                .accessibilityValue("\(Int(point.percent.rounded())) percent at \(point.date.formatted(.dateTime.hour().minute()))")
            }
        }
        .chartXScale(domain: domain.start...domain.end)
        .chartYScale(domain: 0...yAxisMax)
        .chartXAxis {
            AxisMarks(values: domain.tickDates) { value in
                AxisGridLine().foregroundStyle(AttuneTheme.border)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        let hasActivity = isActivityHour(date)
                        Text(compactAxisLabel(for: date, showsOmission: domain.omitsMidnight && date == domain.start))
                            .font(.system(size: hasActivity ? 9 : 8, weight: hasActivity ? .bold : .regular))
                            .foregroundStyle(hasActivity ? AttuneTheme.accent : AttuneTheme.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 25)) { value in
                AxisGridLine().foregroundStyle(AttuneTheme.border)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number))%")
                    }
                }
                .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Daily momentum line chart")
    }
    
    /// Draws 3D grid lines with depth perspective (looking from upper left corner)
    private func drawGridLines3D(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat, depthOffset: CGFloat, perspectiveAngle: CGFloat, domain: DailyMomentumTimeDomain) {
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
        
        // Draw vertical grid lines at the same explicit times shown on the X-axis.
        for tick in domain.tickDates {
            let ratio = CGFloat(tick.timeIntervalSince(domain.start) / domain.duration)
            let xPos = leftPadding + ratio * chartWidth
            
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
    private func drawXAxisLabels(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat, domain: DailyMomentumTimeDomain) {
        for (index, tick) in domain.tickDates.enumerated() {
            let ratio = CGFloat(tick.timeIntervalSince(domain.start) / domain.duration)
            let xPos = leftPadding + ratio * chartWidth
            let label = compactAxisLabel(for: tick, showsOmission: domain.omitsMidnight && index == 0)
            let anchor: UnitPoint = index == 0 ? .leading : (index == domain.tickDates.count - 1 ? .trailing : .center)
            let hasActivity = isActivityHour(tick)
            
            // Draw time label below chart
            var textContext = context
            if hasActivity {
                textContext.addFilter(.shadow(color: AttuneTheme.accent.opacity(0.75), radius: 3))
            }
            textContext.translateBy(x: xPos, y: chartHeight + 20)
            textContext.draw(
                Text(label)
                    .font(.system(size: hasActivity ? 8 : 7, weight: hasActivity ? .bold : .regular))
                    .foregroundStyle(hasActivity ? AttuneTheme.accent : Color.gray.opacity(0.82)),
                at: .zero,
                anchor: anchor
            )
        }
    }

    private func drawDayBoundarySymbols(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat) {
        let baselineY = chartHeight + 9
        let sunCenter = CGPoint(x: leftPadding + 2, y: baselineY)
        let moonCenter = CGPoint(x: leftPadding + chartWidth - 2, y: baselineY)
        let symbolColor = AttuneTheme.accent.opacity(0.35)

        var sun = Path()
        sun.addEllipse(in: CGRect(x: sunCenter.x - 2.5, y: sunCenter.y - 2.5, width: 5, height: 5))
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            sun.move(to: CGPoint(x: sunCenter.x + cos(angle) * 4, y: sunCenter.y + sin(angle) * 4))
            sun.addLine(to: CGPoint(x: sunCenter.x + cos(angle) * 6, y: sunCenter.y + sin(angle) * 6))
        }
        context.stroke(sun, with: .color(symbolColor), lineWidth: 0.8)

        var crescent = Path()
        crescent.addArc(center: moonCenter, radius: 5, startAngle: .degrees(55), endAngle: .degrees(305), clockwise: false)
        crescent.addArc(center: CGPoint(x: moonCenter.x + 3, y: moonCenter.y - 0.5), radius: 4.5, startAngle: .degrees(285), endAngle: .degrees(75), clockwise: true)
        crescent.closeSubpath()
        context.fill(crescent, with: .color(Color(red: 0.72, green: 0.82, blue: 1).opacity(0.38)))
    }
    
    /// Draws deliberately overlapped 3D clusters. The rightmost bar is drawn first
    /// at the back; each bar moving left is drawn later, one layer closer.
    private func draw3DBars(context: GraphicsContext, chartWidth: CGFloat, chartHeight: CGFloat, leftPadding: CGFloat, bottomPadding: CGFloat, depthOffset: CGFloat, perspectiveAngle: CGFloat, domain: DailyMomentumTimeDomain, completionPulse: Double, entranceClock: Double) {
        let baseBarWidth: CGFloat = 20

        let laidOut = DailyMomentumBarLayout.makeItems(
            points: filteredPoints,
            dayStart: domain.start,
            dayDuration: domain.duration,
            chartWidth: chartWidth,
            baseBarWidth: baseBarWidth,
            minimumBarWidth: baseBarWidth
        )

        // Draw the furthest-right bar first at the back, then move left. Same-time
        // points are positioned low-to-high, so shorter bars remain visible in front.
        let drawOrdered = laidOut.sorted { a, b in
            if a.centerX != b.centerX { return a.centerX > b.centerX }
            if a.point.percent != b.point.percent { return a.point.percent > b.point.percent }
            return a.point.id < b.point.id
        }

        let entranceOrdered = laidOut.sorted { a, b in
            if a.centerX != b.centerX { return a.centerX < b.centerX }
            if a.point.percent != b.point.percent { return a.point.percent < b.point.percent }
            return a.point.id < b.point.id
        }

        for item in drawOrdered {
            let point = item.point
            let barWidth = item.barWidth
            let barDepth = barWidth * 0.55

            let xPos = leftPadding + item.centerX - (barWidth / 2)

            // Y position and height from percent
            let entranceIndex = entranceOrdered.firstIndex { $0.point.id == point.id } ?? 0
            let entranceScale = MomentumBarEntranceAnimation.scale(
                clock: entranceClock,
                index: entranceIndex,
                barCount: entranceOrdered.count,
                reduceMotion: reduceMotion
            )
            let barHeightRatio = CGFloat(min(point.percent, yAxisMax) / yAxisMax * entranceScale)
            let barHeight = barHeightRatio * chartHeight
            let yPos = chartHeight - barHeight + 10

            // Bar color per intention (stable colorIndex mapping); legend shows these colors
            let barColor = MomentumPalette.color(forIndex: point.colorIndex)
            let neonIntensity = DailyMomentumBarStyle.neonIntensity(for: point.percent)
            let pulse = point.percent >= 100 ? completionPulse : 1
            
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
            context.fill(
                frontFace,
                with: .linearGradient(
                    Gradient(colors: [
                        barColor.opacity(0.9),
                        Color.white.opacity(0.08 + neonIntensity * 0.30),
                        barColor
                    ]),
                    startPoint: CGPoint(x: xPos, y: yPos),
                    endPoint: CGPoint(x: xPos + barWidth, y: yPos + barHeight)
                )
            )
            context.fill(frontFace, with: .color(frontShade)) // Slight shade so edges are visible
            
            // Add glow effect to front face
            context.drawLayer { layerContext in
                layerContext.addFilter(.shadow(
                    color: barColor.opacity(0.22 + neonIntensity * 0.78 * pulse),
                    radius: 2 + neonIntensity * 10 * pulse,
                    x: 0,
                    y: 1
                ))
                layerContext.fill(frontFace, with: .color(barColor))
            }
            
            context.drawLayer { layerContext in // Extra shadow layer to simulate taller bars behind casting onto shorter ones in front.
                layerContext.addFilter(.shadow(color: Color.black.opacity(0.2), radius: 10, x: -6, y: 12)) // Offset shadow diagonally to mimic light from the upper-left, so taller rear bars cast forward.
                layerContext.fill(frontFace, with: .color(barColor.opacity(0.0001))) // Fill with nearly transparent color so only the shadow is visible without changing bar color.
            }
            
            let isOverflow = point.percent > yAxisMax // Check if the actual percent is higher than the visible axis cap so we know when to show an overflow cue.
            if isOverflow && entranceScale > 0.95 { // Let the overflow cue arrive with its bar instead of floating above the baseline.
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

    private var timeDomain: DailyMomentumTimeDomain {
        DailyMomentumTimeDomain.make(points: points, selectedDate: selectedDate)
    }

    private var barAnimationIdentity: String {
        let pointIdentity = filteredPoints
            .sorted { $0.date < $1.date }
            .map { "\($0.id):\($0.percent)" }
            .joined(separator: "|")
        return "\(chartStyle.rawValue)|\(pointIdentity)|reduce:\(reduceMotion)"
    }

    @MainActor
    private func runBarEntranceAnimation() async {
        let duration = MomentumBarEntranceAnimation.totalDuration(barCount: filteredPoints.count)
        guard !reduceMotion, chartStyle == .bar, !filteredPoints.isEmpty else {
            barEntranceComplete = true
            return
        }
        barEntranceStartedAt = Date()
        barEntranceComplete = false
        await Task.yield()
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        barEntranceComplete = true
    }

    private func axisLabel(for date: Date, showsOmission: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func compactAxisLabel(for date: Date, showsOmission: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func isActivityHour(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return filteredPoints.contains { calendar.isDate($0.date, equalTo: date, toGranularity: .hour) }
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
    LegacyMomentumChartView(
        points: [],
        yAxisMax: 100,
        selectedDate: Date()
    )
    .padding()
}
