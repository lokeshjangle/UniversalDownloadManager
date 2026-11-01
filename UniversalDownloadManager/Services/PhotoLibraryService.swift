import Foundation
import Photos
import UIKit

/// Service responsible for importing completed video and image downloads
/// directly into the Apple Photos app (Camera Roll).
final class PhotoLibraryService: Sendable {
    static let shared = PhotoLibraryService()
    
    private init() {}
    
    // MARK: - Format Detection
    
    /// Checks whether a given filename represents a playable video or photo format.
    func isMediaFile(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        let supportedMediaExtensions: Set<String> = [
            "mp4", "mov", "m4v", "3gp",
            "jpg", "jpeg", "png", "heic", "webp", "gif"
        ]
        return supportedMediaExtensions.contains(ext)
    }
    
    func isVideoFile(filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "3gp"].contains(ext)
    }
    
    // MARK: - Saving to Camera Roll
    
    /// Saves a downloaded video or image to the Photos app Camera Roll.
    func saveMediaToPhotos(fileURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "PhotoLibraryError",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "File does not exist on disk at path: \(fileURL.lastPathComponent)"]
            )
        }
        
        let filename = fileURL.lastPathComponent
        guard isMediaFile(filename: filename) else {
            throw NSError(
                domain: "PhotoLibraryError",
                code: 415,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported media format for Photos app: \(filename)"]
            )
        }
        
        // Security check: Ensure fileURL is strictly confined to app-authorized storage (prevents internal data leak)
        let standardPath = fileURL.standardizedFileURL.path
        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? ""
        let tempPath = FileManager.default.temporaryDirectory.path
        
        guard (!docsPath.isEmpty && standardPath.hasPrefix(docsPath)) ||
              (!cachesPath.isEmpty && standardPath.hasPrefix(cachesPath)) ||
              standardPath.hasPrefix(tempPath) else {
            throw NSError(
                domain: "PhotoLibraryError",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Security Violation: Unauthorized file location cannot be imported to Photos."]
            )
        }
        
        // Request add-only permission (standard privacy-friendly level in modern iOS)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(
                domain: "PhotoLibraryError",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Permission to save to the Photos app was denied. You can enable it in iOS Settings > Universal Download Manager."]
            )
        }
        
        let isVideo = isVideoFile(filename: filename)
        
        try await PHPhotoLibrary.shared().performChanges {
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }
        }
    }
}
