//
//  SessionRecapView.swift
//  Attune
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
