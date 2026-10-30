import SwiftUI

/// Settings view allowing customization of transfer concurrency, save location directory,
/// storage limits, and integration status.
struct SettingsView: View {
    @ObservedObject var store: DownloadStore
    @State private var showingResetAlert: Bool = false
    @State private var showingClearedTempAlert: Bool = false
    
    private let storage = FileStorageService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Transfer Rules
                Section("Transfer Configuration") {
                    Stepper(value: $store.maxConcurrentDownloads, in: 1...5) {
                        HStack {
                            Text("Max Concurrent Downloads")
                            Spacer()
                            Text("\(store.maxConcurrentDownloads)")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                    
                    Toggle(isOn: $store.wifiOnly) {
                        Label("Download Over Wi-Fi Only", systemImage: "wifi")
                    }
                    
                    Toggle(isOn: $store.autoRetry) {
                        Label("Auto-Retry Interrupted", systemImage: "arrow.clockwise")
                    }
                }
                
                // Section 2: Storage & Browsable Save Location
                Section {
                    // Navigation link to the Visual Folder Browser
                    NavigationLink {
                        FolderBrowserView(store: store)
                    } label: {
                        HStack {
                            Label("Download Location", systemImage: "folder.fill")
                            Spacer()
                            Text(storage.currentFolderDisplayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                    
                    HStack {
                        Label("Storage Used", systemImage: "internaldrive")
                        Spacer()
                        Text(Formatters.formatBytes(store.totalStorageUsed))
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Clear Downloaded Files & Cache", role: .destructive) {
                        store.clearTemporaryFiles()
                        showingClearedTempAlert = true
                    }
                } header: {
                    Text("Storage & Save Location")
                } footer: {
                    Text("Tap 'Download Location' to visually browse folders or select a destination in the Apple Files app.")
                }
                
                // Section 3: Browser Integrations Info
                Section("Browser Integrations") {
                    NavigationLink {
                        browserInstructionsView
                    } label: {
                        HStack {
                            Label("Safari & Chrome Setup", systemImage: "safari")
                            Spacer()
                            Text("Phase 5-6")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Section 4: Testing & Demo Controls
                Section("Demo & Test Controls") {
                    Button {
                        showingResetAlert = true
                    } label: {
                        Label("Reset with Real Test Links", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(AppTheme.accentColor)
                    }
                }
                
                // Section 5: Background Reliability & About
                Section("System & Reliability") {
                    NavigationLink {
                        BackgroundGuideView()
                    } label: {
                        HStack {
                            Label("Background Reliability Guide", systemImage: "bolt.shield.fill")
                            Spacer()
                            Text("iOS Rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Engine")
                        Spacer()
                        Text("Foundation URLSession")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Background Transfer")
                        Spacer()
                        Text("Active (nsurlsessiond)")
                            .foregroundStyle(AppTheme.successColor)
                    }
                    HStack {
                        Text("Files App Access")
                        Spacer()
                        Text("Enabled (In-Place)")
                            .foregroundStyle(AppTheme.successColor)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Phase 4 Background)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reset Test Links?", isPresented: $showingResetAlert) {
                Button("Reset Data", role: .destructive) {
                    store.resetToSampleData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This populates the queue with real test URLs ready for download.")
            }
            .alert("Storage & Cache Cleared", isPresented: $showingClearedTempAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All downloaded files and resume fragments have been removed from local storage.")
            }
        }
    }
    
    // MARK: - Browser Instructions Subview
    
    private var browserInstructionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GlassCard(cornerRadius: 16, padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Safari Web Extension", systemImage: "safari.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text("Coming in Phase 6. The extension allows you to tap the Safari toolbar extension icon to send any downloadable link directly to this app's background queue.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                GlassCard(cornerRadius: 16, padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Chrome Share Sheet", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Coming in Phase 5. In Google Chrome or any iOS browser, tap the Share icon and select 'Universal Download Manager' to immediately hand off the URL.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Browser Setup")
    }
}
