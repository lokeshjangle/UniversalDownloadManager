import Foundation
import SwiftUI
import Combine

/// Authoritative view model managing all download items, persistence, and real Foundation network transfers.
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
    
    /// Wi-Fi only download setting.
    @Published var wifiOnly: Bool = false
    
    /// Auto-retry failed downloads setting.
    @Published var autoRetry: Bool = true
    
    /// Total bytes currently stored by completed downloads on disk.
    @Published var totalStorageUsed: Int64 = 0
    
    /// Coordinator for queue and concurrency.
    private let coordinator = DownloadCoordinator.shared
    
    /// Persistence layer.
    private let persistence = DownloadPersistence.shared
    
    /// Storage layer.
    private let storage = FileStorageService.shared
    
    init() {
        // Connect as delegate to background service
        BackgroundDownloadService.shared.delegate = self
        
        // Load persisted items or populate initial sample test files
        loadInitialState()
        recalculateStorage()
    }
    
    // MARK: - Initial State & Persistence
    
    private func loadInitialState() {
        let savedItems = persistence.loadItems()
        if !savedItems.isEmpty {
            self.items = savedItems
        } else {
            // First run: provide trusted sample links ready to test
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
    
    // MARK: - Download Actions (Real URLSession)
    
    /// Adds and starts a real download.
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
        
        // Dispatch to coordinator for concurrency scheduling
        coordinator.startOrQueue(item: newItem, allItems: items)
        persistState()
        return newItem
    }
    
    /// Pauses an active download.
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
    
    /// Resumes a paused download.
    func resumeDownload(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.status == .paused || item.status == .queued || item.status == .interrupted else { return }
        
        coordinator.resumeDownload(item: item, allItems: items)
        persistState()
    }
    
    /// Retries a failed or interrupted download.
    func retryDownload(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        
        coordinator.retryDownload(item: item, allItems: items)
        persistState()
    }
    
    /// Cancels a download.
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
    
    /// Deletes a download record and its associated file on disk.
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
    
    /// Pauses all active downloads.
    func pauseAllActive() {
        for item in items where item.status == .downloading {
            coordinator.pauseDownload(id: item.id)
            item.status = .paused
            item.currentSpeed = nil
            item.estimatedTimeRemaining = nil
        }
        persistState()
    }
    
    /// Resumes all paused downloads.
    func resumeAllPaused() {
        for item in items where item.status == .paused {
            coordinator.resumeDownload(item: item, allItems: items)
        }
        persistState()
    }
    
    /// Clears all completed download records and files.
    func clearAllCompleted() {
        for item in items where item.status == .completed {
            if let local = item.localFilename {
                storage.deleteFile(filename: local)
            }
        }
        items.removeAll { $0.status == .completed }
        persistState()
    }
    
    /// Clears all failed download records.
    func clearAllFailed() {
        items.removeAll { $0.status == .failed || $0.status == .cancelled }
        persistState()
    }
    
    /// Processes queue to start any waiting downloads up to concurrency limit.
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
    }
    
    private func loadSampleData() {
        let now = Date()
        
        // Real small and medium downloadable test files from trusted hosts
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
