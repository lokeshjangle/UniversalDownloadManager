import Foundation
import SwiftUI
import Combine

/// Authoritative view model managing all download items, persistence, customizable save directories,
/// background URLSession lifecycle handling, and task reconciliation on relaunch.
@MainActor
final class DownloadStore: ObservableObject, DownloadServiceDelegate {
    /// All download items in the store.
    @Published var items: [DownloadItem] = []
    
    /// Concurrency limit setting.
    @Published var maxConcurrentDownloads: Int = 3 {
        didSet {
            DownloadCoordinator.shared.maxConcurrentDownloads = maxConcurrentDownloads
            processQueue()
        }
    }
    
    /// Currently chosen download folder (relative to app Documents).
    @Published var currentDownloadFolder: String = "Downloads"
    
    /// Wi-Fi only download setting.
    @Published var wifiOnly: Bool = false
    
    /// Auto-retry failed downloads setting.
    @Published var autoRetry: Bool = true
    
    /// Total bytes currently stored by completed downloads on disk.
    @Published var totalStorageUsed: Int64 = 0
    
    /// User-facing transient notification banner (e.g., download added from Chrome)
    @Published var notificationMessage: String?
    
    /// Coordinator for queue and concurrency.
    private let coordinator = DownloadCoordinator.shared
    
    /// Persistence layer.
    private let persistence = DownloadPersistence.shared
    
    /// Storage layer.
    private let storage = FileStorageService.shared
    
    init() {
        // Connect as delegate to background service
        BackgroundDownloadService.shared.delegate = self
        
        // Load active download folder
        self.currentDownloadFolder = storage.currentSubdirectory
        
        // Load persisted items or populate initial sample test files
        loadInitialState()
        recalculateStorage()
        
        // Import any requests handed off from Chrome Share Sheet or Safari
        checkAndImportPendingRequests()
        
        // Reconcile any in-flight background tasks from previous session
        Task {
            await self.reconcileTasks()
            self.processQueue()
        }
    }
    
    // MARK: - Save Location Customization
    
    func setDownloadLocation(_ newSubdirectory: String) {
        storage.selectInAppFolder(named: newSubdirectory)
        self.currentDownloadFolder = storage.currentFolderDisplayName
    }
    
    // MARK: - Relaunch & Background Reconciliation (Phase 4)
    
    /// Reconciles saved download items with actual URLSession background tasks running in the system daemon.
    func reconcileTasks() async {
        let filenameMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.displayFilename) })
        let runningIDs = await BackgroundDownloadService.shared.reconcileRunningTasks(knownFilenames: filenameMap)
        
        for item in items {
            // 1. Verify completed items still exist on disk (prevents false completion reporting)
            if item.status == .completed {
                if let local = item.localFilename, !storage.fileExists(filename: local) {
                    item.status = .failed
                    item.lastError = "Downloaded file was removed or is missing from disk."
                }
            }
            
            // 2. Reconcile downloading items
            if item.status == .downloading {
                if runningIDs.contains(item.id) {
                    // Task is actively running in system daemon!
                    continue
                }
                
                // If the file is already finished on disk, mark as completed
                if let local = item.localFilename, storage.fileExists(filename: local) {
                    item.status = .completed
                    item.currentSpeed = nil
                    item.estimatedTimeRemaining = nil
                    continue
                }
                
                // If resume data was saved before termination, mark as paused/interrupted
                if storage.readResumeData(for: item.id) != nil {
                    item.status = .interrupted
                    item.hasResumeData = true
                    item.lastError = "Network or app interrupted. Tap Retry to resume."
                    item.currentSpeed = nil
                    item.estimatedTimeRemaining = nil
                    continue
                }
                
                // Otherwise mark interrupted so user can retry safely
                item.status = .interrupted
                item.lastError = "Transfer interrupted. Tap Retry to restart."
                item.currentSpeed = nil
                item.estimatedTimeRemaining = nil
            }
        }
        
        // 3. Clean stale temporary files & expired resume fragments
        let activeIDs = Set(items.filter { $0.status == .downloading || $0.status == .paused || $0.status == .interrupted }.map { $0.id })
        storage.cleanStaleTemporaryFiles(activeDownloadIDs: activeIDs)
        
        persistState()
    }
    
    /// Flushes all metadata to persistent storage immediately (called on scenePhase transition to background).
    func flushToDisk() {
        persistState()
    }
    
    // MARK: - Initial State & Persistence
    
    private func loadInitialState() {
        let savedItems = persistence.loadItems()
        if !savedItems.isEmpty {
            self.items = savedItems
        } else {
            loadSampleData()
        }
    }
    
    private func persistState() {
        persistence.saveItems(items)
        recalculateStorage()
    }
    
    // MARK: - Computed Subsets
    
    var activeItems: [DownloadItem] {
        items.filter { $0.status == .downloading || $0.status == .paused || $0.status == .queued || $0.status == .interrupted }
    }
    
    var completedItems: [DownloadItem] {
        items.filter { $0.status == .completed }
    }
    
    var failedItems: [DownloadItem] {
        items.filter { $0.status == .failed || $0.status == .interrupted }
    }
    
    var aggregateSpeed: Double {
        items.filter { $0.status == .downloading }
             .compactMap { $0.currentSpeed }
             .reduce(0, +)
    }
    
    // MARK: - External / Share Handoff (Phase 5)
    
    /// Imports any requests pending in the shared storage (handed off from Chrome Share Sheet or Safari).
    func checkAndImportPendingRequests() {
        let pending = PendingRequestsStore.shared.fetchAndClearPendingRequests()
        for request in pending {
            if let validURL = coordinator.validateURL(request.urlString) {
                let item = addDownload(url: validURL, customFilename: request.customFilename)
                notificationMessage = "Added download from \(request.sourceApp ?? "Chrome"): \(item.displayFilename)"
            }
        }
    }
    
    /// Handles custom URL scheme requests: universaldownload://add?url=<target>&name=<optional>
    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "universaldownload" else {
            return false
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            notificationMessage = "Malformed universaldownload link received."
            return false
        }
        
        let host = components.host?.lowercased()
        let path = components.path.lowercased()
        
        // Accept host "add" or "share", or path "/add" or "/share"
        guard host == "add" || host == "share" || path == "/add" || path == "/share" || host == nil else {
            return false
        }
        
        // Extract "url" query param
        guard let urlItem = components.queryItems?.first(where: { $0.name.lowercased() == "url" }),
              let rawTargetURLString = urlItem.value,
              let targetURL = coordinator.validateURL(rawTargetURLString) else {
            notificationMessage = "Unable to add download: Invalid or unsupported HTTP/HTTPS URL."
            return false
        }
        
        let nameItem = components.queryItems?.first(where: { $0.name.lowercased() == "name" || $0.name.lowercased() == "filename" })
        let customName = nameItem?.value
        
        let item = addDownload(url: targetURL, customFilename: customName)
        notificationMessage = "Added download from Chrome: \(item.displayFilename)"
        return true
    }
    
    // MARK: - Download Actions (Real URLSession)
    
    @discardableResult
    func addDownload(url: URL, customFilename: String? = nil) -> DownloadItem {
        let filename: String
        if let custom = customFilename, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filename = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            filename = coordinator.suggestedFilename(for: url)
        }
        
        let newItem = DownloadItem(
            url: url,
            displayFilename: filename,
            status: .queued,
            bytesReceived: 0,
            expectedTotalBytes: nil,
            createdAt: Date()
        )
        
        items.insert(newItem, at: 0)
        persistState()
        
        coordinator.startOrQueue(item: newItem, allItems: items)
        persistState()
        return newItem
    }
    
    func pauseDownload(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.status == .downloading || item.status == .queued else { return }
        
        coordinator.pauseDownload(id: id)
        item.status = .paused
        item.currentSpeed = nil
        item.estimatedTimeRemaining = nil
        persistState()
        processQueue()
    }
    
    func resumeDownload(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.status == .paused || item.status == .queued || item.status == .interrupted else { return }
        
        coordinator.resumeDownload(item: item, allItems: items)
        persistState()
    }
    
    func retryDownload(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        coordinator.retryDownload(item: item, allItems: items)
        persistState()
    }
    
    func cancelDownload(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        coordinator.cancelDownload(id: id)
        item.status = .cancelled
        item.currentSpeed = nil
        item.estimatedTimeRemaining = nil
        item.completedAt = Date()
        persistState()
        processQueue()
    }
    
    func deleteDownload(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        
        if item.status == .downloading {
            coordinator.cancelDownload(id: id)
        }
        
        if let local = item.localFilename {
            storage.deleteFile(filename: local)
        }
        storage.removeResumeData(for: id)
        
        items.remove(at: index)
        persistState()
        processQueue()
    }
    
    func pauseAllActive() {
        for item in items where item.status == .downloading {
            coordinator.pauseDownload(id: item.id)
            item.status = .paused
            item.currentSpeed = nil
            item.estimatedTimeRemaining = nil
        }
        persistState()
    }
    
    func resumeAllPaused() {
        for item in items where item.status == .paused {
            coordinator.resumeDownload(item: item, allItems: items)
        }
        persistState()
    }
    
    func clearAllCompleted() {
        for item in items where item.status == .completed {
            if let local = item.localFilename {
                storage.deleteFile(filename: local)
            }
        }
        items.removeAll { $0.status == .completed }
        persistState()
    }
    
    func clearAllFailed() {
        items.removeAll { $0.status == .failed || $0.status == .cancelled }
        persistState()
    }
    
    func processQueue() {
        coordinator.processQueue(items: items)
    }
    
    // MARK: - DownloadServiceDelegate Callbacks
    
    func downloadDidUpdateProgress(id: UUID, bytesReceived: Int64, totalBytes: Int64?, speed: Double?, eta: TimeInterval?) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        item.bytesReceived = bytesReceived
        if let total = totalBytes {
            item.expectedTotalBytes = total
        }
        item.currentSpeed = speed
        item.estimatedTimeRemaining = eta
        
        if item.status != .downloading {
            item.status = .downloading
        }
        objectWillChange.send()
    }
    
    func downloadDidComplete(id: UUID, localFilename: String, fileSize: Int64) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        item.status = .completed
        item.localFilename = localFilename
        item.displayFilename = localFilename
        item.bytesReceived = fileSize
        item.expectedTotalBytes = fileSize
        item.currentSpeed = nil
        item.estimatedTimeRemaining = nil
        item.completedAt = Date()
        
        persistState()
        processQueue()
    }
    
    func downloadDidFail(id: UUID, error: String, canResume: Bool) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        item.status = canResume ? .interrupted : .failed
        item.lastError = error
        item.hasResumeData = canResume
        item.currentSpeed = nil
        item.estimatedTimeRemaining = nil
        item.completedAt = Date()
        
        persistState()
        processQueue()
    }
    
    func downloadDidPause(id: UUID, hasResumeData: Bool) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        item.status = .paused
        item.hasResumeData = hasResumeData
        item.currentSpeed = nil
        item.estimatedTimeRemaining = nil
        
        persistState()
        processQueue()
    }
    
    func downloadDidReconcile(runningIDs: Set<UUID>) {
        objectWillChange.send()
    }
    
    // MARK: - Storage Management
    
    private func recalculateStorage() {
        totalStorageUsed = storage.totalStorageUsed()
    }
    
    func clearTemporaryFiles() {
        storage.clearAllFiles()
        recalculateStorage()
    }
    
    // MARK: - Sample & Reset Data
    
    func resetToSampleData() {
        loadSampleData()
        persistState()
        processQueue()
    }
    
    private func loadSampleData() {
        let now = Date()
        
        items = [
            DownloadItem(
                id: UUID(),
                url: URL(string: "https://proof.ovh.net/files/1Mb.dat")!,
                displayFilename: "1Mb_test_file.dat",
                status: .queued,
                bytesReceived: 0,
                expectedTotalBytes: 1_048_576,
                createdAt: now
            ),
            DownloadItem(
                id: UUID(),
                url: URL(string: "https://raw.githubusercontent.com/apple/swift/main/README.md")!,
                displayFilename: "Swift_README.md",
                status: .queued,
                bytesReceived: 0,
                expectedTotalBytes: 25_000,
                createdAt: now.addingTimeInterval(-10)
            )
        ]
    }
}
