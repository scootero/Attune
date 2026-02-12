//
//  IntentionDetailRouteView.swift
//  Attune
//
//  Route wrapper: looks up intention + set from intentionRows, presents IntentionDetailView.
//

import SwiftUI

struct IntentionDetailRouteView: View {
    let intentionId: String
    let intentionRows: [IntentionRow]
    
    var body: some View {
        Group {
            if let row = intentionRows.first(where: { $0.intention.id == intentionId }) {
                IntentionDetailView(intention: row.intention, intentionSet: row.intentionSet)
            } else {
                ContentUnavailableView("Intention not found", systemImage: "questionmark.circle")
            }
        }
    }
}
