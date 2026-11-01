import SwiftUI
import UserNotifications

@main
struct UniversalDownloadManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    // Shared store instance accessed at the top level
    @StateObject private var store = DownloadStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onAppear {
                    // Request notification permission for background completion alerts
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
                }
                .onOpenURL { incomingURL in
                    _ = store.handleIncomingURL(incomingURL)
                }
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.deepLinkNotification)) { notification in
                    if let incomingURL = notification.object as? URL {
                        _ = store.handleIncomingURL(incomingURL)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        // App was minimized or suspended — flush all download metadata to disk and begin background grace period
                        store.flushToDisk()
                        BackgroundDownloadService.shared.beginBackgroundGracePeriodIfNeeded()
                    case .active:
                        // App returned to foreground — import any pending shared downloads and reconcile running background transfers
                        store.checkAndImportPendingRequests()
                        Task {
                            await store.reconcileTasks()
                            store.processQueue()
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
