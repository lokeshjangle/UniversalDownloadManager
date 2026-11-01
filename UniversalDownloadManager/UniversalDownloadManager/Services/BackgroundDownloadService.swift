import Foundation
import Combine
import UIKit
import UserNotifications

/// Protocol for listening to real-time download lifecycle events.
@MainActor
protocol DownloadServiceDelegate: AnyObject {
    func downloadDidUpdateProgress(id: UUID, bytesReceived: Int64, totalBytes: Int64?, speed: Double?, eta: TimeInterval?)
    func downloadDidComplete(id: UUID, localFilename: String, fileSize: Int64)
    func downloadDidFail(id: UUID, error: String, canResume: Bool)
    func downloadDidPause(id: UUID, hasResumeData: Bool)
    func downloadDidReconcile(runningIDs: Set<UUID>)
}

/// The state of a task during relaunch reconciliation.
enum TaskReconciliationResult {
    case stillRunning(bytesWritten: Int64, totalBytes: Int64)
    case completed
    case orphanedOrTerminated
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
    
    /// Timestamp of the last progress delegate dispatch per download (throttled for maximum throughput).
    private var lastProgressReportTimes: [UUID: Date] = [:]
    
    /// Background task identifier to maintain execution grace period during app minimization.
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    private override init() {
        super.init()
        setupSession()
    }
    
    // MARK: - Session Setup
    
    private func setupSession() {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 300 // 5 minutes to prevent premature timeouts during device sleep
        configuration.timeoutIntervalForResource = 60 * 60 * 48 // 48 hours for multi-GB transfers
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.lokeshjangale.UniversalDownloadManager.sessionQueue"
        delegateQueue.maxConcurrentOperationCount = 8
        delegateQueue.qualityOfService = .userInitiated
        
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }
    
    // MARK: - Background Grace Period Management
    
    /// Requests a temporary background execution extension from iOS so active transfers
    /// transition smoothly to the system daemon without abrupt socket termination.
    func beginBackgroundGracePeriodIfNeeded() {
        Task { @MainActor [weak self] in
            guard let self = self, self.backgroundTaskIdentifier == .invalid else { return }
            self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "UDM_ActiveDownloadGracePeriod") { [weak self] in
                self?.endBackgroundGracePeriod()
            }
        }
    }
    
    func endBackgroundGracePeriod() {
        Task { @MainActor in
            guard self.backgroundTaskIdentifier != .invalid else { return }
            let currentID = self.backgroundTaskIdentifier
            self.backgroundTaskIdentifier = .invalid
            UIApplication.shared.endBackgroundTask(currentID)
        }
    }
    
    // MARK: - Task Control
    
    /// Starts or resumes a download task for a given download item.
    func startDownload(id: UUID, url: URL, filename: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if resume data exists for this item
        if let resumeData = FileStorageService.shared.readResumeData(for: id) {
            let task = session.downloadTask(withResumeData: resumeData)
            task.taskDescription = id.uuidString // Persisted by nsurlsessiond across restarts
            task.priority = URLSessionTask.highPriority // 1.0 (Maximum system priority for nsurlsessiond)
            register(task: task, for: id, filename: filename)
            task.resume()
            beginBackgroundGracePeriodIfNeeded()
            return
        }
        
        // Otherwise start a fresh high-speed download task
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Eliminate URLCache disk bottlenecks
        request.networkServiceType = .responsiveData // High network priority in iOS stack
        request.setValue("UniversalDownloadManager/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        
        let task = session.downloadTask(with: request)
        task.taskDescription = id.uuidString // Persisted by nsurlsessiond across restarts
        task.priority = URLSessionTask.highPriority // 1.0 (Maximum system priority for nsurlsessiond)
        register(task: task, for: id, filename: filename)
        task.resume()
        beginBackgroundGracePeriodIfNeeded()
    }
    
    private func register(task: URLSessionDownloadTask, for id: UUID, filename: String) {
        activeTasks[id] = task
        taskIdentifierToID[task.taskIdentifier] = id
        taskFilenames[id] = filename
        speedTrackers[id] = (lastBytes: 0, lastTime: Date(), smoothedSpeed: 0)
        lastProgressReportTimes[id] = .distantPast
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
        lastProgressReportTimes.removeValue(forKey: id)
        let noActive = activeTasks.isEmpty
        lock.unlock()
        
        if noActive {
            endBackgroundGracePeriod()
        }
        
        FileStorageService.shared.removeResumeData(for: id)
        task?.cancel()
    }
    
    // MARK: - Relaunch Task Reconciliation (Phase 4)
    
    /// Reconnects with running background tasks on app relaunch, restoring state for any in-flight transfers.
    func reconcileRunningTasks(knownFilenames: [UUID: String]) async -> Set<UUID> {
        let tasks = await session.allTasks
        
        return lock.withLock {
            var runningIDs = Set<UUID>()
            
            for task in tasks {
                guard let downloadTask = task as? URLSessionDownloadTask else { continue }
                
                // Reconnect via persisted taskDescription
                if let desc = downloadTask.taskDescription, let id = UUID(uuidString: desc) {
                    if let filename = knownFilenames[id] {
                        activeTasks[id] = downloadTask
                        taskIdentifierToID[downloadTask.taskIdentifier] = id
                        runningIDs.insert(id)
                        
                        taskFilenames[id] = filename
                        if speedTrackers[id] == nil {
                            speedTrackers[id] = (lastBytes: 0, lastTime: Date(), smoothedSpeed: 0)
                        }
                        if lastProgressReportTimes[id] == nil {
                            lastProgressReportTimes[id] = .distantPast
                        }
                        
                        // If task was paused or suspended by the system daemon, resume it immediately
                        if downloadTask.state == .suspended {
                            downloadTask.resume()
                        }
                    } else {
                        // Stale task without corresponding download record in store: cancel safely
                        downloadTask.cancel()
                    }
                } else {
                    // Task without valid taskDescription: cancel safely
                    downloadTask.cancel()
                }
            }
            
            // Also preserve any in-memory active tasks that are running
            for (id, task) in activeTasks {
                if task.state == .running || task.state == .suspended {
                    runningIDs.insert(id)
                }
            }
            
            return runningIDs
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
        // Try resolving by taskIdentifier or taskDescription
        var resolvedID = taskIdentifierToID[downloadTask.taskIdentifier]
        if resolvedID == nil, let desc = downloadTask.taskDescription, let id = UUID(uuidString: desc) {
            taskIdentifierToID[downloadTask.taskIdentifier] = id
            activeTasks[id] = downloadTask
            resolvedID = id
        }
        
        guard let id = resolvedID else {
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
        
        // High-Performance Progress Throttling:
        // Only dispatch to MainActor at most 4 times per second (>= 0.25s) or upon 100% completion.
        let lastReport = lastProgressReportTimes[id] ?? .distantPast
        let timeSinceLastReport = now.timeIntervalSince(lastReport)
        let isComplete = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        
        guard timeSinceLastReport >= 0.25 || isComplete else {
            lock.unlock()
            return
        }
        lastProgressReportTimes[id] = now
        lock.unlock()
        
        let expectedTotal: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let finalSpeed = speed
        let finalEta = eta
        
        Task { @MainActor in
            self.delegate?.downloadDidUpdateProgress(
                id: id,
                bytesReceived: totalBytesWritten,
                totalBytes: expectedTotal,
                speed: finalSpeed,
                eta: finalEta
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
        var resolvedID = taskIdentifierToID[downloadTask.taskIdentifier]
        if resolvedID == nil, let desc = downloadTask.taskDescription, let id = UUID(uuidString: desc) {
            taskIdentifierToID[downloadTask.taskIdentifier] = id
            activeTasks[id] = downloadTask
            resolvedID = id
        }
        
        guard let id = resolvedID else {
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
        var resolvedID = taskIdentifierToID[downloadTask.taskIdentifier]
        if resolvedID == nil, let desc = downloadTask.taskDescription, let id = UUID(uuidString: desc) {
            resolvedID = id
        }
        
        guard let id = resolvedID else {
            lock.unlock()
            return
        }
        
        let suggestedName = taskFilenames[id] ?? "download_\(id.uuidString.prefix(6))"
        
        activeTasks.removeValue(forKey: id)
        taskIdentifierToID.removeValue(forKey: downloadTask.taskIdentifier)
        taskFilenames.removeValue(forKey: id)
        speedTrackers.removeValue(forKey: id)
        lastProgressReportTimes.removeValue(forKey: id)
        let noActive = activeTasks.isEmpty
        lock.unlock()
        
        if noActive {
            endBackgroundGracePeriod()
        }
        
        FileStorageService.shared.removeResumeData(for: id)
        
        var finalFilename = suggestedName
        if let response = downloadTask.response as? HTTPURLResponse,
           let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition") {
            if let parsedName = parseFilenameFromContentDisposition(contentDisposition) {
                finalFilename = parsedName
            }
        }
        
        do {
            let result = try FileStorageService.shared.saveDownloadedFile(from: location, suggestedFilename: finalFilename)
            postCompletionNotification(filename: result.actualFilename, fileSize: result.fileSize)
            Task { @MainActor in
                self.delegate?.downloadDidComplete(id: id, localFilename: result.actualFilename, fileSize: result.fileSize)
            }
        } catch {
            Task { @MainActor in
                self.delegate?.downloadDidFail(id: id, error: "Failed to save file: \(error.localizedDescription)", canResume: false)
            }
        }
    }
    
    private func postCompletionNotification(filename: String, fileSize: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        content.body = "\(filename) (\(sizeStr)) has been saved."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    private func parseFilenameFromContentDisposition(_ header: String) -> String? {
        let parts = header.components(separatedBy: ";")
        var standardName: String?
        var extendedName: String?
        
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            
            if lower.hasPrefix("filename*=") {
                // RFC 5987 / RFC 6266 format: filename*=UTF-8''filename.ext or charset'lang'encoded-value
                let raw = String(trimmed.dropFirst("filename*=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\" '"))
                let subParts = raw.components(separatedBy: "''")
                if subParts.count >= 2 {
                    let encodedValue = subParts.dropFirst().joined(separator: "''")
                    extendedName = encodedValue.removingPercentEncoding ?? encodedValue
                } else {
                    extendedName = raw.removingPercentEncoding ?? raw
                }
            } else if lower.hasPrefix("filename=") {
                let name = String(trimmed.dropFirst("filename=".count))
                standardName = name.trimmingCharacters(in: CharacterSet(charactersIn: "\" '"))
            }
        }
        
        return extendedName ?? standardName
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundDownloadService: URLSessionTaskDelegate {
    
    /// Called when the task completes with an error or cancellation.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        
        let nsError = error as NSError
        
        lock.lock()
        var resolvedID = taskIdentifierToID[task.taskIdentifier]
        if resolvedID == nil, let desc = task.taskDescription, let id = UUID(uuidString: desc) {
            resolvedID = id
        }
        
        guard let id = resolvedID else {
            lock.unlock()
            return
        }
        
        activeTasks.removeValue(forKey: id)
        taskIdentifierToID.removeValue(forKey: task.taskIdentifier)
        taskFilenames.removeValue(forKey: id)
        speedTrackers.removeValue(forKey: id)
        lastProgressReportTimes.removeValue(forKey: id)
        let noActive = activeTasks.isEmpty
        lock.unlock()
        
        if noActive {
            endBackgroundGracePeriod()
        }
        
        // Cancellation handling (e.g. paused by user)
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !resumeData.isEmpty {
                FileStorageService.shared.saveResumeData(resumeData, for: id)
                Task { @MainActor in
                    self.delegate?.downloadDidPause(id: id, hasResumeData: true)
                }
            }
            return
        }
        
        // Network drop with resume data
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
