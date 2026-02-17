//
//  ContentView.swift
//  Attune
//
//  Created by Scott Oliver on 1/31/26.
//

import SwiftUI

// ContentView creates AppRouter and passes it down so Home can navigate to Library → Momentum.
struct ContentView: View {
    @StateObject private var appRouter = AppRouter()

    var body: some View {
        RootTabView()
            .environmentObject(appRouter)
    }
}

#Preview {
    ContentView()
}
