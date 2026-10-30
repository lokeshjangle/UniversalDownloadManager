import Foundation
import Combine

/// Persistent model representing a single download request and its metadata.
/// Conforms to ObservableObject so SwiftUI views update immediately on any state change.
final class DownloadItem: ObservableObject, Identifiable, Codable, Equatable, Hashable {
    /// Stable unique identifier for this download.
    let id: UUID
    
    /// The original URL string from which the file is being downloaded.
    let originalURLString: String
    
    /// The user-visible filename for display purposes.
    @Published var displayFilename: String
    
    /// The local filename on disk after download completes (relative to app storage).
    @Published var localFilename: String?
    
    /// Current download status raw value.
    @Published var statusRawValue: String
    
    /// URLSession task identifier, used for reconciliation on relaunch.
    @Published var taskIdentifier: Int?
    
    /// Number of bytes received so far.
    @Published var bytesReceived: Int64
    
    /// Expected total bytes, if known from the server. Nil means unknown.
    @Published var expectedTotalBytes: Int64?
    
    /// Current download transfer speed in bytes per second. Nil if not downloading.
    @Published var currentSpeed: Double?
    
    /// Estimated time remaining in seconds. Nil if unknown or not downloading.
    @Published var estimatedTimeRemaining: TimeInterval?
    
    /// Timestamp when this download was created / queued.
    let createdAt: Date
    
    /// Timestamp when the actual transfer started.
    @Published var startedAt: Date?
    
    /// Timestamp when the download completed or failed.
    @Published var completedAt: Date?
    
    /// Human-readable description of the last error, if any.
    @Published var lastError: String?
    
    /// Whether resume data exists for this download.
    @Published var hasResumeData: Bool
    
    // MARK: - Computed Properties
    
    /// The current status as a `DownloadStatus` enum value.
    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRawValue) ?? .queued }
        set { statusRawValue = newValue.rawValue }
    }
    
    /// The original URL parsed from the stored string.
    var originalURL: URL? {
        URL(string: originalURLString)
    }
    
    /// Download progress from 0.0 to 1.0. Returns nil if total is unknown.
    var progress: Double? {
        guard let total = expectedTotalBytes, total > 0 else { return nil }
        return min(max(Double(bytesReceived) / Double(total), 0.0), 1.0)
    }
    
    /// Progress formatted as percentage (e.g. "65%").
    var progressPercentageString: String {
        if let progress {
            return "\(Int(progress * 100))%"
        }
        return "--"
    }
    
    // MARK: - CodingKeys for Codable with @Published
    
    enum CodingKeys: String, CodingKey {
        case id
        case originalURLString
        case displayFilename
        case localFilename
        case statusRawValue
        case taskIdentifier
        case bytesReceived
        case expectedTotalBytes
        case currentSpeed
        case estimatedTimeRemaining
        case createdAt
        case startedAt
        case completedAt
        case lastError
        case hasResumeData
    }
    
    // MARK: - Encodable & Decodable
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalURLString, forKey: .originalURLString)
        try container.encode(displayFilename, forKey: .displayFilename)
        try container.encodeIfPresent(localFilename, forKey: .localFilename)
        try container.encode(statusRawValue, forKey: .statusRawValue)
        try container.encodeIfPresent(taskIdentifier, forKey: .taskIdentifier)
        try container.encode(bytesReceived, forKey: .bytesReceived)
        try container.encodeIfPresent(expectedTotalBytes, forKey: .expectedTotalBytes)
        try container.encodeIfPresent(currentSpeed, forKey: .currentSpeed)
        try container.encodeIfPresent(estimatedTimeRemaining, forKey: .estimatedTimeRemaining)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(hasResumeData, forKey: .hasResumeData)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.originalURLString = try container.decode(String.self, forKey: .originalURLString)
        self.displayFilename = try container.decode(String.self, forKey: .displayFilename)
        self.localFilename = try container.decodeIfPresent(String.self, forKey: .localFilename)
        self.statusRawValue = try container.decode(String.self, forKey: .statusRawValue)
        self.taskIdentifier = try container.decodeIfPresent(Int.self, forKey: .taskIdentifier)
        self.bytesReceived = try container.decode(Int64.self, forKey: .bytesReceived)
        self.expectedTotalBytes = try container.decodeIfPresent(Int64.self, forKey: .expectedTotalBytes)
        self.currentSpeed = try container.decodeIfPresent(Double.self, forKey: .currentSpeed)
        self.estimatedTimeRemaining = try container.decodeIfPresent(TimeInterval.self, forKey: .estimatedTimeRemaining)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        self.hasResumeData = try container.decode(Bool.self, forKey: .hasResumeData)
    }
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        url: URL,
        displayFilename: String,
        status: DownloadStatus = .queued,
        bytesReceived: Int64 = 0,
        expectedTotalBytes: Int64? = nil,
        currentSpeed: Double? = nil,
        estimatedTimeRemaining: TimeInterval? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastError: String? = nil,
        hasResumeData: Bool = false,
        localFilename: String? = nil
    ) {
        self.id = id
        self.originalURLString = url.absoluteString
        self.displayFilename = displayFilename
        self.localFilename = localFilename
        self.statusRawValue = status.rawValue
        self.taskIdentifier = nil
        self.bytesReceived = bytesReceived
        self.expectedTotalBytes = expectedTotalBytes
        self.currentSpeed = currentSpeed
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastError = lastError
        self.hasResumeData = hasResumeData
    }
    
    // MARK: - Equatable & Hashable
    
    static func == (lhs: DownloadItem, rhs: DownloadItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
