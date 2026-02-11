//
//  MetadataRow.swift
//  Attune
//
//  Shared component for displaying metadata as label: value pairs.
//

import SwiftUI

/// Simple metadata row view (label: value)
struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
