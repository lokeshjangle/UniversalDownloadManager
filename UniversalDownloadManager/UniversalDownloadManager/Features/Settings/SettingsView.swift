import SwiftUI

/// Settings view allowing customization of transfer concurrency, save location directory,
/// storage limits, and integration status.
struct SettingsView: View {
    @ObservedObject var store: DownloadStore
    @State private var showingResetAlert: Bool = false
    @State private var showingClearedTempAlert: Bool = false
    @State private var resolverEndpoint: String = MediaResolverService.shared.resolverEndpoint
    @State private var resolverAPIKey: String = MediaResolverService.shared.resolverAPIKey
    
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
                
                // Section 3: Media Stream Resolver (Instagram & YouTube)
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Instagram Reels", systemImage: "camera.circle.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.purple)
                            Spacer()
                            Text("Native On-Device")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.successColor)
                        }
                        Text("Public reels extract directly from page metadata without third-party APIs.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Stream Resolver API", systemImage: "play.rectangle.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        TextField("https://api.cobalt.tools", text: $resolverEndpoint)
                            .font(.subheadline)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: resolverEndpoint) { _, newValue in
                                MediaResolverService.shared.resolverEndpoint = newValue
                            }
                        Text("Used to resolve YouTube and web streams into direct MP4 downloads. Compatible with open-source Cobalt API instances.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("API Key / Bearer Token", systemImage: "key.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        SecureField("Optional (required by api.cobalt.tools)", text: $resolverAPIKey)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: resolverAPIKey) { _, newValue in
                                MediaResolverService.shared.resolverAPIKey = newValue
                            }
                        Text("The official api.cobalt.tools instance requires an API key or JWT token. Self-hosted instances run without an API key.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Media Stream Resolvers")
                } footer: {
                    Text("You can host your own private Cobalt resolver instance and point the endpoint above.")
                }
                
                // Section 4: Browser Integrations Info
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
                // Safari Web Extension Guide
                GlassCard(cornerRadius: 16, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Safari Web Extension", systemImage: "safari.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Spacer()
                            GlassBadge("Active", color: .green)
                        }
                        
                        Text("Universal Download Manager includes a native Safari Web Extension with a toolbar popup for 1-tap background downloading.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Divider().background(Color.white.opacity(0.2))
                        
                        Text("HOW TO ENABLE IN SAFARI")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            stepRow(number: "1", text: "Open iPhone Settings → Apps → Safari.")
                            stepRow(number: "2", text: "Tap 'Extensions' and select 'Universal Download Manager'.")
                            stepRow(number: "3", text: "Toggle the extension switch ON.")
                            stepRow(number: "4", text: "In Safari, tap the puzzle piece (🧩) or 'aA' icon in the address bar to open the popup and download files in the background.")
                        }
                        
                        Divider().background(Color.white.opacity(0.2))
                        
                        Text("PERMISSIONS & PRIVACY")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        Text("• Scoped activeTab permission only: The extension only reads links on the page when you tap the popup.\n• Zero tracking: Browsing history is never stored or transmitted.\n• Direct links only: Video streams (like YouTube) and cookie-protected pages require web browser sessions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Chrome & Share Sheet Guide
                GlassCard(cornerRadius: 16, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Chrome & Share Sheet", systemImage: "square.and.arrow.up.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Spacer()
                            GlassBadge("Active", color: .green)
                        }
                        
                        Text("In Google Chrome, Firefox, or any iOS browser, tap the browser's Share icon and choose 'Universal Download'.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Divider().background(Color.white.opacity(0.2))
                        
                        Text("HOW TO USE IN CHROME")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            stepRow(number: "1", text: "In Chrome, tap the Share icon (or long-press any link → Share Link).")
                            stepRow(number: "2", text: "Select 'Universal Download' from the Share Sheet.")
                            stepRow(number: "3", text: "Review the target URL and customize the filename if desired.")
                            stepRow(number: "4", text: "Tap 'Add to Download Queue'. The file will download in the background!")
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Browser Setup")
    }
    
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue.opacity(0.2)))
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
