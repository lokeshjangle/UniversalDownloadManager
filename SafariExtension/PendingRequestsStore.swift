import Foundation

/// Represents a download request initiated from an external source (such as Chrome Share Sheet or Safari).
public struct PendingDownloadRequest: Codable, Identifiable, Sendable {
    public let id: UUID
    public let urlString: String
    public let customFilename: String?
    public let sourceApp: String?
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        urlString: String,
        customFilename: String? = nil,
        sourceApp: String? = "Chrome",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.urlString = urlString
        self.customFilename = customFilename
        self.sourceApp = sourceApp
        self.timestamp = timestamp
    }
}

/// Thread-safe storage for queuing download requests handed off from the Share Extension or external schemes.
public final class PendingRequestsStore: @unchecked Sendable {
    public static let shared = PendingRequestsStore()
    
    public static let appGroupIdentifier = "group.com.lokeshjangale.UniversalDownloadManager"
    private let fileName = "pending_downloads.json"
    private let lock = NSLock()
    
    private init() {}
    
    /// Resolves the storage directory for handoff:
    /// 1. App Group container if configured and accessible.
    /// 2. Universal shared fallback directory for simulator / development environments.
    private var storageDirectoryURL: URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            return containerURL
        }
        
        // Fallback for development/simulator environments:
        // /tmp/UDM_Shared_Handoff is accessible by both the host app and any app extension in simulator.
        let fallbackDir = URL(fileURLWithPath: "/tmp/UDM_Shared_Handoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        return fallbackDir
    }
    
    private var fileURL: URL {
        storageDirectoryURL.appendingPathComponent(fileName)
    }
    
    /// Saves a new pending download request to the shared queue.
    public func savePendingRequest(_ request: PendingDownloadRequest) {
        lock.lock()
        defer { lock.unlock() }
        
        var existing = readAllUnlocked()
        // Deduplicate requests with the same URL within recent window (10 seconds)
        if !existing.contains(where: { $0.urlString == request.urlString && abs($0.timestamp.timeIntervalSince(request.timestamp)) < 10 }) {
            existing.append(request)
        }
        writeAllUnlocked(existing)
    }
    
    /// Reads and atomically clears all pending requests so they can be imported into the main queue.
    public func fetchAndClearPendingRequests() -> [PendingDownloadRequest] {
        lock.lock()
        defer { lock.unlock() }
        
        let pending = readAllUnlocked()
        if !pending.isEmpty {
            writeAllUnlocked([])
        }
        return pending
    }
    
    /// Reads all pending requests without clearing.
    public func loadPendingRequests() -> [PendingDownloadRequest] {
        lock.lock()
        defer { lock.unlock() }
        return readAllUnlocked()
    }
    
    private func readAllUnlocked() -> [PendingDownloadRequest] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([PendingDownloadRequest].self, from: data)
            return items
        } catch {
            return []
        }
    }
    
    private func writeAllUnlocked(_ requests: [PendingDownloadRequest]) {
        let url = fileURL
        do {
            let data = try JSONEncoder().encode(requests)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Write failed; file write logged if needed
        }
    }
}
