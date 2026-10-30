import SwiftUI

/// Sheet for adding a new download with real HTTP/HTTPS test presets and stacked action buttons.
struct AddDownloadView: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var urlText: String = ""
    @State private var customFilename: String = ""
    @State private var suggestedFilename: String = ""
    @State private var validationError: String?
    @State private var isValid: Bool = false
    @State private var detectedPlatform: SupportedPlatform = .direct
    @State private var isResolvingMedia: Bool = false
    
    private let coordinator = DownloadCoordinator.shared
    
    // Real, accessible test files for Phase 3 download engine verification
    private struct PresetDownload: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        let filename: String
        let icon: String
        let sizeNote: String
    }
    
    private let presets: [PresetDownload] = [
        PresetDownload(
            title: "Quick Test: Swift README",
            url: "https://raw.githubusercontent.com/apple/swift/main/README.md",
            filename: "Swift_README.md",
            icon: "doc.text.fill",
            sizeNote: "25 KB"
        ),
        PresetDownload(
            title: "1 MB Benchmark File",
            url: "https://proof.ovh.net/files/1Mb.dat",
            filename: "1Mb_test_file.dat",
            icon: "doc.zipper",
            sizeNote: "1 MB"
        ),
        PresetDownload(
            title: "10 MB Test File",
            url: "https://proof.ovh.net/files/10Mb.dat",
            filename: "10Mb_test_file.dat",
            icon: "externaldrive.fill",
            sizeNote: "10 MB"
        ),
        PresetDownload(
            title: "Sample Video: For Bigger Blazes",
            url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
            filename: "ForBiggerBlazes.mp4",
            icon: "film.fill",
            sizeNote: "15 MB"
        )
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: URL Input
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("https://example.com/file.zip", text: $urlText)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: urlText) { _, newValue in
                                    validateInput(newValue)
                                }
                                .accessibilityLabel("Download URL Input")
                            
                            if !urlText.isEmpty {
                                Button {
                                    urlText = ""
                                    validateInput("")
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Button {
                                if let pasted = UIPasteboard.general.string {
                                    urlText = pasted
                                    validateInput(pasted)
                                }
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel("Paste URL from Clipboard")
                        }
                        
                        if let error = validationError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(AppTheme.errorColor)
                        }
                        
                        if detectedPlatform != .direct {
                            HStack(spacing: 10) {
                                Image(systemName: detectedPlatform.iconName)
                                    .font(.title3)
                                    .foregroundStyle(detectedPlatform == .instagram ? .purple : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(detectedPlatform.rawValue) Detected")
                                        .font(.subheadline.bold())
                                    Text(detectedPlatform == .instagram ? "Client-side video stream extraction" : "Stream extraction via resolver API")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                GlassBadge("Stream", color: detectedPlatform == .instagram ? .purple : .red)
                            }
                            .padding(10)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        }
                    }
                } header: {
                    Text("Download Source URL")
                } footer: {
                    Text(detectedPlatform == .direct ? "Enter a direct HTTP or HTTPS file URL." : "Social media video link detected. Tap 'Resolve & Download' to extract the direct MP4.")
                }
                
                // Section 2: Filename Customization (revealed when valid)
                if isValid {
                    Section("File Name") {
                        TextField(suggestedFilename.isEmpty ? "File name (optional)" : suggestedFilename, text: $customFilename)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                
                // Section 3: Preset / Quick Test URLs
                Section("Quick Test Presets (Real HTTP Files)") {
                    ForEach(presets) { preset in
                        Button {
                            urlText = preset.url
                            customFilename = preset.filename
                            validateInput(preset.url)
                        } label: {
                            HStack {
                                Image(systemName: preset.icon)
                                    .foregroundStyle(AppTheme.accentColor)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(preset.filename)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text(preset.sizeNote)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: .capsule)
                            }
                        }
                    }
                }
                
                // Section 4: Stacked Action Buttons (Up & Down)
                Section {
                    VStack(spacing: 10) {
                        // Top: Primary Start Download Button
                        Button {
                            startDownload()
                        } label: {
                            HStack(spacing: 8) {
                                if isResolvingMedia {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Resolving Media Stream...")
                                        .font(.headline)
                                } else {
                                    Image(systemName: detectedPlatform == .direct ? "arrow.down.circle.fill" : "wand.and.stars")
                                        .font(.headline)
                                    Text(detectedPlatform == .direct ? "Start Download" : "Resolve & Download")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!isValid || isResolvingMedia)
                        .accessibilityLabel("Start Download")
                        
                        // Bottom: Secondary Back Button
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.subheadline.bold())
                                Text("Back to Downloads")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Back to Downloads")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Add Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Top-Left Back Button
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                            Text("Back")
                                .font(.body)
                        }
                    }
                    .accessibilityLabel("Back to Downloads")
                }
                
                // Top-Right Close Button
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
    
    // MARK: - Validation & Actions
    
    private func validateInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isValid = false
            validationError = nil
            suggestedFilename = ""
            detectedPlatform = .direct
            return
        }
        
        if let url = coordinator.validateURL(trimmed) {
            isValid = true
            validationError = nil
            detectedPlatform = MediaResolverService.shared.detectPlatform(from: url)
            let suggested = coordinator.suggestedFilename(for: url)
            suggestedFilename = suggested
        } else {
            isValid = false
            detectedPlatform = .direct
            validationError = "Please enter a valid HTTP or HTTPS URL."
        }
    }
    
    private func startDownload() {
        guard let url = coordinator.validateURL(urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        
        let userSpecified = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if detectedPlatform == .direct {
            let filename = userSpecified.isEmpty ? nil : userSpecified
            store.addDownload(url: url, customFilename: filename)
            dismiss()
        } else {
            isResolvingMedia = true
            validationError = nil
            
            Task { @MainActor in
                do {
                    let resolved = try await MediaResolverService.shared.resolve(url: url)
                    let finalName = userSpecified.isEmpty ? resolved.filename : userSpecified
                    store.addDownload(url: resolved.directURL, customFilename: finalName)
                    isResolvingMedia = false
                    dismiss()
                } catch {
                    isResolvingMedia = false
                    validationError = error.localizedDescription
                }
            }
        }
    }
}
