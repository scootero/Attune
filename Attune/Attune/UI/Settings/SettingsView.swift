//
//  SettingsView.swift
//  Attune
//
//  Main settings screen with navigation to About and Logs.
//  Modern, sleek design following iOS conventions.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    // State for showing share sheet when exporting data
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var showingExportError = false
    @State private var exportErrorMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                // About section
                Section {
                    NavigationLink(destination: AboutView()) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            Text("About")
                                .font(.body)
                        }
                    }
                }
                
                // Data Export section
                Section {
                    Button(action: exportData) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.fill")
                                .foregroundColor(.orange)
                                .font(.title3)
                            Text("Export All Data")
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export all extractions, corrections, topics, and sessions as JSON files for backup or training purposes.")
                }
                
                // Logs section
                Section {
                    NavigationLink(destination: LogsView()) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("Logs")
                                .font(.body)
                        }
                    }
                } header: {
                    Text("Developer")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingExportSheet) {
                // Share sheet to export the ZIP file
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Failed", isPresented: $showingExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportErrorMessage)
            }
        }
    }
    
    // MARK: - Export Function
    
    /// Exports all app data by sharing the Attune data directory
    /// This allows the user to access all JSON files directly via Files app or AirDrop
    private func exportData() {
        do {
            // Get the base Attune directory which contains all data
            let baseDir = AppPaths.baseDir
            
            // Verify directory exists and has content
            guard FileManager.default.fileExists(atPath: baseDir.path) else {
                exportErrorMessage = "No data to export. Record some sessions first."
                showingExportError = true
                return
            }
            
            // Share the entire Attune directory
            // iOS will let user choose how to export (Files, AirDrop, etc.)
            exportURL = baseDir
            showingExportSheet = true
            
            AppLogger.log(AppLogger.STORE, "Data export initiated for directory: \(baseDir.path)")
            
        } catch {
            // Show error alert
            exportErrorMessage = error.localizedDescription
            showingExportError = true
            AppLogger.log(AppLogger.ERR, "Data export failed: \(error.localizedDescription)")
        }
    }
    
    /// Formats a date for use in filenames (YYYY-MM-DD-HHMMSS)
    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - ShareSheet Helper

/// UIKit ShareSheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    SettingsView()
}
