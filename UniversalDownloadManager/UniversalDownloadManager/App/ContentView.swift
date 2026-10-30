import SwiftUI

/// Main container view providing tabbed navigation across all key feature areas.
struct ContentView: View {
    @ObservedObject var store: DownloadStore
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab: String, CaseIterable {
        case dashboard
        case active
        case completed
        case failed
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Dashboard
            NavigationStack {
                DashboardView(store: store)
            }
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
            }
            .tag(Tab.dashboard)
            
            // Tab 2: Active Transfers
            ActiveDownloadsView(store: store)
                .tabItem {
                    Label("Active", systemImage: "arrow.down.circle.fill")
                }
                .badge(activeBadgeCount)
                .tag(Tab.active)
            
            // Tab 3: Completed Downloads
            CompletedDownloadsView(store: store)
                .tabItem {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                }
                .tag(Tab.completed)
            
            // Tab 4: Failed / Issues
            FailedDownloadsView(store: store)
                .tabItem {
                    Label("Issues", systemImage: "exclamationmark.triangle.fill")
                }
                .badge(failedBadgeCount)
                .tag(Tab.failed)
            
            // Tab 5: Settings
            SettingsView(store: store)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
    }
    
    // MARK: - Badges
    
    private var activeBadgeCount: Int {
        store.items.filter { $0.status == .downloading }.count
    }
    
    private var failedBadgeCount: Int {
        store.failedItems.count
    }
}
