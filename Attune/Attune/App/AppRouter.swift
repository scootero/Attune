//
//  AppRouter.swift
//  Attune
//
//  Shared navigation state: lets Home momentum card switch to Library → Momentum tab
//  instead of pushing a new view. Used by RootTabView and LibraryView.
//

import Combine
import SwiftUI

/// Root tabs (Home, All Day, Library, Settings, Progress)
enum RootTab: Int, CaseIterable {
    case home = 0  // Root tab for Home
    case allDay = 1  // Root tab for All Day
    case library = 2  // Root tab for Library
    case settings = 3  // Root tab for Settings
    case progress = 4  // Root tab for Progress
}

/// App-level routing: tab selection so Home can navigate to the Momentum tab.
@MainActor
final class AppRouter: ObservableObject {
    /// Currently selected root tab so TabView can bind to it
    @Published var selectedRootTab: RootTab = .home

    /// Library sub-tab (used when we navigate to Library)
    @Published var selectedLibraryTab: LibraryTab = .sessions

    /// Optional selected date for Momentum so Home can pass the day we should show
    @Published var momentumSelectedDate: Date? = nil

    /// Call from Home momentum card: switch to root Momentum tab and seed its date.
    func navigateToMomentum(date: Date) {
        momentumSelectedDate = date  // Remember which day to show in Momentum
        selectedRootTab = .progress  // Switch root tab to the Momentum screen (formerly Progress slot)
    }
}
