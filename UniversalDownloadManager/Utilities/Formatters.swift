import Foundation
import SwiftUI

/// Utility formatters for file sizes, transfer speeds, and time estimates.
@MainActor
enum Formatters {
    
    // MARK: - Byte Count Formatter
    
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()
    
    /// Formats a raw byte count into human-readable string (e.g. "14.2 MB", "1.24 GB").
    static func formatBytes(_ bytes: Int64) -> String {
        byteCountFormatter.string(fromByteCount: bytes)
    }
    
    /// Formats a transfer ratio (e.g. "14.2 MB / 100 MB" or "14.2 MB" if total unknown).
    static func formatTransfer(received: Int64, total: Int64?) -> String {
        let receivedStr = formatBytes(received)
        if let total, total > 0 {
            let totalStr = formatBytes(total)
            return "\(receivedStr) / \(totalStr)"
        }
        return receivedStr
    }
    
    // MARK: - Speed Formatter
    
    /// Formats transfer speed in bytes per second into "X.X MB/s" or "X.X KB/s".
    static func formatSpeed(_ bytesPerSecond: Double?) -> String {
        guard let speed = bytesPerSecond, speed > 0 else { return "-- MB/s" }
        if speed >= 1_000_000_000 {
            return String(format: "%.2f GB/s", speed / 1_000_000_000)
        } else if speed >= 1_000_000 {
            return String(format: "%.1f MB/s", speed / 1_000_000)
        } else if speed >= 1_000 {
            return String(format: "%.0f KB/s", speed / 1_000)
        } else {
            return "\(Int(speed)) B/s"
        }
    }
    
    // MARK: - Remaining Time Formatter
    
    /// Formats remaining seconds into a concise string (e.g. "45s", "3m 12s", "1h 20m").
    static func formatRemainingTime(_ seconds: TimeInterval?) -> String {
        guard let seconds = seconds, seconds > 0, !seconds.isInfinite, !seconds.isNaN else {
            return "--"
        }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSecs = totalSeconds % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(remainingSecs)s"
        } else {
            return "\(remainingSecs)s"
        }
    }
    
    // MARK: - Date Formatter
    
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private static let detailedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Formats a date relative to now (e.g. "2 hr. ago", "Yesterday").
    static func formatRelativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    /// Formats a date with full date and time.
    static func formatDetailedDate(_ date: Date) -> String {
        detailedDateFormatter.string(from: date)
    }
}

/// Helper for determining file icons and colors based on file extension.
enum FileTypeHelper {
    
    static func iconName(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "wav", "aac", "flac", "m4a": return "music.note"
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg": return "photo.fill"
        case "doc", "docx", "txt", "rtf", "md": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx", "key": return "rectangle.fill.on.rectangle.fill"
        case "dmg", "iso", "img": return "externaldrive.fill"
        case "ipa", "apk": return "app.fill"
        case "swift", "js", "html", "css", "py", "json": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }
    
    static func iconColor(for filename: String) -> Color {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return .red
        case "zip", "rar", "7z", "tar", "gz": return .indigo
        case "mp4", "mov", "avi", "mkv": return .purple
        case "mp3", "wav", "aac", "flac", "m4a": return .pink
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg": return .cyan
        case "doc", "docx", "txt", "rtf", "md": return .blue
        case "xls", "xlsx", "csv": return .green
        case "ppt", "pptx", "key": return .orange
        case "dmg", "iso", "img": return .gray
        case "ipa", "apk": return .teal
        default: return .blue
        }
    }
}
