import SwiftUI

/// The main dashboard view providing a unified overview of all active, queued, completed, and failed transfers.
struct DashboardView: View {
    @ObservedObject var store: DownloadStore
    @State private var showingAddDownload = false
    @State private var showingBrowser = false
    @State private var selectedTab: DashboardFilter = .all
    @State private var selectedDetailId: UUID?
    
    enum DashboardFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case completed = "Completed"
        case failed = "Issues"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Glass Summary Card
                GlassCard(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Universal Download Manager")
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                
                                Text(headerSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Speed Pill
                            if store.aggregateSpeed > 0 {
                                GlassBadge(
                                    Formatters.formatSpeed(store.aggregateSpeed),
                                    iconName: "arrow.down",
                                    color: AppTheme.accentColor
                                )
                            }
                        }
                        
                        // Summary Metric Cards Grid (fits all iPhone screen widths)
                        HStack(spacing: 6) {
                            GlassMetricCard(
                                title: "Active",
                                value: "\(store.items.filter { $0.status == .downloading }.count)",
                                iconName: "arrow.down.circle.fill",
                                color: AppTheme.accentColor
                            )
                            
                            GlassMetricCard(
                                title: "Queued",
                                value: "\(store.items.filter { $0.status == .queued || $0.status == .paused }.count)",
                                iconName: "clock.fill",
                                color: AppTheme.warningColor
                            )
                            
                            GlassMetricCard(
                                title: "Done",
                                value: "\(store.completedItems.count)",
                                iconName: "checkmark.circle.fill",
                                color: AppTheme.successColor
                            )
                            
                            GlassMetricCard(
                                title: "Issues",
                                value: "\(store.failedItems.count)",
                                iconName: "exclamationmark.triangle.fill",
                                color: AppTheme.errorColor
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Section Filter Segmented Control
                Picker("Filter", selection: $selectedTab) {
                    ForEach(DashboardFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                
                // Main Content Area strictly bounded within margins
                contentSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 90) // Clear floating bottom TabBar
        }
        .navigationTitle("Downloads")
        .navigationDestination(isPresented: Binding(
            get: { selectedDetailId != nil },
            set: { if !$0 { selectedDetailId = nil } }
        )) {
            if let id = selectedDetailId {
                DownloadDetailsView(store: store, itemId: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingBrowser = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("Browser")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.purple)
                }
                .accessibilityLabel("In-App Browser")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddDownload = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Add Download")
            }
        }
        .sheet(isPresented: $showingAddDownload) {
            AddDownloadView(store: store)
        }
        .sheet(isPresented: $showingBrowser) {
            InAppBrowserView(store: store)
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var contentSection: some View {
        switch selectedTab {
        case .all:
            allSectionsView
        case .active:
            activeOnlyView
        case .completed:
            completedOnlyView
        case .failed:
            failedOnlyView
        }
    }
    
    // All Sections View
    @ViewBuilder
    private var allSectionsView: some View {
        VStack(spacing: 18) {
            // 1. In-Progress Section
            if !store.activeItems.isEmpty {
                VStack(spacing: 8) {
                    GlassSectionHeader(
                        "In Progress",
                        count: store.activeItems.count,
                        actionTitle: "Pause All"
                    ) {
                        store.pauseAllActive()
                    }
                    
                    LazyVStack(spacing: 10) {
                        ForEach(store.activeItems) { item in
                            downloadCard(for: item)
                        }
                    }
                }
            }
            
            // 2. Issues Section (if any)
            if !store.failedItems.isEmpty {
                VStack(spacing: 8) {
                    GlassSectionHeader(
                        "Attention Needed",
                        count: store.failedItems.count,
                        actionTitle: "Retry All"
                    ) {
                        for item in store.failedItems {
                            store.retryDownload(id: item.id)
                        }
                    }
                    
                    LazyVStack(spacing: 10) {
                        ForEach(store.failedItems) { item in
                            downloadCard(for: item)
                        }
                    }
                }
            }
            
            // 3. Recently Completed Section
            if !store.completedItems.isEmpty {
                VStack(spacing: 8) {
                    GlassSectionHeader(
                        "Recently Completed",
                        count: store.completedItems.count
                    )
                    
                    LazyVStack(spacing: 10) {
                        ForEach(store.completedItems.prefix(3)) { item in
                            downloadCard(for: item)
                        }
                    }
                }
            }
            
            if store.items.isEmpty {
                GlassEmptyState(
                    title: "No Downloads Yet",
                    message: "Tap the + button to add a download or share links from Safari & Chrome.",
                    systemImage: "arrow.down.circle",
                    buttonTitle: "Add First Download"
                ) {
                    showingAddDownload = true
                }
            }
        }
    }
    
    // Active Only View
    @ViewBuilder
    private var activeOnlyView: some View {
        if store.activeItems.isEmpty {
            GlassEmptyState(
                title: "No Active Downloads",
                message: "All current transfers have completed or are finished.",
                systemImage: "arrow.down.circle",
                buttonTitle: "Start a Download"
            ) {
                showingAddDownload = true
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(store.activeItems) { item in
                    downloadCard(for: item)
                }
            }
        }
    }
    
    // Completed Only View
    @ViewBuilder
    private var completedOnlyView: some View {
        if store.completedItems.isEmpty {
            GlassEmptyState(
                title: "No Completed Files",
                message: "Finished downloads will be stored and listed here.",
                systemImage: "checkmark.circle"
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(store.completedItems) { item in
                    downloadCard(for: item)
                }
            }
        }
    }
    
    // Failed Only View
    @ViewBuilder
    private var failedOnlyView: some View {
        if store.failedItems.isEmpty {
            GlassEmptyState(
                title: "No Issues",
                message: "No failed or interrupted transfers.",
                systemImage: "checkmark.shield.fill"
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(store.failedItems) { item in
                    downloadCard(for: item)
                }
            }
        }
    }
    
    // Card Helper
    private func downloadCard(for item: DownloadItem) -> some View {
        DownloadRowView(
            item: item,
            onPause: { store.pauseDownload(id: item.id) },
            onResume: { store.resumeDownload(id: item.id) },
            onCancel: { store.cancelDownload(id: item.id) },
            onRetry: { store.retryDownload(id: item.id) },
            onDelete: { store.deleteDownload(id: item.id) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDetailId = item.id
        }
    }
    
    private var headerSubtitle: String {
        let activeCount = store.items.filter { $0.status == .downloading }.count
        if activeCount > 0 {
            return "\(activeCount) active \(activeCount == 1 ? "transfer" : "transfers") in progress"
        } else {
            return "All transfers completed or paused"
        }
    }
}
