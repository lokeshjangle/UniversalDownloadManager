import Foundation

/// Service responsible for managing local file storage for completed downloads,
/// avoiding filename collisions, and cleaning temporary files.
final class FileStorageService: Sendable {
    /// Shared singleton instance.
    static let shared = FileStorageService()
    
    /// The directory where completed downloads are permanently stored.
    let downloadsDirectory: URL
    
    /// The directory where resume data fragments are stored.
    let resumeDataDirectory: URL
    
    private init() {
        let fileManager = FileManager.default
        
        // Use Documents/Downloads for persistent user-accessible files
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloads = docs.appendingPathComponent("Downloads", isDirectory: true)
        self.downloadsDirectory = downloads
        
        // Use Application Support/ResumeData for resume fragments
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resume = appSupport.appendingPathComponent("ResumeData", isDirectory: true)
        self.resumeDataDirectory = resume
        
        createDirectoryIfNeeded(downloads)
        createDirectoryIfNeeded(resume)
    }
    
    // MARK: - Directory Management
    
    private func createDirectoryIfNeeded(_ url: URL) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Moving Completed Files
    
    /// Moves a downloaded file from URLSession's temporary location into persistent app storage.
    /// Resolves filename collisions automatically (e.g. `file (1).zip`).
    /// - Parameters:
    ///   - tempURL: The temporary file URL provided by URLSessionDownloadDelegate.
    ///   - suggestedFilename: The suggested filename from URL or response headers.
    /// - Returns: A tuple with the final persistent file URL, actual filename saved, and file size in bytes.
    func saveDownloadedFile(from tempURL: URL, suggestedFilename: String) throws -> (permanentURL: URL, actualFilename: String, fileSize: Int64) {
        let fileManager = FileManager.default
        let safeName = sanitizeFilename(suggestedFilename)
        let uniqueName = uniqueFilename(for: safeName)
        let destinationURL = downloadsDirectory.appendingPathComponent(uniqueName)
        
        // If a file already exists at the target, remove it (uniqueFilename ensures uniqueness, but extra safety check)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        // Move temporary file to persistent storage
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        // Get final file size
        let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        
        return (destinationURL, uniqueName, fileSize)
    }
    
    // MARK: - Filename Sanitization & Collision Handling
    
    /// Cleans filename of prohibited characters, path separators, and null bytes.
    func sanitizeFilename(_ filename: String) -> String {
        var clean = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            clean = "download"
        }
        // Prohibit directory traversal characters and slashes
        clean = clean.replacingOccurrences(of: "/", with: "_")
        clean = clean.replacingOccurrences(of: ":", with: "_")
        clean = clean.replacingOccurrences(of: "\\", with: "_")
        clean = clean.replacingOccurrences(of: "\0", with: "")
        
        // Restrict excessive filename length (max 180 chars preserving extension)
        if clean.count > 180 {
            let ext = (clean as NSString).pathExtension
            let nameWithoutExt = (clean as NSString).deletingPathExtension
            let truncated = String(nameWithoutExt.prefix(170))
            if !ext.isEmpty {
                clean = "\(truncated).\(ext)"
            } else {
                clean = truncated
            }
        }
        return clean
    }
    
    /// Generates a unique filename if a file with the same name already exists in downloads directory.
    /// Example: `report.pdf` -> `report (1).pdf` -> `report (2).pdf`.
    func uniqueFilename(for filename: String) -> String {
        let fileManager = FileManager.default
        var candidate = filename
        var counter = 1
        
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        
        while fileManager.fileExists(atPath: downloadsDirectory.appendingPathComponent(candidate).path) {
            if ext.isEmpty {
                candidate = "\(base) (\(counter))"
            } else {
                candidate = "\(base) (\(counter)).\(ext)"
            }
            counter += 1
        }
        return candidate
    }
    
    // MARK: - Resume Data Storage
    
    /// Saves URLSession resume data for a given download ID.
    func saveResumeData(_ data: Data, for id: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(id.uuidString).resume")
        try? data.write(to: fileURL, options: .atomic)
    }
    
    /// Reads stored resume data for a given download ID, if available.
    func readResumeData(for id: UUID) -> Data? {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(id.uuidString).resume")
        return try? Data(contentsOf: fileURL)
    }
    
    /// Removes stored resume data for a given download ID.
    func removeResumeData(for id: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(id.uuidString).resume")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - File Management & Queries
    
    /// Returns the full file URL for a given local filename if it exists in Downloads.
    func fileURL(for filename: String) -> URL? {
        let url = downloadsDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Checks whether a local file exists in the Downloads folder.
    func fileExists(filename: String) -> Bool {
        let url = downloadsDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Deletes a file from the Downloads folder.
    func deleteFile(filename: String) {
        let url = downloadsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Calculates total storage used by all completed downloads in bytes.
    func totalStorageUsed() -> Int64 {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var total: Int64 = 0
        for file in files {
            if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    /// Clears all files in the Downloads and ResumeData directories.
    func clearAllFiles() {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        if let resumeFiles = try? fileManager.contentsOfDirectory(at: resumeDataDirectory, includingPropertiesForKeys: nil) {
            for file in resumeFiles {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
