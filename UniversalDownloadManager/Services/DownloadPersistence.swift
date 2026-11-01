import Foundation

/// Service responsible for persisting download metadata to disk so the queue survives app relaunch.
final class DownloadPersistence: Sendable {
    /// Shared singleton instance.
    static let shared = DownloadPersistence()
    
    private let metadataFileURL: URL
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        
        self.metadataFileURL = appSupport.appendingPathComponent("downloads_metadata.json")
    }
    
    // MARK: - Save & Load Metadata
    
    /// Atomically persists the list of download items to disk.
    func saveItems(_ items: [DownloadItem]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: metadataFileURL, options: .atomic)
        } catch {
            print("[DownloadPersistence] Error saving items: \(error.localizedDescription)")
        }
    }
    
    /// Loads persisted download items from disk.
    func loadItems() -> [DownloadItem] {
        guard FileManager.default.fileExists(atPath: metadataFileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: metadataFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([DownloadItem].self, from: data)
            return items
        } catch {
            print("[DownloadPersistence] Error loading items: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Clears persisted metadata.
    func clearMetadata() {
        try? FileManager.default.removeItem(at: metadataFileURL)
    }
}

