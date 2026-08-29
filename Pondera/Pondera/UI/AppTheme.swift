//
//  AppTheme.swift
//  Pondera
//
//  Shared semantic design foundation for the consumer UI.
//

import SwiftUI
import UIKit

enum PonderaTheme {
    static let background = Color(red: 0.045, green: 0.055, blue: 0.075)
    static let backgroundRaised = Color(red: 0.075, green: 0.095, blue: 0.115)
    static let surface = Color.white.opacity(0.085)
    static let surfaceStrong = Color.white.opacity(0.13)
    static let border = Color.white.opacity(0.14)

    static let accent = Color(red: 0.22, green: 0.78, blue: 0.70)
    static let accentSecondary = Color(red: 0.52, green: 0.45, blue: 0.95)
    static let success = Color(red: 0.28, green: 0.78, blue: 0.52)
    static let warning = Color(red: 0.96, green: 0.61, blue: 0.28)
    static let recording = Color(red: 0.96, green: 0.30, blue: 0.36)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.52)

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let horizontalPadding: CGFloat = 20

    static let backgroundGradient = LinearGradient(
        colors: [backgroundRaised, background],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    @MainActor
    static func configureAppearance() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tabAppearance.backgroundColor = UIColor(red: 0.045, green: 0.055, blue: 0.075, alpha: 0.82)
        tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        let normalColor = UIColor.white.withAlphaComponent(0.62)
        let selectedColor = UIColor(red: 0.22, green: 0.78, blue: 0.70, alpha: 1)
        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}

/// Shared customer-facing Pondera mark used by the persistent header and launch intro.
struct PonderaBrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            Image("PonderaBrandIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: min(proxy.size.width, proxy.size.height) * 0.2237,
                        style: .continuous
                    )
                )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PonderaHeaderTitle: View {
    var body: some View {
        Text("Pondera: Intentions")
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .tracking(0.25)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PonderaSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PonderaTheme.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens Pondera settings")
    }
}

struct PonderaHeaderGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                PonderaTheme.background.opacity(0.98)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        PonderaTheme.background.opacity(0.76),
                        PonderaTheme.background.opacity(0.38),
                        PonderaTheme.background.opacity(0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Ellipse()
                    .fill(PonderaTheme.accent.opacity(0.10))
                    .frame(width: 210, height: 48)
                    .blur(radius: 22)
                    .offset(x: -95, y: -14)

                Ellipse()
                    .fill(PonderaTheme.accentSecondary.opacity(0.08))
                    .frame(width: 170, height: 42)
                    .blur(radius: 24)
                    .offset(x: 120, y: -10)
            }
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.white.opacity(reduceTransparency ? 0.05 : 0.14), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0.82), location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct PonderaScreenBackground: View {
    var body: some View {
        ZStack {
            PonderaTheme.backgroundGradient

            RadialGradient(
                colors: [PonderaTheme.accent.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct PonderaCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous))
            .background(
                PonderaTheme.surface,
                in: RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous)
                    .stroke(PonderaTheme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 7)
    }
}

struct InsightCaptureCardModifier: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PonderaTheme.cardRadius, style: .continuous)

        content
            .background(
                isHighlighted
                    ? PonderaTheme.accentSecondary.opacity(0.28)
                    : Color.clear,
                in: shape
            )
            .background(.ultraThinMaterial, in: shape)
            .background(PonderaTheme.surface, in: shape)
            .overlay(
                shape
                    .stroke(
                        isHighlighted ? PonderaTheme.accentSecondary.opacity(0.72) : PonderaTheme.border,
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
                    .allowsHitTesting(false)
            )
            .shadow(
                color: isHighlighted ? PonderaTheme.accentSecondary.opacity(0.24) : Color.black.opacity(0.24),
                radius: isHighlighted ? 16 : 12,
                x: 0,
                y: 7
            )
    }
}

struct PonderaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(red: 0.025, green: 0.12, blue: 0.12))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [PonderaTheme.accent, Color(red: 0.35, green: 0.68, blue: 0.96)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: PonderaTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension View {
    func ponderaCard() -> some View {
        modifier(PonderaCardModifier())
    }

    func insightCaptureCard(isHighlighted: Bool) -> some View {
        modifier(InsightCaptureCardModifier(isHighlighted: isHighlighted))
    }
}
