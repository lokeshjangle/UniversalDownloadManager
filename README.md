# Universal Download Manager for iOS

[![Platform](https://img.shields.io/badge/Platform-iOS%2018%2B-blue.svg?style=flat-square)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-16.0%2B-blueviolet.svg?style=flat-square)](https://developer.apple.com/xcode/)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20SwiftUI%20%2B%20URLSession-success.svg?style=flat-square)](https://developer.apple.com)
[![Status](https://img.shields.io/badge/Code%20Readiness-Verified-brightgreen.svg?style=flat-square)](#-code-readiness-audit--checklist)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg?style=flat-square)](LICENSE)

A high-performance background download manager for iPhone engineered with **Swift 6**, **Liquid Glass** design principles, system daemon Foundation `URLSession` background execution (`nsurlsessiond`), native **Apple Photos Camera Roll** auto-saving, an **In-App Authenticated Browser** for Instagram stories and reels, and seamless integrations with **Safari** and **Google Chrome**.

---

## 🌟 Key Features & Capabilities

- **True Background Execution (`nsurlsessiond`):** Downloads are delegated directly to iOS daemon processes. Transfers persist uninterrupted across app suspension, device lock, and multitasking. Data streams straight to disk in byte-ranged chunks without consuming device RAM.
- **In-App Authenticated Browser:** Built-in secure `WKWebView` browser with cookie and session synchronization via `InstagramSessionManager`. Users log in once to download private stories, reels, and posts with 1 tap, directly on-device without external token leaks.
- **Photos App Camera Roll Integration:** Media files (`.mp4`, `.mov`, `.jpg`, `.png`, `.heic`) are automatically discovered upon completion and imported directly to the native iOS Photos Camera Roll via `PhotoLibraryService`.
- **Apple Files App & Visual Folder Picker:** Files persist in `Documents/Downloads/` and appear immediately in `Files.app > On My iPhone > Universal Download Manager`. Includes a visual folder browser for sub-folder organization.
- **Google Chrome & System Share Sheet Extension:** Share links directly from Chrome, Firefox, or any iOS app into the download queue with filename preview, URL sanitization, and confirmation dialogs.
- **Safari Web Extension (Manifest V3):** Embedded native Safari extension featuring link discovery, 1-tap background downloading, and strict minimal `activeTab` host permissions.
- **Robust Failure Resilience:** Byte-range resume support for interrupted connections, automated collision protection (`filename (1).ext`), and automated cleanup of temporary fragments.
- **Liquid Glass Design System:** Crafted with adaptive translucent materials, specular highlights, and dynamic color tokens supporting both Light and Dark modes.

---

## 📋 Code Readiness Audit & Checklist

This repository has completed a pre-production code readiness verification:

| Category | Item | Verification Status | Implementation Details |
| :--- | :--- | :---: | :--- |
| **Data Integrity** | Zero Mock / Sample Data | ✅ Verified | All hardcoded test downloads and demo links removed from `DownloadStore.swift` and `AddDownloadView.swift`. Startup storage sweep automatically purges legacy mock files. |
| **Security** | Intranet / SSRF Protection | ✅ Verified | `DownloadCoordinator.isPrivateOrLocalAddress(url:)` blocks RFC 1918 / loopback IP addresses from external handoffs. |
| **Security** | Domain Spoofing Defense | ✅ Verified | Strict subdomain & host validation (`MediaResolverService.swift`) blocks credentials from leaking to spoofed domains (e.g. `attacker-instagram.com`). |
| **Security** | Path Traversal Sanitization | ✅ Verified | `FileStorageService.swift` and `PhotoLibraryService.swift` strictly constrain all file operations to sandboxed directories (`Documents`, `Caches`, `tmp`). |
| **Concurrency** | Swift 6 Concurrency Safety | ✅ Verified | Authoritative `@MainActor` state management in `DownloadStore`, actor isolation for disk and photo library operations. |
| **Privacy & TCC** | Permissions & Info.plist | ✅ Verified | `NSPhotoLibraryAddUsageDescription` and `NSPhotoLibraryUsageDescription` configured with user-facing explanations. |
| **App Groups** | Cross-Process Queue | ✅ Verified | Shared app container entitlement `group.com.lokeshjangale.UniversalDownloadManager` synchronizes Share Extension and Safari Extension queues. |
| **Assets** | Official Liquid Glass App Icon | ✅ Verified | 1024x1024 AppIcon asset generated and validated with zero asset catalog compilation errors. |

---

## 🏗️ Architecture & Component Layout

```
UniversalDownloadManager/
├── UniversalDownloadManager/               # Main Host Application
│   ├── App/
│   │   ├── UniversalDownloadManagerApp.swift # App entry point & lifecycle
│   │   ├── AppDelegate.swift               # Background URLSession delegate & event replay
│   │   └── ContentView.swift               # Root tab navigation
│   ├── ViewModels/
│   │   └── DownloadStore.swift             # Authoritative state engine & queue orchestrator
│   ├── Models/
│   │   ├── DownloadItem.swift              # Observable download item model
│   │   └── DownloadStatus.swift            # State enum (queued, downloading, completed, failed, paused)
│   ├── Services/
│   │   ├── BackgroundDownloadService.swift # URLSessionDownloadTask daemon wrapper
│   │   ├── DownloadCoordinator.swift       # URL validation, SSRF checks & filename extraction
│   │   ├── FileStorageService.swift        # Sandboxed file manager & collision resolution
│   │   ├── MediaResolverService.swift      # On-device & remote media stream extraction
│   │   ├── InstagramSessionManager.swift   # WKHTTPCookieStore session persistence
│   │   ├── PhotoLibraryService.swift       # PHPhotoLibrary Camera Roll export
│   │   └── DownloadPersistence.swift       # Metadata persistence across app launches
│   ├── Features/
│   │   ├── Dashboard/DashboardView.swift   # Overview metrics & quick actions
│   │   ├── AddDownload/AddDownloadView.swift # URL input, clipboard paste & stream resolution
│   │   ├── Browser/InAppBrowserView.swift  # Authenticated story & reel browser
│   │   ├── Detail/DownloadDetailsView.swift # Transfer telemetry, speed graphs & file inspector
│   │   └── Settings/SettingsView.swift     # Storage management, session status & options
│   ├── DesignSystem/
│   │   ├── AppTheme.swift                  # Color palettes & liquid glass styles
│   │   └── GlassComponents.swift           # Reusable translucent cards & buttons
│   └── Shared/
│       └── PendingRequestsStore.swift      # App Group queue reader
├── ShareExtension/                         # iOS Share Sheet App Extension
│   ├── ShareViewController.swift           # Input item extraction & handoff
│   ├── ShareSheetView.swift                # Liquid glass confirmation card
│   └── PendingRequestsStore.swift          # App Group queue writer
├── SafariExtension/                        # Safari Web Extension (Manifest V3)
│   ├── SafariWebExtensionHandler.swift     # Native Swift extension messaging bridge
│   └── Resources/                          # Popup UI, background scripts & manifest
└── Config/                                 # Entitlements & Info.plist definitions
```

---

## ⚡ Quick Start: Build & Verification

### Prerequisites
- macOS Sequoia (or latest) with **Xcode 16.0+**
- iOS 18.0+ Simulator or physical device with **Developer Mode** enabled

### 1. Build Verification via Command Line
Run a clean build for the iOS Simulator:
```bash
xcodebuild -project UniversalDownloadManager/UniversalDownloadManager.xcodeproj \
  -scheme UniversalDownloadManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO
```

### 2. Run on Simulator
```bash
# Boot the simulator
xcrun simctl boot "iPhone 17 Pro"

# Install the built .app bundle
xcrun simctl install booted /Users/lokeshjangale/Library/Developer/Xcode/DerivedData/UniversalDownloadManager-*/Build/Products/Debug-iphonesimulator/UniversalDownloadManager.app

# Launch the app
xcrun simctl launch booted com.lokeshjangale.UniversalDownloadManager
```

---

## 📱 User Workflows

### 1. In-App Authenticated Instagram Download
1. Navigate to **Browser** or tap **Browse Instagram Stories & Reels** from the Add Download tab.
2. Log in securely via the embedded browser. Session cookies are securely persisted on-device in `WKHTTPCookieStore`.
3. Open any story, reel, or private post.
4. Tap the purple **Download Media** badge to immediately capture the stream into your download queue.

### 2. Auto-Save to Photos App
- When enabled in **Settings > Auto-Save to Photos App**, any completed video or photo is automatically exported to your iOS Photos Camera Roll upon download completion.
- You can also manually export any completed download at any time from the **Download Details** view.

### 3. Share from Google Chrome or Safari
- **Chrome:** Tap the Share button on any link > choose **Universal Download** > tap **Add to Download Queue**.
- **Safari:** Tap the extensions icon (🧩) in the address bar > select **Universal Download Manager** > tap **Download in Background**.

---

## 🔒 Security & Privacy Commitments

- **No Third-Party Analytics / Tracking:** No telemetry, tracking scripts, or ad networks are bundled.
- **On-Device Cookie Storage:** Social login credentials remain inside Apple's sandboxed `WKHTTPCookieStore` and are never transmitted to external logging servers.
- **Sandboxed Storage:** All downloads and temporary chunks are locked inside the application's sandboxed container and shared App Group directory.

---

## 📄 License
This project is released under the **MIT License**.
