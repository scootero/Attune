//
//  SessionRecapView.swift
//  Pondera
//
//  Read-only presentation for the post-session recap.
//

import SwiftUI

enum SessionRecapFeature {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
}

struct SessionRecapView: View {
    let recap: SessionRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SESSION RECAP", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(AttuneTheme.accent)

            Text(recap.headline)
                .font(.title2.bold())
                .foregroundStyle(AttuneTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let quote = recap.quote {
                Text("You said: “\(quote)”")
                    .font(.body)
                    .italic()
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .attuneCard()
        .accessibilityElement(children: .combine)
    }
}

/// A brief, tappable completion treatment. The full recap remains available in
/// `SessionDetailView`; this view is intentionally compact enough to behave like
/// confirmation rather than a second destination.
struct SessionRecapPreviewCard: View {
    let recap: SessionRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                Text("SESSION HIGHLIGHT")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .opacity(0.8)
            }
            .foregroundStyle(AttuneTheme.accent)

            Text(recap.headline)
                .font(.title3.weight(.bold))
                .foregroundStyle(AttuneTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let quote = recap.quote {
                Text("“\(quote)”")
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text("Tap to see more")
                Image(systemName: "arrow.up.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.86))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SessionRecapPreviewBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [AttuneTheme.accent.opacity(0.9), AttuneTheme.accentSecondary.opacity(0.75), Color.pink.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .shadow(color: AttuneTheme.accent.opacity(0.22), radius: 18, x: -5, y: 6)
        .shadow(color: AttuneTheme.accentSecondary.opacity(0.20), radius: 20, x: 8, y: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct SessionRecapPreviewBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.16, blue: 0.20),
                    Color(red: 0.12, green: 0.08, blue: 0.25),
                    Color(red: 0.20, green: 0.07, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AttuneTheme.accent.opacity(0.34), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 230
            )

            RadialGradient(
                colors: [Color.pink.opacity(0.24), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 210
            )

            // Low-contrast scan lines add texture without competing with the recap.
            VStack(spacing: 7) {
                ForEach(0..<22, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.025))
                        .frame(height: 1)
                }
            }
            .rotationEffect(.degrees(-4))
            .scaleEffect(1.15)
        }
    }
}

struct SessionRecapSheet: View {
    let sessionId: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SessionDetailView(sessionId: sessionId)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
