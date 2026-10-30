import Foundation
import Combine

/// Protocol for listening to real-time download lifecycle events.
@MainActor
protocol DownloadServiceDelegate: AnyObject {
    func downloadDidUpdateProgress(id: UUID, bytesReceived: Int64, totalBytes: Int64?, speed: Double?, eta: TimeInterval?)
    func downloadDidComplete(id: UUID, localFilename: String, fileSize: Int64)
    func downloadDidFail(id: UUID, error: String, canResume: Bool)
    func downloadDidPause(id: UUID, hasResumeData: Bool)
}

/// The core Foundation URLSession download engine supporting background transfers,
/// streaming to disk, resumable transfers, and concurrency management.
final class BackgroundDownloadService: NSObject, @unchecked Sendable {
    /// Shared singleton instance.
    static let shared = BackgroundDownloadService()
    
    /// Stable background session identifier.
    static let backgroundSessionIdentifier = "com.lokeshjangale.UniversalDownloadManager.background"
    
    /// The active URLSession instance.
    private var session: URLSession!
    
    /// Delegate to notify main-actor UI of progress and state updates.
    weak var delegate: DownloadServiceDelegate?
    
    /// Stored background completion handler provided by AppDelegate / App lifecycle.
    var backgroundCompletionHandler: (() -> Void)?
    
    /// Lock for thread-safe access to internal state dictionaries.
    private let lock = NSLock()
    
    /// Maps download UUID -> active URLSessionDownloadTask.
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    
    /// Maps URLSession taskIdentifier -> download UUID.
    private var taskIdentifierToID: [Int: UUID] = [:]
    
    /// Maps download UUID -> suggested display filename.
    private var taskFilenames: [UUID: String] = [:]
    
    /// Speed calculation trackers: download UUID -> (lastBytes: Int64, lastTime: Date, smoothedSpeed: Double).
    private var speedTrackers: [UUID: (lastBytes: Int64, lastTime: Date, smoothedSpeed: Double)] = [:]
    
    private override init() {
        super.init()
        setupSession()
    }
    
    // MARK: - Session Setup
    
    private func setupSession() {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24 // 24 hours for large downloads
        configuration.httpMaximumConnectionsPerHost = 4
        
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.lokeshjangale.UniversalDownloadManager.sessionQueue"
        delegateQueue.maxConcurrentOperationCount = 2
        
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }
    
    // MARK: - Task Control
    
    /// Starts or resumes a download task for a given download item.
    func startDownload(id: UUID, url: URL, filename: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if resume data exists for this item
        if let resumeData = FileStorageService.shared.readResumeData(for: id) {
            let task = session.downloadTask(withResumeData: resumeData)
            register(task: task, for: id, filename: filename)
            task.resume()
            return
        }
        
        // Otherwise start a fresh download task
        var request = URLRequest(url: url)
        request.setValue("UniversalDownloadManager/1.0", forHTTPHeaderField: "User-Agent")
        
        let task = session.downloadTask(with: request)
        register(task: task, for: id, filename: filename)
        task.resume()
    }
    
    private func register(task: URLSessionDownloadTask, for id: UUID, filename: String) {
        activeTasks[id] = task
        taskIdentifierToID[task.taskIdentifier] = id
        taskFilenames[id] = filename
        speedTrackers[id] = (lastBytes: 0, lastTime: Date(), smoothedSpeed: 0)
    }
    
    /// Pauses an active download, attempting to produce and persist resume data.
    func pauseDownload(id: UUID) {
        lock.lock()
        guard let task = activeTasks[id] else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        task.cancel { [weak self] resumeData in
            guard let self = self else { return }
            
            self.lock.lock()
            self.activeTasks.removeValue(forKey: id)
            self.taskIdentifierToID.removeValue(forKey: task.taskIdentifier)
            self.speedTrackers.removeValue(forKey: id)
            self.lock.unlock()
            
            let hasResumeData: Bool
            if let resumeData = resumeData, !resumeData.isEmpty {
                FileStorageService.shared.saveResumeData(resumeData, for: id)
                hasResumeData = true
            } else {
                hasResumeData = false
            }
            
            Task { @MainActor in
                self.delegate?.downloadDidPause(id: id, hasResumeData: hasResumeData)
            }
        }
    }
    
    /// Cancels an active download, discarding any resume data.
    func cancelDownload(id: UUID) {
        lock.lock()
        let task = activeTasks.removeValue(forKey: id)
        if let task = task {
            taskIdentifierToID.removeValue(forKey: task.taskIdentifier)
        }
        speedTrackers.removeValue(forKey: id)
        lock.unlock()
        
        FileStorageService.shared.removeResumeData(for: id)
        task?.cancel()
    }
    
    /// Reconnects with running background tasks on app relaunch.
    func reconcileTasks(completion: @escaping ([Int: URLSessionDownloadTask]) -> Void) {
        session.getAllTasks { tasks in
            var mapped: [Int: URLSessionDownloadTask] = [:]
            for task in tasks {
                if let downloadTask = task as? URLSessionDownloadTask {
                    mapped[downloadTask.taskIdentifier] = downloadTask
                }
            }
            completion(mapped)
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundDownloadService: URLSessionDownloadDelegate {
    
    /// Called periodically as chunks of data are written to temporary disk storage.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        guard let id = taskIdentifierToID[downloadTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        
        // Calculate rolling speed and ETA
        let now = Date()
        var speed: Double? = nil
        var eta: TimeInterval? = nil
        
        if let tracker = speedTrackers[id] {
            let elapsed = now.timeIntervalSince(tracker.lastTime)
            if elapsed >= 0.5 {
                let deltaBytes = totalBytesWritten - tracker.lastBytes
                let currentSpeed = Double(deltaBytes) / elapsed
                // Smooth speed using 70/30 weight
                let smoothed = tracker.smoothedSpeed > 0 ? (tracker.smoothedSpeed * 0.7 + currentSpeed * 0.3) : currentSpeed
                speedTrackers[id] = (lastBytes: totalBytesWritten, lastTime: now, smoothedSpeed: smoothed)
                speed = smoothed
                
                if totalBytesExpectedToWrite > 0 && smoothed > 0 {
                    let remainingBytes = Double(totalBytesExpectedToWrite - totalBytesWritten)
                    eta = max(remainingBytes / smoothed, 0)
                }
            } else {
                speed = tracker.smoothedSpeed > 0 ? tracker.smoothedSpeed : nil
                if let s = speed, s > 0 && totalBytesExpectedToWrite > 0 {
                    let remainingBytes = Double(totalBytesExpectedToWrite - totalBytesWritten)
                    eta = max(remainingBytes / s, 0)
                }
            }
        } else {
            speedTrackers[id] = (lastBytes: totalBytesWritten, lastTime: now, smoothedSpeed: 0)
        }
        lock.unlock()
        
        let expectedTotal: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        
        Task { @MainActor in
            self.delegate?.downloadDidUpdateProgress(
                id: id,
                bytesReceived: totalBytesWritten,
                totalBytes: expectedTotal,
                speed: speed,
                eta: eta
            )
        }
    }
    
    /// Called when resume data offset is restored.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        lock.lock()
        guard let id = taskIdentifierToID[downloadTask.taskIdentifier] else {
            lock.unlock()
            return
        }
        speedTrackers[id] = (lastBytes: fileOffset, lastTime: Date(), smoothedSpeed: 0)
        lock.unlock()
        
        Task { @MainActor in
            self.delegate?.downloadDidUpdateProgress(
                id: id,
                bytesReceived: fileOffset,
                totalBytes: expectedTotalBytes > 0 ? expectedTotalBytes : nil,
                speed: nil,
                eta: nil
            )
        }
    }
    
    /// Called when the download completes and the file has been saved to a temporary location.
    /// MUST move the file before returning from this method!
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        guard let id = taskIdentifierToID[downloadTask.taskIdentifier],
              let suggestedName = taskFilenames[id] else {
            lock.unlock()
            return
        }
        
        activeTasks.removeValue(forKey: id)
        taskIdentifierToID.removeValue(forKey: downloadTask.taskIdentifier)
        taskFilenames.removeValue(forKey: id)
        speedTrackers.removeValue(forKey: id)
        lock.unlock()
        
        // Remove any stale resume data
        FileStorageService.shared.removeResumeData(for: id)
        
        // Check for server suggested filename in Content-Disposition if available
        var finalFilename = suggestedName
        if let response = downloadTask.response as? HTTPURLResponse,
           let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition") {
            if let parsedName = parseFilenameFromContentDisposition(contentDisposition) {
                finalFilename = parsedName
            }
        }
        
        do {
            let result = try FileStorageService.shared.saveDownloadedFile(from: location, suggestedFilename: finalFilename)
            Task { @MainActor in
                self.delegate?.downloadDidComplete(id: id, localFilename: result.actualFilename, fileSize: result.fileSize)
            }
        } catch {
            Task { @MainActor in
                self.delegate?.downloadDidFail(id: id, error: "Failed to save file: \(error.localizedDescription)", canResume: false)
            }
        }
    }
    
    private func parseFilenameFromContentDisposition(_ header: String) -> String? {
        // e.g. 'attachment; filename="data.csv"' or "filename=data.csv"
        let parts = header.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("filename=") {
                let name = String(trimmed.dropFirst("filename=".count))
                return name.trimmingCharacters(in: CharacterSet(charactersIn: "\" '"))
            }
        }
        return nil
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundDownloadService: URLSessionTaskDelegate {
    
    /// Called when the task completes with an error or cancellation.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        
        let nsError = error as NSError
        
        lock.lock()
        guard let id = taskIdentifierToID[task.taskIdentifier] else {
            lock.unlock()
            return
        }
        
        activeTasks.removeValue(forKey: id)
        taskIdentifierToID.removeValue(forKey: task.taskIdentifier)
        taskFilenames.removeValue(forKey: id)
        speedTrackers.removeValue(forKey: id)
        lock.unlock()
        
        // If cancellation error (e.g. paused by user), handle gracefully
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            // Check if resume data was attached in userInfo
            if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !resumeData.isEmpty {
                FileStorageService.shared.saveResumeData(resumeData, for: id)
                Task { @MainActor in
                    self.delegate?.downloadDidPause(id: id, hasResumeData: true)
                }
            }
            return
        }
        
        // Extract resume data if network failure occurred during download
        var canResume = false
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !resumeData.isEmpty {
            FileStorageService.shared.saveResumeData(resumeData, for: id)
            canResume = true
        }
        
        let errorMessage: String
        switch nsError.code {
        case NSURLErrorTimedOut:
            errorMessage = "Connection timed out."
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            errorMessage = "Cannot connect to server."
        case NSURLErrorNotConnectedToInternet:
            errorMessage = "No internet connection."
        case NSURLErrorSecureConnectionFailed:
            errorMessage = "SSL/TLS secure connection failed."
        default:
            errorMessage = nsError.localizedDescription
        }
        
        Task { @MainActor in
            self.delegate?.downloadDidFail(id: id, error: errorMessage, canResume: canResume)
        }
    }
}

// MARK: - URLSessionDelegate (Background Completion)

extension BackgroundDownloadService: URLSessionDelegate {
    
    /// Called when all events for a background session have been delivered.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            if let handler = self.backgroundCompletionHandler {
                self.backgroundCompletionHandler = nil
                handler()
            }
        }
    }
}

