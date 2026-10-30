import SwiftUI

/// Liquid Glass styled confirmation dialog presented inside the iOS Share Sheet.
struct ShareSheetView: View {
    @State var urlString: String
    @State var customFilename: String
    let errorMessage: String?
    
    let onConfirm: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var isSuccess = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Universal Download")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Share Sheet Transfer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
                
                if let errorMessage {
                    // Error state for malformed or unsupported URLs
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Unsupported Link")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                        }
                        
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.tint(.red.opacity(0.1)), in: .rect(cornerRadius: 14))
                } else {
                    // Valid URL Confirmation Card
                    VStack(alignment: .leading, spacing: 14) {
                        // URL Display
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TARGET LINK")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            
                            Text(urlString)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                        }
                        
                        // Filename Input
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SAVE AS")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            
                            TextField("Filename", text: $customFilename)
                                .font(.subheadline)
                                .padding(10)
                                .glassEffect(.regular, in: .rect(cornerRadius: 10))
                        }
                        
                        // Limitations and Auth Notice
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Direct files only. Chrome session cookies, paywalls, or stream segments (e.g. YouTube) cannot be downloaded without in-browser authentication.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                    .padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
                
                // Action Buttons — Vertical Stack per user design rules
                VStack(spacing: 10) {
                    if errorMessage == nil {
                        Button {
                            withAnimation {
                                isSuccess = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onConfirm(urlString, customFilename)
                            }
                        } label: {
                            HStack {
                                if isSuccess {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Added to Queue!")
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add to Download Queue")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isSuccess)
                    }
                    
                    Button {
                        onCancel()
                    } label: {
                        Text(errorMessage == nil ? "Cancel" : "Dismiss")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.3).ignoresSafeArea().onTapGesture {
            onCancel()
        })
    }
}
