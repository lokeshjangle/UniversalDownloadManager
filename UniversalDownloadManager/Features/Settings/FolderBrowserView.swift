import SwiftUI

/// Visual folder browser view allowing users to browse, select, or create download directories
/// both in-app and through the native Apple Files app folder picker.
struct FolderBrowserView: View {
    @ObservedObject var store: DownloadStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var availableFolders: [FolderInfo] = []
    @State private var showingFilesAppPicker: Bool = false
    @State private var showingNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    
    private let storage = FileStorageService.shared
    
    var body: some View {
        List {
            // Section 1: Active Selection Header
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "folder.fill.badge.checkmark")
                        .font(.title)
                        .foregroundStyle(AppTheme.accentColor)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active Download Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(storage.currentFolderDisplayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // Section 2: Apple Files App Native Browser
            Section {
                Button {
                    showingFilesAppPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.blue, in: .rect(cornerRadius: 8))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse in Apple Files App...")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Select any folder on iPhone or iCloud Drive")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("System Files App")
            } footer: {
                Text("Opens the native iOS folder picker sheet to visually browse your device.")
            }
            
            // Section 3: Available In-App Folders (Visual List)
            Section {
                ForEach(availableFolders) { folder in
                    Button {
                        selectFolder(folder.name)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: folderIcon(for: folder.name))
                                .font(.title3)
                                .foregroundStyle(folderColor(for: folder.name))
                                .frame(width: 32, height: 32)
                                .background(folderColor(for: folder.name).opacity(0.12), in: .rect(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                
                                Text("\(folder.fileCount) \(folder.fileCount == 1 ? "file" : "files")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if isCurrentFolder(folder.name) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.successColor)
                            }
                        }
                    }
                }
                
                // Add New Folder Action
                Button {
                    newFolderName = ""
                    showingNewFolderAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accentColor)
                        Text("Create New Folder...")
                            .foregroundStyle(AppTheme.accentColor)
                    }
                }
            } header: {
                Text("In-App Storage Folders")
            } footer: {
                Text("Tap any folder to set it as your default download destination.")
            }
        }
        .navigationTitle("Select Folder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshFolders()
        }
        .sheet(isPresented: $showingFilesAppPicker) {
            FolderPicker { pickedURL in
                storage.selectExternalFolder(url: pickedURL)
                store.currentDownloadFolder = storage.currentFolderDisplayName
                refreshFolders()
            }
        }
        .alert("Create New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Folder Name", text: $newFolderName)
            Button("Create") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    storage.createNewInAppFolder(named: trimmed)
                    selectFolder(trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new download folder.")
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func selectFolder(_ name: String) {
        storage.selectInAppFolder(named: name)
        store.currentDownloadFolder = name
        refreshFolders()
    }
    
    private func isCurrentFolder(_ name: String) -> Bool {
        !storage.isExternalFolderActive && storage.currentSubdirectory.lowercased() == name.lowercased()
    }
    
    private func refreshFolders() {
        self.availableFolders = storage.availableInAppFolders()
    }
    
    private func folderIcon(for name: String) -> String {
        switch name.lowercased() {
        case "media", "videos", "music": return "film.stack.fill"
        case "documents", "pdfs", "work": return "doc.text.fill"
        case "archives", "zips": return "doc.zipper"
        default: return "folder.fill"
        }
    }
    
    private func folderColor(for name: String) -> Color {
        switch name.lowercased() {
        case "media", "videos", "music": return .purple
        case "documents", "pdfs", "work": return .blue
        case "archives", "zips": return .indigo
        default: return .orange
        }
    }
}

