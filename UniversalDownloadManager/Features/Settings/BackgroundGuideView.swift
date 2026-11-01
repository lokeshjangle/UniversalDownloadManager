import SwiftUI

/// Educational and diagnostic screen explaining iOS background execution rules,
/// system daemon behaviors, and platform limitations.
struct BackgroundGuideView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Card
                GlassCard(cornerRadius: 18, padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.shield.fill")
                                .font(.title2)
                                .foregroundStyle(AppTheme.accentColor)
                            Text("iOS Background Architecture")
                                .font(.headline)
                        }
                        
                        Text("Universal Download Manager delegates downloads to Apple's system daemon (nsurlsessiond). Transfers run independently of the app's UI process.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Scenarios Breakdown
                scenarioCard(
                    title: "Switching Apps / Minimized",
                    status: "Permitted",
                    statusColor: AppTheme.successColor,
                    icon: "arrow.up.left.and.arrow.down.right",
                    description: "When you leave the app to check messages or use other apps, the download continues uninterrupted in the background through iOS's system networking service."
                )
                
                scenarioCard(
                    title: "Screen Locked",
                    status: "Permitted",
                    statusColor: AppTheme.successColor,
                    icon: "lock.fill",
                    description: "You can lock your iPhone or put it in your pocket. The system continues downloading data over Wi-Fi or cellular until the file is complete."
                )
                
                scenarioCard(
                    title: "System Termination (Low RAM)",
                    status: "Supported with Recovery",
                    statusColor: AppTheme.successColor,
                    icon: "memorychip",
                    description: "If iOS terminates the app UI to free memory for games or heavy apps, the system daemon keeps downloading. When finished, iOS wakes the app up in the background to move the file into your documents."
                )
                
                scenarioCard(
                    title: "Force-Quit (App Switcher Swipe)",
                    status: "Blocked by Apple Policy",
                    statusColor: AppTheme.errorColor,
                    icon: "hand.raised.fill",
                    description: "If you swipe up to force-quit the app in the iOS App Switcher, iOS treats this as an explicit user command to abort all background activity. All active transfers are cancelled by iOS until you re-open the app."
                )
                
                scenarioCard(
                    title: "Low Power Mode",
                    status: "System Throttled",
                    statusColor: AppTheme.warningColor,
                    icon: "battery.50percent",
                    description: "When Low Power Mode is on, iOS may pause or defer non-urgent background transfers until the device is plugged into power or re-opened."
                )
                
                scenarioCard(
                    title: "Network Interruption",
                    status: "Automatic Resume",
                    statusColor: AppTheme.accentColor,
                    icon: "wifi.exclamationmark",
                    description: "If Wi-Fi drops or is interrupted, the engine captures resume data fragments. When connectivity is restored, transfers resume from where they left off without restarting from zero."
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Background Guide")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func scenarioCard(
        title: String,
        status: String,
        statusColor: Color,
        icon: String,
        description: String
    ) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text(status)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: .capsule)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}

