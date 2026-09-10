//
//  LifeAreaConstellationCard.swift
//  Pondera
//

import SwiftUI

struct LifeAreaConstellationCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let items: [ExtractedItem]
    let corrections: [String: ItemCorrection]
    @State private var selectedPeriod: LifeAreaPeriod = .day
    @State private var hasAppeared = false
    @State private var pulsePhase = false
    @State private var pressedCategory: String?
    @State private var destinationCategory: String?

    private var summaries: [LifeAreaSummary] {
        LifeAreaSummaryBuilder.make(
            from: items,
            corrections: corrections,
            period: selectedPeriod
        )
        .filter { $0.intentionCount > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PonderaTheme.textPrimary)
                Text("Areas that have been present in your conversations.")
                    .font(.caption)
                    .foregroundStyle(PonderaTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Life area period", selection: $selectedPeriod) {
                ForEach(LifeAreaPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            GeometryReader { geometry in
                let nodes = layoutNodes(in: geometry.size)

                ZStack {
                    LifeAreaPerspectiveGrid()

                    if nodes.isEmpty {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(PonderaTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    } else {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                            let isPressed = pressedCategory == node.summary.category
                            Button {
                                selectNode(node.summary.category)
                            } label: {
                                LifeAreaBubble(
                                    summary: node.summary,
                                    diameter: node.diameter,
                                    color: categoryColor(for: node.summary.category),
                                    isHighlighted: isPressed
                                )
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(hasAppeared ? (isPressed ? 1.12 : (pulsePhase ? 1.035 : 1)) : 0.12)
                            .opacity(hasAppeared ? (pressedCategory == nil || isPressed ? 1 : 0.26) : 0)
                            .blur(radius: pressedCategory == nil || isPressed ? 0 : 1.2)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.045),
                                value: hasAppeared
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        guard pressedCategory == nil else { return }
                                        pressedCategory = node.summary.category
                                        PonderaHaptics.insightSelection()
                                    }
                            )
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.8)
                                    .repeatCount(2, autoreverses: true)
                                    .delay(0.18 + Double(index) * 0.055),
                                value: pulsePhase
                            )
                            .position(node.position)
                            .accessibilityLabel(
                                "\(InsightDisplay.categoryLabel(node.summary.category)), \(node.summary.mentionCount) mentions, \(node.summary.intentionCount) intentions"
                            )
                            .accessibilityHint("Opens this life area")
                        }
                    }
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.82),
                    value: selectedPeriod
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(height: 264)

            Text("Circle size follows intentions in the selected period.")
                .font(.caption2)
                .foregroundStyle(PonderaTheme.textTertiary)

            NavigationLink(
                destination: LifeAreaDetailView(category: destinationCategory ?? ""),
                isActive: Binding(
                    get: { destinationCategory != nil },
                    set: {
                        if !$0 {
                            destinationCategory = nil
                            pressedCategory = nil
                        }
                    }
                )
            ) {
                EmptyView()
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .padding(14)
        .ponderaCard()
        .onAppear {
            replayEntrance()
        }
        .onChange(of: selectedPeriod) { _, _ in
            pressedCategory = nil
            replayEntrance()
        }
    }

    private func replayEntrance() {
        pulsePhase = false
        guard !reduceMotion else {
            hasAppeared = true
            return
        }

        hasAppeared = false
        withAnimation {
            hasAppeared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
            guard !reduceMotion else { return }
            withAnimation {
                pulsePhase = true
            }
        }
    }

    private func selectNode(_ category: String) {
        guard destinationCategory == nil else { return }
        if pressedCategory == nil {
            pressedCategory = category
            PonderaHaptics.insightSelection()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard destinationCategory == nil else { return }
            PonderaHaptics.insightHandoff()
            withAnimation(.easeInOut(duration: 0.28)) {
                destinationCategory = category
            }
        }
    }

    private var title: String {
        switch selectedPeriod {
        case .day: return "For your life today"
        case .week: return "For your life this week"
        case .month: return "For your life this month"
        case .allTime: return "Across your life"
        }
    }

    private var emptyMessage: String {
        selectedPeriod == .allTime
            ? "No life areas yet."
            : "No life areas mentioned in this period."
    }

    private func layoutNodes(in size: CGSize) -> [LifeAreaBubbleNode] {
        let ordered = summaries.sorted { categoryOrder($0.category) < categoryOrder($1.category) }
        guard !ordered.isEmpty else { return [] }
        if ordered.count == 1, let summary = ordered.first {
            return [
                LifeAreaBubbleNode(
                    summary: summary,
                    diameter: LifeAreaBubbleScale.diameter(for: summary.intentionCount),
                    position: CGPoint(x: size.width * 0.5, y: size.height * 0.46)
                )
            ]
        }

        // Each life area owns a stable, asymmetric anchor. The collision pass
        // only nudges circles away from one another, so repeated visits retain
        // the same visual map without falling back to a uniform row or grid.
        var nodes = ordered.map { summary in
            let anchor = normalizedAnchor(for: summary.category)
            return LifeAreaBubbleNode(
                summary: summary,
                diameter: LifeAreaBubbleScale.diameter(for: summary.intentionCount),
                position: CGPoint(
                    x: size.width * anchor.x,
                    y: size.height * anchor.y
                )
            )
        }

        let minimumGap: CGFloat = 18
        for _ in 0..<120 {
            for index in nodes.indices {
                let anchor = normalizedAnchor(for: nodes[index].summary.category)
                let target = CGPoint(
                    x: size.width * anchor.x,
                    y: size.height * anchor.y
                )
                nodes[index].position.x += (target.x - nodes[index].position.x) * 0.012
                nodes[index].position.y += (target.y - nodes[index].position.y) * 0.012
            }

            for first in nodes.indices {
                for second in nodes.indices where second > first {
                    let dx = nodes[second].position.x - nodes[first].position.x
                    let dy = nodes[second].position.y - nodes[first].position.y
                    let distance = max(0.001, hypot(dx, dy))
                    let firstRadius = nodes[first].diameter * 0.5
                    let secondRadius = nodes[second].diameter * 0.5
                    let requiredDistance = firstRadius + secondRadius + minimumGap
                    guard distance < requiredDistance else { continue }

                    let overlap = requiredDistance - distance
                    let directionX: CGFloat
                    let directionY: CGFloat
                    if distance < 1 {
                        let angle = CGFloat((first + 1) * (second + 2)) * 0.83
                        directionX = cos(angle)
                        directionY = sin(angle)
                    } else {
                        directionX = dx / distance
                        directionY = dy / distance
                    }

                    let totalDiameter = max(1, nodes[first].diameter + nodes[second].diameter)
                    let firstMovement = overlap * (nodes[second].diameter / totalDiameter)
                    let secondMovement = overlap * (nodes[first].diameter / totalDiameter)
                    nodes[first].position.x -= directionX * firstMovement
                    nodes[first].position.y -= directionY * firstMovement
                    nodes[second].position.x += directionX * secondMovement
                    nodes[second].position.y += directionY * secondMovement
                }
            }

            for index in nodes.indices {
                nodes[index].position = constrainedPosition(
                    nodes[index].position,
                    diameter: nodes[index].diameter,
                    in: size
                )
            }
        }

        return nodes
    }

    private func constrainedPosition(_ point: CGPoint, diameter: CGFloat, in size: CGSize) -> CGPoint {
        let radius = diameter * 0.5
        let canFitHorizontally = diameter + 16 <= size.width
        let canFitVertically = diameter + 16 <= size.height
        let horizontalInset = canFitHorizontally ? radius + 8 : 28
        let topInset = canFitVertically ? radius + 8 : 28
        let bottomInset: CGFloat
        if canFitVertically {
            // Small bubbles place their readable label beneath the circle.
            bottomInset = radius + (diameter < 88 ? 42 : 8)
        } else {
            // Oversized bubbles may leave the card, but their centered text
            // remains visible and substantially more than a quarter remains.
            bottomInset = 28
        }
        return CGPoint(
            x: min(max(point.x, horizontalInset), max(horizontalInset, size.width - horizontalInset)),
            y: min(max(point.y, topInset), max(topInset, size.height - bottomInset))
        )
    }

    private func normalizedAnchor(for category: String) -> CGPoint {
        switch category {
        case ExtractedItem.Category.fitnessHealth: return CGPoint(x: 0.22, y: 0.28)
        case ExtractedItem.Category.careerWork: return CGPoint(x: 0.71, y: 0.24)
        case ExtractedItem.Category.moneyFinance: return CGPoint(x: 0.82, y: 0.72)
        case ExtractedItem.Category.personalGrowth: return CGPoint(x: 0.49, y: 0.70)
        case ExtractedItem.Category.relationshipsSocial: return CGPoint(x: 0.19, y: 0.72)
        case ExtractedItem.Category.stressLoad: return CGPoint(x: 0.45, y: 0.22)
        case ExtractedItem.Category.peaceWellbeing: return CGPoint(x: 0.70, y: 0.52)
        default: return CGPoint(x: 0.52, y: 0.46)
        }
    }

    private func categoryOrder(_ category: String) -> Int {
        switch category {
        case ExtractedItem.Category.fitnessHealth: return 0
        case ExtractedItem.Category.careerWork: return 1
        case ExtractedItem.Category.moneyFinance: return 2
        case ExtractedItem.Category.personalGrowth: return 3
        case ExtractedItem.Category.relationshipsSocial: return 4
        case ExtractedItem.Category.stressLoad: return 5
        case ExtractedItem.Category.peaceWellbeing: return 6
        default: return 7
        }
    }

    private func categoryColor(for category: String) -> Color {
        switch category {
        case ExtractedItem.Category.fitnessHealth: return .green
        case ExtractedItem.Category.careerWork: return .blue
        case ExtractedItem.Category.moneyFinance: return .yellow
        case ExtractedItem.Category.personalGrowth: return .purple
        case ExtractedItem.Category.relationshipsSocial: return .pink
        case ExtractedItem.Category.stressLoad: return .orange
        case ExtractedItem.Category.peaceWellbeing: return .cyan
        default: return PonderaTheme.accent
        }
    }
}

private struct LifeAreaBubbleNode: Identifiable {
    let summary: LifeAreaSummary
    let diameter: CGFloat
    var position: CGPoint

    var id: String { summary.id }
}

enum LifeAreaBubbleScale {
    /// A deliberately legible low end, followed by continuous growth. After
    /// five intentions every additional intention adds five points, so a very
    /// active area can become larger than the card instead of being normalized
    /// back toward the other circles.
    static func diameter(for count: Int) -> CGFloat {
        switch count {
        case ...0: return 0
        case 1: return 14
        case 2: return 22
        case 3: return 32
        case 4: return 44
        case 5: return 58
        default: return 58 + CGFloat(count - 5) * 5
        }
    }
}

private struct LifeAreaBubble: View {
    let summary: LifeAreaSummary
    let diameter: CGFloat
    let color: Color
    let isHighlighted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.22))
                .overlay {
                    Circle()
                        .stroke(
                            color.opacity(isHighlighted ? 1 : 0.82),
                            lineWidth: min(4, max(1.2, diameter / 32))
                        )
                }
                .overlay {
                    Circle()
                        .stroke(color.opacity(isHighlighted ? 0.55 : 0.18), lineWidth: 1)
                        .padding(-min(5, max(2, diameter / 24)))
                }
                .frame(width: diameter, height: diameter)

            if diameter >= 88 {
                bubbleText
            } else {
                Text("\(summary.intentionCount)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(PonderaTheme.textPrimary)

                bubbleText
                    .offset(y: diameter * 0.5 + 17)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: color.opacity(isHighlighted ? 0.72 : 0.28), radius: isHighlighted ? 14 : 5)
        .contentShape(Circle())
    }

    private var bubbleText: some View {
        VStack(spacing: 1) {
            if diameter >= 88 {
                Text("\(summary.intentionCount)")
                    .font(.headline.weight(.bold).monospacedDigit())
            }
            Text(InsightDisplay.categoryLabel(summary.category))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text("\(summary.intentionCount) \(summary.intentionCount == 1 ? "intention" : "intentions")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(diameter >= 88 ? PonderaTheme.textSecondary : PonderaTheme.textTertiary)
                .lineLimit(1)
        }
        .foregroundStyle(PonderaTheme.textPrimary)
        .frame(width: max(80, min(diameter - 12, 116)))
    }
}

private struct LifeAreaPerspectiveGrid: View {
    var body: some View {
        Canvas { context, size in
            let horizon = size.height * 0.36
            let color = PonderaTheme.accent.opacity(0.16)
            var lines = Path()

            for index in 0...8 {
                let x = size.width * CGFloat(index) / 8
                lines.move(to: CGPoint(x: size.width * 0.5, y: horizon))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }

            for index in 0...7 {
                let progress = CGFloat(index) / 7
                let y = horizon + pow(progress, 1.8) * (size.height - horizon)
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(lines, with: .color(color), lineWidth: 0.65)
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.96),
                        PonderaTheme.background.opacity(0.92),
                        Color(red: 0.035, green: 0.11, blue: 0.14).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                PonderaTheme.brandGradient
                    .opacity(0.12)

                RadialGradient(
                    colors: [PonderaTheme.accent.opacity(0.2), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: 190
                )
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [PonderaTheme.accent.opacity(0.34), PonderaTheme.accentSecondary.opacity(0.16), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .allowsHitTesting(false)
    }
}
