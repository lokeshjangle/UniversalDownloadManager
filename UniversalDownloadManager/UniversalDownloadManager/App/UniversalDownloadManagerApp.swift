import SwiftUI

@main
struct UniversalDownloadManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    // Shared store instance accessed at the top level
    @StateObject private var store = DownloadStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        // App was minimized or suspended — flush all download metadata to disk
                        store.flushToDisk()
                    case .active:
                        // App returned to foreground — reconcile running background transfers
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
