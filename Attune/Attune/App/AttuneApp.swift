//
//  AttuneApp.swift
//  Attune
//
//  Created by Scott Oliver on 1/31/26.
//

import SwiftUI
import SwiftData

@main
struct AttuneApp: App {
    @Environment(\.scenePhase) private var scenePhase // Observe foreground/background transitions to refresh reminder scheduling.
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in // Refresh reminder when app becomes active so today's state is always up-to-date.
            if newPhase == .active { // Only refresh on active to avoid unnecessary work in background/inactive states.
                DailyReminderNotificationService.shared.refreshReminderForToday() // Recompute reminder at user-selected time based on latest check-ins/progress.
            }
        }
    }
}
