import SwiftUI

/// Screen dedicated to active, queued, and paused download transfers with stacked controls.
struct ActiveDownloadsView: View {
    @ObservedObject var store: DownloadStore
    @State private var selectedFilter: ActiveFilter = .all
    @State private var showingAddSheet: Bool = false
    @State private var selectedDetailId: UUID?
    
    enum ActiveFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case downloading = "Downloading"
        case paused = "Paused"
        case queued = "Queued"
        
        var id: String { rawValue }
    }
    
    private var filteredItems: [DownloadItem] {
        switch selectedFilter {
        case .all:
            return store.activeItems
        case .downloading:
            return store.items.filter { $0.status == .downloading }
        case .paused:
            return store.items.filter { $0.status == .paused }
        case .queued:
            return store.items.filter { $0.status == .queued }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Summary Banner with STACKED Controls (Up and Down)
                    GlassCard(cornerRadius: 18, padding: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Top Info Row
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Active Speed")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text(Formatters.formatSpeed(store.aggregateSpeed))
                                        .font(.title2.bold())
                                        .foregroundStyle(AppTheme.accentColor)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Active Items")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text("\(store.activeItems.count)")
                                        .font(.title3.bold())
                                        .foregroundStyle(.primary)
                                }
                            }
                            
                            Divider()
                            
                            // Stacked Up and Down Controls
                            VStack(spacing: 8) {
                                // 1. Pause All Button (Top)
                                Button {
                                    store.pauseAllActive()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "pause.fill")
                                            .font(.subheadline.bold())
                                        Text("Pause All Active Transfers")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.glass)
                                .disabled(store.items.allSatisfy { $0.status != .downloading })
                                
                                // 2. Resume All Button (Directly Underneath)
                                Button {
                                    store.resumeAllPaused()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                            .font(.subheadline.bold())
                                        Text("Resume All Paused Transfers")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.glassProminent)
                                .disabled(store.items.allSatisfy { $0.status != .paused })
                            }
                        }
                    }
                    
                    // Filter Picker
                    Picker("Filter Active", selection: $selectedFilter) {
                        ForEach(ActiveFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Downloads List
                    if filteredItems.isEmpty {
                        GlassEmptyState(
                            title: "No Active Transfers",
                            message: "There are currently no transfers matching this filter. Tap + to start a download.",
                            systemImage: "arrow.down.circle",
                            buttonTitle: "Add Download"
                        ) {
                            showingAddSheet = true
                        }
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredItems) { item in
                                DownloadRowView(
                                    item: item,
                                    onPause: {
                                        store.pauseDownload(id: item.id)
                                    },
                                    onResume: {
                                        store.resumeDownload(id: item.id)
                                    },
                                    onCancel: {
                                        store.cancelDownload(id: item.id)
                                    },
                                    onRetry: {
                                        store.retryDownload(id: item.id)
                                    },
                                    onDelete: {
                                        store.deleteDownload(id: item.id)
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedDetailId = item.id
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
            .navigationTitle("Active Transfers")
            .navigationDestination(isPresented: Binding(
                get: { selectedDetailId != nil },
                set: { if !$0 { selectedDetailId = nil } }
            )) {
                if let id = selectedDetailId {
                    DownloadDetailsView(store: store, itemId: id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Add Download")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddDownloadView(store: store)
            }
        }
    }
}
