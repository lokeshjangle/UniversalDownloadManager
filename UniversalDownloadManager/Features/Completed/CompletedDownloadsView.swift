import SwiftUI

/// Screen displaying all successfully completed downloads with search and management actions.
struct CompletedDownloadsView: View {
    @ObservedObject var store: DownloadStore
    @State private var searchText: String = ""
    @State private var showingClearConfirmation: Bool = false
    
    private var filteredItems: [DownloadItem] {
        let completed = store.completedItems
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return completed
        }
        return completed.filter {
            $0.displayFilename.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Storage Summary Card
                    GlassCard(cornerRadius: 16, padding: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: "internaldrive.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.successColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Storage Used")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(Formatters.formatBytes(store.totalStorageUsed))
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Files Saved")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(store.completedItems.count)")
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search completed files...", text: $searchText)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    
                    // Completed Items List
                    if filteredItems.isEmpty {
                        GlassEmptyState(
                            title: searchText.isEmpty ? "No Completed Downloads" : "No Matches Found",
                            message: searchText.isEmpty
                                ? "Files you download will be stored persistently and shown here."
                                : "No completed files matched \"\(searchText)\".",
                            systemImage: "checkmark.circle"
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredItems) { item in
                                NavigationLink(destination: DownloadDetailsView(store: store, itemId: item.id)) {
                                    DownloadRowView(
                                        item: item,
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
            .navigationTitle("Completed")
            .toolbar {
                if !store.completedItems.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                        .foregroundStyle(AppTheme.errorColor)
                    }
                }
            }
            .confirmationDialog(
                "Clear Completed History?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Completed", role: .destructive) {
                    store.clearAllCompleted()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all completed download records from the list.")
            }
        }
    }
}
