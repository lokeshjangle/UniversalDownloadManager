import SwiftUI

/// Design tokens and theme constants for the Liquid Glass-inspired UI.
/// Uses actual SwiftUI Liquid Glass APIs available in iOS 27 SDK.
enum AppTheme {
    
    // MARK: - Colors
    
    /// Primary accent color used across the app.
    static let accentColor = Color.blue
    
    /// Color for successful / completed states.
    static let successColor = Color.green
    
    /// Color for error / failed states.
    static let errorColor = Color.red
    
    /// Color for warning / interrupted states.
    static let warningColor = Color.orange
    
    /// Color for queued / pending states.
    static let pendingColor = Color.secondary
    
    /// Color for active download progress.
    static let progressColor = Color.blue
    
    // MARK: - Layout
    
    /// Standard corner radius for cards and containers.
    static let cornerRadius: CGFloat = 16
    
    /// Standard padding for content within cards.
    static let cardPadding: CGFloat = 14
    
    /// Standard spacing between list items.
    static let listSpacing: CGFloat = 10
    
    // MARK: - Helpers
    
    /// Returns the appropriate status color for a given download status.
    static func color(for status: DownloadStatus) -> Color {
        switch status {
        case .queued: return pendingColor
        case .downloading: return accentColor
        case .paused: return warningColor
        case .completed: return successColor
        case .failed: return errorColor
        case .interrupted: return warningColor
        case .cancelled: return pendingColor
        }
    }
}

