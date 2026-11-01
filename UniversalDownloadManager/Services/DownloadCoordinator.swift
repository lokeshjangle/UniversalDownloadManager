import Foundation
import Combine

/// Coordinator responsible for URL validation, queue scheduling, concurrency enforcement,
/// and dispatching tasks to the background download engine.
@MainActor
final class DownloadCoordinator: ObservableObject {
    /// Shared singleton instance.
    static let shared = DownloadCoordinator()
    
    /// Maximum number of concurrent downloads allowed at once.
    @Published var maxConcurrentDownloads: Int = 3
    
    /// Reference to the underlying download engine.
    private let downloadService = BackgroundDownloadService.shared
    
    private init() {}
    
    // MARK: - URL Validation & Helpers
    
    /// Validates that a URL is a supported HTTP or HTTPS URL.
    /// - Parameter urlString: The URL string to validate.
    /// - Returns: A valid `URL` if the string is a supported download URL, nil otherwise.
    func validateURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
    
    /// Determines whether a URL points to local/private network addresses (localhost, 127.0.0.1, 192.168.x.x, etc.)
    func isPrivateOrLocalAddress(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        if host == "localhost" || host.hasSuffix(".local") || host == "127.0.0.1" || host == "::1" {
            return true
        }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("169.254.") {
            return true
        }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), second >= 16 && second <= 31 {
                return true
            }
        }
        return false
    }
    
    /// Derives a clean filename from a URL.
    /// - Parameter url: The URL to derive a filename from.
    /// - Returns: A suggested filename string.
    func suggestedFilename(for url: URL) -> String {
        let lastComponent = url.lastPathComponent
        if lastComponent.isEmpty || lastComponent == "/" {
            return "download"
        }
        let clean = lastComponent.removingPercentEncoding ?? lastComponent
        return clean.isEmpty ? "download" : clean
    }
    
    // MARK: - Queue & Concurrency Management
    
    /// Checks the queue and starts any pending queued items if below concurrency limit.
    func processQueue(items: [DownloadItem]) {
        let currentlyDownloading = items.filter { $0.status == .downloading }.count
        let availableSlots = maxConcurrentDownloads - currentlyDownloading
        
        guard availableSlots > 0 else { return }
        
        let queuedItems = items.filter { $0.status == .queued }
        for item in queuedItems.prefix(availableSlots) {
            guard let url = item.originalURL else { continue }
            item.status = .downloading
            item.startedAt = Date()
            downloadService.startDownload(id: item.id, url: url, filename: item.displayFilename)
        }
    }
    
    /// Starts or queues a new download item.
    func startOrQueue(item: DownloadItem, allItems: [DownloadItem]) {
        let currentlyDownloading = allItems.filter { $0.status == .downloading }.count
        
        if currentlyDownloading < maxConcurrentDownloads {
            guard let url = item.originalURL else { return }
            item.status = .downloading
            item.startedAt = Date()
            downloadService.startDownload(id: item.id, url: url, filename: item.displayFilename)
        } else {
            item.status = .queued
        }
    }
    
    /// Pauses an active download.
    func pauseDownload(id: UUID) {
        downloadService.pauseDownload(id: id)
    }
    
    /// Resumes a paused download.
    func resumeDownload(item: DownloadItem, allItems: [DownloadItem]) {
        let currentlyDownloading = allItems.filter { $0.status == .downloading }.count
        
        if currentlyDownloading < maxConcurrentDownloads {
            guard let url = item.originalURL else { return }
            item.status = .downloading
            downloadService.startDownload(id: item.id, url: url, filename: item.displayFilename)
        } else {
            item.status = .queued
        }
    }
    
    /// Retries a failed download.
    func retryDownload(item: DownloadItem, allItems: [DownloadItem]) {
        item.lastError = nil
        resumeDownload(item: item, allItems: allItems)
    }
    
    /// Cancels an active or queued download.
    func cancelDownload(id: UUID) {
        downloadService.cancelDownload(id: id)
    }
}
