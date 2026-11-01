import SwiftUI

/// Detailed inspection view for a single download item with file preview and export capabilities.
struct DownloadDetailsView: View {
    @ObservedObject var store: DownloadStore
    let itemId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var showingCopiedAlert: Bool = false
    @State private var photosFeedbackMessage: String?
    
    private var item: DownloadItem? {
        store.items.first(where: { $0.id == itemId })
    }
    
    var body: some View {
        Group {
            if let item {
                contentView(for: item)
            } else {
                ContentUnavailableView(
                    "Download Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This download may have been deleted.")
                )
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func contentView(for item: DownloadItem) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero Header Card
                GlassCard(cornerRadius: 20, padding: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: FileTypeHelper.iconName(for: item.displayFilename))
                            .font(.system(size: 48))
                            .foregroundStyle(FileTypeHelper.iconColor(for: item.displayFilename))
                            .frame(width: 76, height: 76)
                            .background(FileTypeHelper.iconColor(for: item.displayFilename).opacity(0.12), in: .rect(cornerRadius: 18))
                            .padding(.top, 4)
                        
                        Text(item.displayFilename)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        
                        GlassBadge(
                            item.status.displayName,
                            iconName: item.status.iconName,
                            color: AppTheme.color(for: item.status)
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Transfer Progress Card
                GlassCard(cornerRadius: 16, padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transfer Status")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        
                        if let progress = item.progress {
                            VStack(spacing: 6) {
                                ProgressView(value: progress)
                                    .tint(AppTheme.color(for: item.status))
                                
                                HStack {
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.color(for: item.status))
                                    Spacer()
                                    Text(Formatters.formatTransfer(received: item.bytesReceived, total: item.expectedTotalBytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                Text("Downloaded")
                                    .font(.subheadline)
                                Spacer()
                                Text(Formatters.formatBytes(item.bytesReceived))
                                    .font(.subheadline.bold())
                            }
                        }
                        
                        Divider()
                        
                        // Speed & ETA rows
                        metricRow(
                            label: "Transfer Speed",
                            value: Formatters.formatSpeed(item.currentSpeed),
                            icon: "speedometer"
                        )
                        
                        metricRow(
                            label: "Time Remaining",
                            value: Formatters.formatRemainingTime(item.estimatedTimeRemaining),
                            icon: "hourglass"
                        )
                    }
                }
                
                // Error Details Card (if present)
                if let error = item.lastError {
                    GlassCard(cornerRadius: 16, padding: 14, tint: AppTheme.errorColor.opacity(0.1)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(AppTheme.errorColor)
                                Text("Failure Diagnostics")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.errorColor)
                            }
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                // Lifecycle Timestamps Card
                GlassCard(cornerRadius: 16, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Timeline")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        
                        timestampRow(label: "Queued", date: item.createdAt)
                        
                        if let startedAt = item.startedAt {
                            timestampRow(label: "Started", date: startedAt)
                        }
                        
                        if let completedAt = item.completedAt {
                            timestampRow(
                                label: item.status == .completed ? "Completed" : "Ended",
                                date: completedAt
                            )
                        }
                    }
                }
                
                // Technical Details Card
                GlassCard(cornerRadius: 16, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Technical Information")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source URL")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Text(item.originalURLString)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                
                                Spacer()
                                
                                Button {
                                    UIPasteboard.general.string = item.originalURLString
                                    showingCopiedAlert = true
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel("Copy URL")
                            }
                        }
                        
                        Divider()
                        
                        HStack {
                            Text("Resumable Transfer")
                                .font(.caption)
                            Spacer()
                            Text(item.hasResumeData ? "Supported" : "Standard")
                                .font(.caption.bold())
                                .foregroundStyle(item.hasResumeData ? AppTheme.successColor : .secondary)
                        }
                        
                        if let localName = item.localFilename {
                            Divider()
                            HStack {
                                Text("Storage Destination")
                                    .font(.caption)
                                Spacer()
                                Text("Documents/Downloads/\(localName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                // Action Buttons Stack (Up & Down)
                VStack(spacing: 10) {
                    switch item.status {
                    case .downloading:
                        GlassActionButton("Pause Transfer", systemImage: "pause.fill", isProminent: false) {
                            store.pauseDownload(id: item.id)
                        }
                        GlassActionButton("Cancel Transfer", systemImage: "xmark", color: AppTheme.errorColor) {
                            store.cancelDownload(id: item.id)
                        }
                        
                    case .paused:
                        GlassActionButton("Resume Transfer", systemImage: "play.fill", isProminent: true) {
                            store.resumeDownload(id: item.id)
                        }
                        GlassActionButton("Cancel Transfer", systemImage: "xmark", color: AppTheme.errorColor) {
                            store.cancelDownload(id: item.id)
                        }
                        
                    case .failed, .interrupted, .cancelled:
                        GlassActionButton("Retry Transfer", systemImage: "arrow.clockwise", isProminent: true) {
                            store.retryDownload(id: item.id)
                        }
                        GlassActionButton("Delete Record", systemImage: "trash", color: AppTheme.errorColor) {
                            store.deleteDownload(id: item.id)
                            dismiss()
                        }
                        
                    case .completed:
                        if let localName = item.localFilename,
                           let fileURL = FileStorageService.shared.fileURL(for: localName) {
                            
                            if PhotoLibraryService.shared.isMediaFile(filename: localName) {
                                GlassActionButton("Save to Photos (Camera Roll)", systemImage: "photo.badge.arrow.down", isProminent: true) {
                                    saveFileToPhotos(fileURL: fileURL)
                                }
                            }
                            
                            ShareLink(item: fileURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export / Share File")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.glassProminent)
                        }
                        
                        GlassActionButton("Delete File", systemImage: "trash", color: AppTheme.errorColor) {
                            store.deleteDownload(id: item.id)
                            dismiss()
                        }
                        
                    case .queued:
                        GlassActionButton("Cancel Queued", systemImage: "xmark", color: AppTheme.errorColor) {
                            store.cancelDownload(id: item.id)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .overlay {
            if showingCopiedAlert {
                VStack {
                    Spacer()
                    GlassBadge("URL Copied to Clipboard", iconName: "checkmark", color: AppTheme.successColor)
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showingCopiedAlert = false
                    }
                }
            }
            
            if let msg = photosFeedbackMessage {
                VStack {
                    Spacer()
                    GlassBadge(msg, iconName: "photo.badge.checkmark", color: AppTheme.successColor)
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation {
                            photosFeedbackMessage = nil
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Photo Library Action
    
    private func saveFileToPhotos(fileURL: URL) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                try await PhotoLibraryService.shared.saveMediaToPhotos(fileURL: fileURL)
                await MainActor.run {
                    withAnimation {
                        photosFeedbackMessage = "Saved to Photos Camera Roll!"
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        photosFeedbackMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: - Row Helpers
    
    private func metricRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
    }
    
    private func timestampRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.formatDetailedDate(date))
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
