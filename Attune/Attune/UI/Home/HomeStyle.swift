//
//  HomeStyle.swift
//  Attune
//
//  Cyber-glass neon style system for Home UI.
//  Replicates teal fog glow, glass blur cards, bloom shadows, neon progress fills.
//  Does NOT modify layout; provides reusable components for future integration.
//

import SwiftUI

// MARK: - Color Palette

/// Neon/cyber color system sampled from reference image.
/// All colors use SwiftUI Color for consistency across light/dark modes (though this is dark-only design).
struct NeonPalette {
    // Base dark background colors
    static let darkBase = Color(red: 0.08, green: 0.08, blue: 0.10)          // Near-black background
    static let darkOverlay = Color(red: 0.12, green: 0.12, blue: 0.15)       // Slightly lighter for overlays
    
    // Primary neon teal (used for glows, progress fills, accents)
    static let neonTeal = Color(red: 0.2, green: 0.8, blue: 0.7)             // Bright cyan-teal
    static let neonTealGlow = Color(red: 0.15, green: 0.85, blue: 0.75)      // Slightly brighter for glow layers
    
    // Secondary glow (softer, used for background fog)
    static let fogTeal = Color(red: 0.18, green: 0.65, blue: 0.6)            // Muted teal for radial background glow
    
    // Edge lighting and highlights
    static let edgeLightTop = Color.white.opacity(0.25)                      // Top-left edge light gradient start
    static let edgeLightBottom = Color.white.opacity(0.0)                    // Edge light gradient end (transparent)
    
    // Glass card strokes
    static let glassStrokePrimary = Color.white.opacity(0.12)                // Main perimeter stroke
    static let glassStrokeSubtle = Color.white.opacity(0.05)                 // Subtle inner stroke
    
    // Shadow/bloom colors
    static let bloomShadow = Color(red: 0.15, green: 0.85, blue: 0.75).opacity(0.4)  // Teal bloom shadow
    static let darkShadow = Color.black.opacity(0.5)                         // Dark base shadow for depth
    
    // Low mood colors (red/orange) - reuse MoodTier mapping but define accent palette
    static let moodLowRed = Color(red: 0.9, green: 0.25, blue: 0.2)          // veryLow tier
    static let moodLowOrange = Color(red: 0.95, green: 0.5, blue: 0.2)       // low tier
    static let moodNeutralYellow = Color(red: 0.9, green: 0.75, blue: 0.2)   // neutral tier
    
    // Record Check-In button: blue gradient + light red/orange border
    static let recordButtonBlue = Color(red: 0.2, green: 0.5, blue: 0.85)       // Deeper blue
    static let recordButtonBlueLight = Color(red: 0.35, green: 0.6, blue: 0.95)  // Lighter blue (gradient end)
    static let recordButtonBorder = Color(red: 1.0, green: 0.6, blue: 0.4)       // Light red/orange border + glow
}

// MARK: - MoodTier Extensions

/// Extends existing MoodTier (Models/MoodTier.swift) with halo/gradient helpers for UI.
/// Does NOT move or refactor the enum; just adds display utilities here.
extension MoodTier {
    
    /// Returns halo color for Record button based on mood tier.
    /// Positive tiers = teal/green; low tiers = red/orange.
    /// Matches existing `colorForMoodTier` but exposed for halo blur layers.
    static func haloColor(for tier: MoodTier) -> Color {
        // Delegate to existing colorForMoodTier for consistency
        return colorForMoodTier(tier)
    }
    
    /// Returns a gradient fill for buttons/pills based on mood tier.
    /// Positive moods use teal gradient; low moods use red/orange gradients.
    static func gradientFill(for tier: MoodTier) -> LinearGradient {
        let baseColor = colorForMoodTier(tier)
        // Create a subtle gradient by varying opacity/brightness
        let lighterColor = baseColor.opacity(0.9)
        let darkerColor = baseColor.opacity(0.7)
        
        return LinearGradient(
            gradient: Gradient(colors: [lighterColor, darkerColor]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - CyberBackground

/// Full-screen cyber background with dark gradient base, teal radial glow, and vignette.
/// Modern crisp glassy look: multiple teal fog layers, soft glows, and depth vignette.
struct CyberBackground: View {
    var body: some View {
        ZStack {
            // 1) Dark gradient base (top to bottom, subtle variation)
            LinearGradient(
                gradient: Gradient(colors: [
                    NeonPalette.darkBase,
                    NeonPalette.darkOverlay
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // 2) Primary teal radial glow in lower-mid area (stronger, more vibrant)
            RadialGradient(
                gradient: Gradient(colors: [
                    NeonPalette.fogTeal.opacity(0.45),   // Brighter center glow
                    NeonPalette.fogTeal.opacity(0.2),   // Mid falloff
                    NeonPalette.fogTeal.opacity(0.05),  // Soft outer ring
                    Color.clear                          // Fade to transparent
                ]),
                center: .center,
                startRadius: 30,
                endRadius: 450
            )
            .offset(y: 80)
            .blur(radius: 20)  // Soft bloom for modern glassy feel
            .ignoresSafeArea()
            
            // 3) Secondary teal glow (upper-left corner, subtle accent)
            RadialGradient(
                gradient: Gradient(colors: [
                    NeonPalette.neonTealGlow.opacity(0.15),
                    NeonPalette.neonTealGlow.opacity(0.05),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.2, y: 0.15),
                startRadius: 10,
                endRadius: 280
            )
            .ignoresSafeArea()
            
            // 4) Third glow (lower-right, adds depth and asymmetry)
            RadialGradient(
                gradient: Gradient(colors: [
                    NeonPalette.neonTeal.opacity(0.12),
                    Color.clear
                ]),
                center: UnitPoint(x: 0.9, y: 0.75),
                startRadius: 20,
                endRadius: 200
            )
            .ignoresSafeArea()
            
            // 5) Vignette overlay (darkens edges for depth and focus)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    NeonPalette.darkBase.opacity(0.7)
                ]),
                center: .center,
                startRadius: 180,
                endRadius: 550
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - GlassTextureOverlay

/// Procedural texture for glass cards: fine grain + subtle hexagonal mesh.
/// Grain = frosted glass micro-texture; hex mesh = cool cyber/sci-fi accent.
/// All drawn in code—no image assets needed.
struct GlassTextureOverlay: View {
    var body: some View {
        Canvas { context, size in
            // 1) Fine grain: tiny dots for frosted glass micro-texture
            let dotSpacing: CGFloat = 3
            for i in stride(from: 0, to: size.width + dotSpacing, by: dotSpacing) {
                for j in stride(from: 0, to: size.height + dotSpacing, by: dotSpacing) {
                    // Pseudo-random opacity from position (deterministic, no actual random)
                    let s = sin(i * 0.07) * cos(j * 0.09) + sin((i + j) * 0.05)
                    let opacity = 0.02 + 0.05 * (s + 1) / 2
                    let rect = CGRect(x: i, y: j, width: 1.2, height: 1.2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
            // 2) Subtle hexagonal mesh (sparse, teal-tinted—cool cyber accent)
            let hexSize: CGFloat = 36
            let lineOpacity: CGFloat = 0.03
            for row in 0..<Int(size.height / (hexSize * 0.85)) + 1 {
                for col in 0..<Int(size.width / (hexSize * 1.5)) + 1 {
                    let x = CGFloat(col) * hexSize * 1.5 + (row % 2 == 0 ? 0 : hexSize * 0.75)
                    let y = CGFloat(row) * hexSize * 0.866
                    if x < size.width + hexSize && y < size.height + hexSize {
                        var path = Path()
                        for k in 0..<6 {
                            let angle = CGFloat(k) * .pi / 3 - .pi / 6
                            let px = x + hexSize * cos(angle)
                            let py = y + hexSize * sin(angle)
                            if k == 0 { path.move(to: CGPoint(x: px, y: py)) }
                            else { path.addLine(to: CGPoint(x: px, y: py)) }
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(NeonPalette.neonTeal.opacity(lineOpacity)), lineWidth: 0.4)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - GlassCard Modifier

/// View modifier that applies cyber-glass card styling.
/// Modern glassy look: UltraThinMaterial blur, texture overlay, edge lighting,
/// perimeter stroke, stronger bloom shadows, and bottom inner shadow for depth.
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                // Dark tint overlay for glass effect
                NeonPalette.darkOverlay.opacity(0.35)
                    .allowsHitTesting(false) // Keep the tint layer visual-only so touches pass through to child controls.
            )
            .background(
                // UltraThinMaterial blur layer (frosted glass)
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                // Cool texture: grain + subtle hex mesh (frosted crystalline look)
                GlassTextureOverlay()
                    .blendMode(.overlay)
                    .opacity(0.7)
                    .allowsHitTesting(false) // Prevent texture overlay from swallowing button touches.
            )
            .overlay(
                // Edge lighting stroke (crisp top-left highlight for glassy shine)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .allowsHitTesting(false) // Keep edge-light stroke purely visual and non-interactive.
            )
            .overlay(
                // Perimeter subtle stroke (all edges, glass border)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NeonPalette.glassStrokePrimary, lineWidth: 1)
                    .allowsHitTesting(false) // Ensure perimeter stroke does not block taps to child controls.
            )
            .overlay(
                // Teal glow accent on bottom edge (subtle cyan halo)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NeonPalette.neonTeal.opacity(0.08), lineWidth: 0.5)
                    .allowsHitTesting(false) // Keep bottom glow layer visual-only for reliable hit testing.
            )
            .overlay(
                // Bottom inner shadow gradient overlay (adds depth at bottom edge)
                VStack {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            NeonPalette.darkShadow.opacity(0.35)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false) // Avoid inner-shadow overlay from intercepting interactions.
            )
            .shadow(color: NeonPalette.bloomShadow.opacity(0.5), radius: 16, x: 0, y: 6)   // Teal bloom (stronger)
            .shadow(color: NeonPalette.bloomShadow.opacity(0.2), radius: 24, x: 0, y: 8)  // Outer soft glow
            .shadow(color: NeonPalette.darkShadow, radius: 10, x: 0, y: 4)               // Dark depth
    }
}

extension View {
    /// Applies cyber-glass card styling with bloom shadows and edge lighting.
    func glassCard() -> some View {
        self.modifier(GlassCardModifier())
    }
}

// MARK: - RecordCheckInButtonStyle

/// Dedicated style for Record Check-In button: blue gradient, light red/orange border, subtle glow.
/// Does not vary by mood; consistent inviting look.
struct RecordCheckInButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .background(
                ZStack {
                    // Glow layer behind button (soft blue bloom)
                    Capsule()
                        .fill(NeonPalette.recordButtonBlue)
                        .blur(radius: 20)
                        .opacity(0.5)
                        .scaleEffect(1.1)
                    // Blue-to-blue gradient fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    NeonPalette.recordButtonBlueLight,
                                    NeonPalette.recordButtonBlue
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                // Thin light red/orange border with slight glow
                Capsule()
                    .stroke(NeonPalette.recordButtonBorder, lineWidth: 1.5)
                    .shadow(color: NeonPalette.recordButtonBorder.opacity(0.6), radius: 6, x: 0, y: 0)
            )
            // Use immediate spring animation for more responsive feel (no delay)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            // Reduce opacity slightly when pressed for additional visual feedback
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

// MARK: - NeonPillButtonStyle

/// Button style for neon pill CTA (e.g., Record Check-In button).
/// Features: gradient fill, halo blur behind, inner highlight stroke, bloom shadows, press scale animation.
/// Padding: more vertical (off the text) and moderate horizontal—user prefers padding around text, not stretched sides.
struct NeonPillButtonStyle: ButtonStyle {
    let moodTier: MoodTier   // Determines color/halo based on mood
    var fullWidth: Bool = true  // When true, button spans available width; padding is around text only
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: fullWidth ? .infinity : nil)  // Full width when true; else size to content
            .padding(.horizontal, 24)   // Moderate horizontal; padding around text, not stretched sides
            .padding(.vertical, 24)    // More padding above/below text (off the text, not the sides)
            .background(
                ZStack {
                    // Halo blur layer behind button (glow effect)
                    Capsule()
                        .fill(MoodTier.haloColor(for: moodTier))
                        .blur(radius: 20)
                        .opacity(0.6)
                        .scaleEffect(1.1)
                    
                    // Main gradient fill
                    Capsule()
                        .fill(MoodTier.gradientFill(for: moodTier))
                }
            )
            .overlay(
                // Inner highlight stroke (top edge shimmer)
                Capsule()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .padding(1)  // Inset stroke slightly
            )
            .shadow(color: MoodTier.haloColor(for: moodTier).opacity(0.6), radius: 20, x: 0, y: 8)  // Stronger bloom
            .shadow(color: MoodTier.haloColor(for: moodTier).opacity(0.25), radius: 32, x: 0, y: 12)  // Outer soft glow
            .shadow(color: NeonPalette.darkShadow, radius: 10, x: 0, y: 5)                           // Depth shadow
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)  // Slight press scale animation
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - NeonProgressBar

/// Neon progress bar with capsule track, teal glow, and glowing fill.
/// Matches reference: dark translucent track + teal glow underlay + bright teal fill + glow shadow.
struct NeonProgressBar: View {
    let value: Double        // Progress value 0.0 to 1.0
    let height: CGFloat      // Bar height (default ~8-10pt)
    
    init(value: Double, height: CGFloat = 10) {
        self.value = max(0.0, min(1.0, value))  // Clamp to 0-1 range
        self.height = height
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track (dark translucent capsule)
                Capsule()
                    .fill(NeonPalette.darkOverlay.opacity(0.5))
                    .frame(height: height)
                
                // Teal glow layer behind fill (positioned under the fill bar)
                if value > 0 {
                    Capsule()
                        .fill(NeonPalette.neonTealGlow)
                        .blur(radius: 6)
                        .frame(width: geometry.size.width * value, height: height)
                        .opacity(0.4)
                }
                
                // Teal main fill bar
                if value > 0 {
                    Capsule()
                        .fill(NeonPalette.neonTeal)
                        .frame(width: geometry.size.width * value, height: height)
                        .shadow(color: NeonPalette.bloomShadow, radius: 6, x: 0, y: 2)  // Glow shadow on fill
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - WeeklyMomentumBar

/// Single vertical momentum bar for weekly display.
/// 8pt width, glows when filled, day letter beneath, empty for future days.
/// Uses existing MomentumTier from Models/WeekMomentum.swift for color mapping.
struct WeeklyMomentumBar: View {
    let dayLetter: String         // Single letter: M, T, W, T, F, S, S
    let fillHeight: CGFloat       // Height of filled portion (0 = empty, max ~48pt)
    let isFutureDay: Bool         // If true, render as empty (no bar)
    let tier: MomentumTier?       // Momentum tier from Models/WeekMomentum.swift (determines bar color)
    
    private let barWidth: CGFloat = 8
    private let maxBarHeight: CGFloat = 48
    
    var body: some View {
        VStack(spacing: 4) {
            // Bar area (fixed height container)
            ZStack(alignment: .bottom) {
                // Empty container (always present for layout stability)
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: barWidth, height: maxBarHeight)
                
                // Filled bar (only if not future day and has height)
                if !isFutureDay && fillHeight > 0 {
                    let barColor = colorForTier(tier ?? .neutral)
                    
                    ZStack {
                        // Glow layer behind bar
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor)
                            .blur(radius: 4)
                            .opacity(0.5)
                        
                        // Main filled bar
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor)
                            .shadow(color: barColor.opacity(0.6), radius: 4, x: 0, y: 2)
                    }
                    .frame(width: barWidth, height: fillHeight)
                }
            }
            
            // Day letter beneath bar
            Text(dayLetter)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
    }
    
    /// Maps MomentumTier to bar color (matches HomeView's colorForMomentumTier).
    /// Uses existing MomentumTier enum from Models/WeekMomentum.swift.
    private func colorForTier(_ tier: MomentumTier) -> Color {
        switch tier {
        case .veryLow:
            return NeonPalette.moodLowRed
        case .low:
            return NeonPalette.moodLowOrange
        case .neutral:
            return Color.gray
        case .good:
            return Color(red: 0.3, green: 0.7, blue: 0.5)
        case .great:
            return NeonPalette.neonTeal
        }
    }
}

// MARK: - Preview Helpers

#Preview("CyberBackground") {
    CyberBackground()
}

#Preview("GlassCard") {
    ZStack {
        CyberBackground()
        
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Progress")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Sample glass card with bloom shadows")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding()
            .glassCard()
        }
        .padding()
    }
}

#Preview("NeonPillButton") {
    ZStack {
        CyberBackground()
        
        VStack(spacing: 20) {
            Button("Record Check-In (Happy)") {}
                .buttonStyle(NeonPillButtonStyle(moodTier: .great))
            
            Button("Record Check-In (Neutral)") {}
                .buttonStyle(NeonPillButtonStyle(moodTier: .neutral))
            
            Button("Record Check-In (Low)") {}
                .buttonStyle(NeonPillButtonStyle(moodTier: .low))
        }
        .font(.title2)
        .fontWeight(.bold)
        .padding()
    }
}

#Preview("NeonProgressBar") {
    ZStack {
        CyberBackground()
        
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reading")
                        .foregroundColor(.white)
                    Spacer()
                    Text("75%")
                        .foregroundColor(.white)
                }
                NeonProgressBar(value: 0.75, height: 10)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Exercise")
                        .foregroundColor(.white)
                    Spacer()
                    Text("30%")
                        .foregroundColor(.white)
                }
                NeonProgressBar(value: 0.30, height: 10)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Not Started")
                        .foregroundColor(.white)
                    Spacer()
                    Text("0%")
                        .foregroundColor(.white)
                }
                NeonProgressBar(value: 0.0, height: 10)
            }
        }
        .padding()
    }
}

#Preview("WeeklyMomentumBar") {
    ZStack {
        CyberBackground()
        
        HStack(spacing: 12) {
            WeeklyMomentumBar(dayLetter: "M", fillHeight: 40, isFutureDay: false, tier: .great)
            WeeklyMomentumBar(dayLetter: "T", fillHeight: 32, isFutureDay: false, tier: .good)
            WeeklyMomentumBar(dayLetter: "W", fillHeight: 20, isFutureDay: false, tier: .neutral)
            WeeklyMomentumBar(dayLetter: "T", fillHeight: 10, isFutureDay: false, tier: .low)
            WeeklyMomentumBar(dayLetter: "F", fillHeight: 0, isFutureDay: true, tier: nil)
            WeeklyMomentumBar(dayLetter: "S", fillHeight: 0, isFutureDay: true, tier: nil)
            WeeklyMomentumBar(dayLetter: "S", fillHeight: 0, isFutureDay: true, tier: nil)
        }
        .padding()
    }
}
