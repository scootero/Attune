//
//  AppRouter.swift
//  Attune
//
//  Shared navigation state: lets Home momentum card switch to Library → Momentum tab
//  instead of pushing a new view. Used by RootTabView and LibraryView.
//

import Combine
import SwiftUI

/// Consumer-facing root tabs. Settings is presented from Today.
enum RootTab: Int, CaseIterable {
    case home = 0
    case allDay = 1
    case library = 2
    case progress = 3
}

/// App-level routing: tab selection so Home can navigate to the Momentum tab.
@MainActor
final class AppRouter: ObservableObject {
    /// Currently selected root tab so TabView can bind to it
    @Published var selectedRootTab: RootTab = .home

    /// Library sub-tab (used when we navigate to Library)
    @Published var selectedLibraryTab: LibraryTab = .insights

    /// Optional selected date for Momentum so Home can pass the day we should show
    @Published var momentumSelectedDate: Date? = nil

    /// Call from Home momentum card: switch to root Momentum tab and seed its date.
    func navigateToMomentum(date: Date) {
        momentumSelectedDate = date  // Remember which day to show in Momentum
        selectedRootTab = .progress  // Switch root tab to the Momentum screen (formerly Progress slot)
    }
}
