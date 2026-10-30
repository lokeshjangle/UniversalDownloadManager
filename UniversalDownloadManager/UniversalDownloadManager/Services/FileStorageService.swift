import Foundation

/// Model representing a browsable folder.
struct FolderInfo: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let fileCount: Int
    let isExternal: Bool
}

/// Service responsible for managing local file storage for completed downloads,
/// customizable and browsable save directories, collision avoidance, and cleaning temporary files.
final class FileStorageService: @unchecked Sendable {
    /// Shared singleton instance.
    static let shared = FileStorageService()
    
    private let lock = NSLock()
    private let documentsDirectory: URL
    
    /// The directory where resume data fragments are stored.
    let resumeDataDirectory: URL
    
    private let userDefaultsSubdirectoryKey = "UDM_SelectedDownloadSubdirectory"
    private let userDefaultsBookmarkKey = "UDM_ExternalFolderBookmark"
    private let userDefaultsIsExternalKey = "UDM_IsExternalFolderSelected"
    
    /// Currently chosen relative subdirectory (e.g. "Downloads", "Media", "Documents").
    var currentSubdirectory: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return UserDefaults.standard.string(forKey: userDefaultsSubdirectoryKey) ?? "Downloads"
        }
        set {
            lock.lock()
            UserDefaults.standard.set(newValue, forKey: userDefaultsSubdirectoryKey)
            UserDefaults.standard.set(false, forKey: userDefaultsIsExternalKey)
            let dir = documentsDirectory.appendingPathComponent(newValue, isDirectory: true)
            createDirectoryIfNeeded(dir)
            lock.unlock()
        }
    }
    
    /// User-visible name of the currently selected download location.
    var currentFolderDisplayName: String {
        if isExternalFolderActive, let url = resolvedExternalURL() {
            return "\(url.lastPathComponent) (Files App)"
        }
        return currentSubdirectory
    }
    
    /// Whether an external Files app folder is actively selected.
    var isExternalFolderActive: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsIsExternalKey)
    }
    
    /// The current full directory URL where completed downloads are saved.
    var downloadsDirectory: URL {
        if isExternalFolderActive, let externalURL = resolvedExternalURL() {
            _ = externalURL.startAccessingSecurityScopedResource()
            return externalURL
        }
        
        let sub = currentSubdirectory
        let dir = documentsDirectory.appendingPathComponent(sub, isDirectory: true)
        createDirectoryIfNeeded(dir)
        return dir
    }
    
    private init() {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.documentsDirectory = docs
        
        // Use Application Support/ResumeData for resume fragments
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resume = appSupport.appendingPathComponent("ResumeData", isDirectory: true)
        self.resumeDataDirectory = resume
        
        // Ensure default directories exist
        let defaultDownloads = docs.appendingPathComponent("Downloads", isDirectory: true)
        createDirectoryIfNeeded(defaultDownloads)
        createDirectoryIfNeeded(resume)
        
        // Create initial preset folders so user can browse them immediately
        let presets = ["Media", "Documents", "Archives"]
        for p in presets {
            createDirectoryIfNeeded(docs.appendingPathComponent(p, isDirectory: true))
        }
    }
    
    // MARK: - Directory Management
    
    private func createDirectoryIfNeeded(_ url: URL) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Folder Browsing & Creation
    
    /// Scans the Documents container and returns all browsable folders.
    func availableInAppFolders() -> [FolderInfo] {
        let fileManager = FileManager.default
        var result: [FolderInfo] = []
        
        // Always ensure standard folders are included
        let standard = ["Downloads", "Media", "Documents", "Archives"]
        for name in standard {
            let dir = documentsDirectory.appendingPathComponent(name, isDirectory: true)
            createDirectoryIfNeeded(dir)
        }
        
        guard let items = try? fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        for item in items {
            guard let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir else {
                continue
            }
            let name = item.lastPathComponent
            // Exclude system hidden directories
            if name.hasPrefix(".") { continue }
            
            let files = (try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
            let count = files.filter { !$0.lastPathComponent.hasPrefix(".") }.count
            
            result.append(FolderInfo(
                name: name,
                path: name,
                fileCount: count,
                isExternal: false
            ))
        }
        
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Creates a new in-app folder under Documents.
    @discardableResult
    func createNewInAppFolder(named name: String) -> Bool {
        let safeName = sanitizeFilename(name)
        guard !safeName.isEmpty else { return false }
        let dir = documentsDirectory.appendingPathComponent(safeName, isDirectory: true)
        createDirectoryIfNeeded(dir)
        return true
    }
    
    /// Selects an in-app folder by name.
    func selectInAppFolder(named name: String) {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if clean.isEmpty { clean = "Downloads" }
        self.currentSubdirectory = clean
    }
    
    // MARK: - External Files App Folder Selection
    
    /// Selects an external folder picked via UIDocumentPickerViewController (Files app).
    func selectExternalFolder(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: userDefaultsBookmarkKey)
            UserDefaults.standard.set(true, forKey: userDefaultsIsExternalKey)
        } catch {
            print("[FileStorageService] Error saving folder bookmark: \(error)")
        }
    }
    
    private func resolvedExternalURL() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: userDefaultsBookmarkKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale), !isStale else {
            return nil
        }
        return url
    }
    
    // MARK: - Moving Completed Files
    
    func saveDownloadedFile(from tempURL: URL, suggestedFilename: String) throws -> (permanentURL: URL, actualFilename: String, fileSize: Int64) {
        let fileManager = FileManager.default
        let targetDirectory = downloadsDirectory
        
        let safeName = sanitizeFilename(suggestedFilename)
        let uniqueName = uniqueFilename(for: safeName, in: targetDirectory)
        let destinationURL = targetDirectory.appendingPathComponent(uniqueName)
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        
        return (destinationURL, uniqueName, fileSize)
    }
    
    // MARK: - Filename Sanitization & Collision Handling
    
    func sanitizeFilename(_ filename: String) -> String {
        var clean = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            clean = "download"
        }
        clean = clean.replacingOccurrences(of: "/", with: "_")
        clean = clean.replacingOccurrences(of: ":", with: "_")
        clean = clean.replacingOccurrences(of: "\\", with: "_")
        clean = clean.replacingOccurrences(of: "\0", with: "")
        
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
    
    func uniqueFilename(for filename: String, in directory: URL) -> String {
        let fileManager = FileManager.default
        var candidate = filename
        var counter = 1
        
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
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
    
    func saveResumeData(_ data: Data, for id: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(id.uuidString).resume")
        try? data.write(to: fileURL, options: .atomic)
    }
    
    func readResumeData(for id: UUID) -> Data? {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(id.uuidString).resume")
        return try? Data(contentsOf: fileURL)
    }
    
    func removeResumeData(for id: UUID) {
        let fileURL = resumeDataDirectory.appendingPathComponent("\(id.uuidString).resume")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - File Management & Queries
    
    func fileURL(for filename: String) -> URL? {
        let target = downloadsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        // Fallback: check Documents root & subfolders
        guard let enumerator = FileManager.default.enumerator(at: documentsDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == filename {
                return url
            }
        }
        return nil
    }
    
    func fileExists(filename: String) -> Bool {
        fileURL(for: filename) != nil
    }
    
    func deleteFile(filename: String) {
        if let url = fileURL(for: filename) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func totalStorageUsed() -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: documentsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    func clearAllFiles() {
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        if let resumeFiles = try? fileManager.contentsOfDirectory(at: resumeDataDirectory, includingPropertiesForKeys: nil) {
            for file in resumeFiles {
                try? fileManager.removeItem(at: file)
            }
        }
        let defaultDownloads = documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
        createDirectoryIfNeeded(defaultDownloads)
    }
}
