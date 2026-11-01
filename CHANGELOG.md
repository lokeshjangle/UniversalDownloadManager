# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-11-01

### Added
- **True Background Execution (`nsurlsessiond`):** URLSession daemon background execution with automatic transfer resumption across app suspension, background timeouts, and device reboots.
- **In-App Authenticated Browser:** Embedded secure `WKWebView` browser with cookie synchronization (`InstagramSessionManager`) for downloading authenticated Instagram stories, reels, and media on-device.
- **Photos App Camera Roll Integration:** Automatic discovery and export of completed video (`.mp4`, `.mov`) and image (`.jpg`, `.png`, `.heic`) media directly to the user's Photos library via `PhotoLibraryService`.
- **System Share Sheet Extension:** iOS Share Sheet extension enabling 1-tap download queues directly from Google Chrome, Firefox, and third-party apps with URL sanitization and filename confirmation.
- **Safari Web Extension (Manifest V3):** Native Safari extension with link discovery, native messaging bridge (`SafariWebExtensionHandler`), and minimal permission boundaries.
- **Media Stream Resolution Engine:** `MediaResolverService` with support for high-quality video/audio extraction, API key configuration, and friendly error mapping.
- **Liquid Glass Design System:** Adaptive translucent materials, specular highlights, and fluid navigation across all dashboard and detail views.
- **Apple Files App Integration:** Sandboxed file management in `Documents/Downloads/` exposing downloaded files directly in `Files.app > On My iPhone > Universal Download Manager` with a visual folder picker.
- **App Groups Queue Sync:** Cross-process queue synchronization using `group.com.lokeshjangale.UniversalDownloadManager` across host app and extensions.
- **GitHub Actions CI Workflow:** Automated Xcode clean-build validation workflow (`.github/workflows/swift.yml`) running on `macos-latest` runners.
- **Shared Xcode Scheme:** Explicitly versioned and tracked `UniversalDownloadManager.xcscheme` for reproducible CI/CD builds.

### Changed
- **Repository Architecture Refactor:** Flattened nested directory hierarchy by moving project files and configuration from `UniversalDownloadManager/UniversalDownloadManager` to repository root.
- **RFC 5987 Support:** Support for international character encodings in HTTP `Content-Disposition: filename*` headers.
- **Dynamic Filename Resolution:** Optional custom filenames allowing automatic server-sent header extraction to take precedence and update display labels upon download completion.

### Security
- **SSRF & Intranet Defense:** Implemented `DownloadCoordinator.isPrivateOrLocalAddress(url:)` to block RFC 1918 private subnets and loopback addresses from external handoffs.
- **Domain Spoofing Defense:** Strict hostname and subdomain validation in `MediaResolverService` to prevent authentication cookies from leaking to malicious third-party domains.
- **Path Traversal Protection:** Constrained all file persistence and export operations strictly within approved sandboxed directories (`Documents`, `Caches`, `tmp`).
- **Privacy & Permissions (TCC):** Configured user-facing usage descriptions for `NSPhotoLibraryAddUsageDescription` and `NSPhotoLibraryUsageDescription`.

### Fixed
- Byte-range resume data persistence preventing corrupted file states on network interruptions.
- Automated file collision protection (`filename (1).ext`) when duplicate filenames are queued.
- Eliminated all hardcoded demo mock files and added automated startup cleanup for legacy test files.
