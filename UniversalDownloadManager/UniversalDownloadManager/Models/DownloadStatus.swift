import Foundation

/// Represents the lifecycle state of a download.
enum DownloadStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case interrupted
    case cancelled
    
    /// A user-friendly display name for this status.
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        case .cancelled: return "Cancelled"
        }
    }
    
    /// SF Symbol name appropriate for this status.
    var iconName: String {
        switch self {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        case .interrupted: return "bolt.slash"
        case .cancelled: return "xmark.circle"
        }
    }
    
    /// Whether this status represents a terminal state.
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .downloading, .paused, .interrupted:
            return false
        }
    }
    
    /// Whether this status represents an active transfer.
    var isActive: Bool {
        self == .downloading
    }
}

