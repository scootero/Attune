//
//  AboutView.swift
//  Attune
//
//  About screen displaying app information.
//  Clean, centered layout with modern typography.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App icon placeholder (using SF Symbol)
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            // App name
            Text("Attune")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            
            // Version
            Text("Version 1.0")
                .font(.title3)
                .foregroundColor(.secondary)
            
            // Creator
            Text("Made by Scott")
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        AboutView()
    }
}
