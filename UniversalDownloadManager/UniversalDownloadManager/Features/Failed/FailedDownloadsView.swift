import SwiftUI

/// Screen displaying failed, cancelled, and interrupted downloads with diagnostic details and retry controls.
struct FailedDownloadsView: View {
    @ObservedObject var store: DownloadStore
    @State private var showingClearConfirmation: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !store.failedItems.isEmpty {
                        // Diagnostic Banner
                        GlassCard(cornerRadius: 16, padding: 14, tint: AppTheme.errorColor.opacity(0.08)) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.errorColor)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(store.failedItems.count) Issues")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text("Transfers can often be resumed if the server supports range requests.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button {
                                    for item in store.failedItems {
                                        store.retryDownload(id: item.id)
                                    }
                                } label: {
                                    Label("Retry All", systemImage: "arrow.clockwise")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                    }
                    
                    // Failed Items List
                    if store.failedItems.isEmpty {
                        GlassEmptyState(
                            title: "All Clear!",
                            message: "No failed or interrupted transfers. Your download queue is running smoothly.",
                            systemImage: "checkmark.shield.fill"
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(store.failedItems) { item in
                                NavigationLink(destination: DownloadDetailsView(store: store, itemId: item.id)) {
                                    DownloadRowView(
                                        item: item,
                                        onRetry: { store.retryDownload(id: item.id) },
                                        onDelete: { store.deleteDownload(id: item.id) }
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90) // Clear TabBar
            }
            .navigationTitle("Failed & Issues")
            .toolbar {
                if !store.failedItems.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear Failed", role: .destructive) {
                            showingClearConfirmation = true
                        }
                        .foregroundStyle(AppTheme.errorColor)
                    }
                }
            }
            .confirmationDialog(
                "Clear Failed Downloads?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Failed Records", role: .destructive) {
                    store.clearAllFailed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all failed and interrupted records.")
            }
        }
    }
}
