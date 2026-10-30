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
        .overlay(alignment: .top) {
            if let msg = store.notificationMessage {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text(msg)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        withAnimation {
                            store.notificationMessage = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation {
                            store.notificationMessage = nil
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.notificationMessage)
    }
    
    // MARK: - Badges
    
    private var activeBadgeCount: Int {
        store.items.filter { $0.status == .downloading }.count
    }
    
    private var failedBadgeCount: Int {
        store.failedItems.count
    }
}
