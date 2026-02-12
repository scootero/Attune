//
//  CheckInTranscriptView.swift
//  Attune
//
//  Full transcript for a check-in. Slice 6.
//

import SwiftUI

struct CheckInTranscriptView: View {
    let checkIn: CheckIn
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(checkIn.createdAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Text(checkIn.transcript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Check-in")
    }
}
