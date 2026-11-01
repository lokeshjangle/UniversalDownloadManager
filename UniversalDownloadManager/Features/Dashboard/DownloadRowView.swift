import SwiftUI

/// A comprehensive Liquid Glass card displaying a single download's status and interactive controls,
/// strictly bounded within screen bezels with clean single-layer buttons and immediate reactivity.
struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem
    var onPause: (() -> Void)? = nil
    var onResume: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        GlassCard(cornerRadius: AppTheme.cornerRadius, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // Top Row: Icon + Filename/Subtitle + Status Badge
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: FileTypeHelper.iconName(for: item.displayFilename))
                        .font(.body)
                        .foregroundStyle(FileTypeHelper.iconColor(for: item.displayFilename))
                        .frame(width: 32, height: 32)
                        .background(FileTypeHelper.iconColor(for: item.displayFilename).opacity(0.12), in: .rect(cornerRadius: 8))
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayFilename)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text(subtitleText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    GlassBadge(
                        item.status.displayName,
                        iconName: item.status.iconName,
                        color: AppTheme.color(for: item.status)
                    )
                    .fixedSize()
                }
                
                // Progress Bar (only when active/paused)
                if showProgressBar {
                    VStack(alignment: .leading, spacing: 3) {
                        if let progress = item.progress {
                            ProgressView(value: progress)
                                .tint(AppTheme.color(for: item.status))
                                .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: progress)
                        } else {
                            ProgressView()
                                .tint(AppTheme.accentColor)
                        }
                        
                        // Speed & ETA
                        if item.status == .downloading {
                            HStack {
                                if let speed = item.currentSpeed {
                                    Label(Formatters.formatSpeed(speed), systemImage: "arrow.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if let eta = item.estimatedTimeRemaining {
                                    Label(Formatters.formatRemainingTime(eta), systemImage: "clock")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                // Error Callout (if any)
                if let error = item.lastError {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.errorColor)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.errorColor)
                            .lineLimit(2)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.errorColor.opacity(0.1), in: .rect(cornerRadius: 6))
                }
                
                // Bottom Row: Size + Progress % + Action buttons
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(Formatters.formatTransfer(received: item.bytesReceived, total: item.expectedTotalBytes))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if let pct = item.progress, showProgressBar {
                            Text("(\(Int(pct * 100))%)")
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.color(for: item.status))
                        }
                    }
                    .minimumScaleFactor(0.8)
                    
                    Spacer(minLength: 4)
                    
                    // Single-layer Action Controls
                    actionControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Action Controls (Immediate State Toggle)
    
    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: 8) {
            switch item.status {
            case .downloading:
                if let onPause {
                    Button {
                        onPause()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pause Download")
                }
                if let onCancel {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.errorColor)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.errorColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel Download")
                }
                
            case .paused:
                if let onResume {
                    Button {
                        onResume()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume Download")
                }
                if let onCancel {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.errorColor)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.errorColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel Download")
                }
                
            case .queued:
                if let onCancel {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel Queued")
                }
                
            case .failed, .interrupted:
                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Retry")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(AppTheme.accentColor, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry Download")
                }
                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.errorColor)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.errorColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete Download")
                }
                
            case .completed:
                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete File")
                }
                
            case .cancelled:
                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.accentColor)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.accentColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Restart")
                }
                if let onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var showProgressBar: Bool {
        item.status == .downloading || item.status == .paused || (item.status == .interrupted && item.bytesReceived > 0)
    }
    
    private var subtitleText: String {
        if item.status == .completed, let completedAt = item.completedAt {
            return "Completed \(Formatters.formatRelativeDate(completedAt))"
        } else if let startedAt = item.startedAt {
            return "Started \(Formatters.formatRelativeDate(startedAt))"
        } else {
            return "Queued \(Formatters.formatRelativeDate(item.createdAt))"
        }
    }
}
