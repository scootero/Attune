//
//  ContentView.swift
//  Attune
//
//  Created by Scott Oliver on 1/31/26.
//

import SwiftUI

// ContentView creates AppRouter, subscription state, and the AI privacy sheet.
struct ContentView: View {
    @StateObject private var appRouter = AppRouter()
    /// Shared StoreKit subscription state for paywall + feature gates.
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    /// Drives the first-launch AI disclosure; starts false if consent already saved.
    @State private var showAIPrivacySheet = !AIPrivacyConsent.hasAccepted

    var body: some View {
        RootTabView()
            .environmentObject(appRouter)
            .environmentObject(subscriptionManager)
            .sheet(isPresented: $showAIPrivacySheet) {
                AIPrivacyDisclosureSheet {
                    // Persist acceptance so OpenAIClient may send transcripts.
                    AIPrivacyConsent.hasAccepted = true
                    showAIPrivacySheet = false
                }
                .interactiveDismissDisabled(true) // Require an explicit Accept tap.
            }
    }
}

#Preview {
    ContentView()
}
