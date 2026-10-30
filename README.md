# Universal Download Manager for iOS

A modern, high-performance background download manager for iPhone built with Swift 6, iOS 27 Liquid Glass design principles, Foundation `URLSession` background execution, and direct integration with Safari and Google Chrome.

---

## Features

- **Liquid Glass Interface:** Native SwiftUI UI utilizing official iOS 27 Liquid Glass APIs (`.glassEffect`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`). Automatically adapts to Light and Dark modes.
- **Background Engine:** True system-level background execution powered by `URLSessionDownloadTask` in `nsurlsessiond`. Downloads continue seamlessly across app switching, screen lock, and system suspensions without loading large files into RAM.
- **Apple Files App Integration:** Files are persisted in `Documents/Downloads/` and accessible directly in the native Apple Files app (`On My iPhone > Universal Download Manager`).
- **Visual Folder Browser:** In-app visual folder browser allowing users to choose or create custom download folders, or pick any external destination using Apple's document picker.
- **Chrome Share Sheet Extension:** Share links directly from Google Chrome, Firefox, or any iOS app into the download queue with filename preview and confirmation.
- **Safari Web Extension:** Native Manifest V3 Safari extension with a toolbar popup for 1-tap background downloading, automatic on-page link discovery, and minimal `activeTab` permissions.
- **Resilience & Collision Protection:** Byte-range resume support, automatic duplicate collision handling (`file (1).ext`), path traversal sanitization, and automated cleanup of stale temporary fragments.

---

## Project Structure

```
UniversalDownloadManager/
├── UniversalDownloadManager/       # Main Host App
│   ├── App/                        # App entry point, AppDelegate, ContentView
│   ├── ViewModels/                 # DownloadStore (Authoritative state)
│   ├── Models/                     # DownloadItem, DownloadStatus
│   ├── Services/                   # BackgroundDownloadService, DownloadCoordinator, FileStorageService, DownloadPersistence
│   ├── DesignSystem/               # Liquid Glass design system, AppTheme, GlassComponents
│   ├── Features/                   # Dashboard, Active, Completed, Failed, AddDownload, Detail, Settings
│   └── Shared/                     # PendingRequestsStore (Cross-process queue)
├── ShareExtension/                 # iOS Share Sheet App Extension
│   ├── ShareViewController.swift   # URL extraction & handoff controller
│   ├── ShareSheetView.swift        # Liquid Glass modal confirmation card
│   └── PendingRequestsStore.swift  # Shared persistence
├── SafariExtension/                # Safari Web Extension (Manifest V3)
│   ├── SafariWebExtensionHandler.swift # Native Swift messaging handler
│   └── Resources/                  # manifest.json, popup.html, popup.css, popup.js, background.js, content.js
└── Config/                         # Info.plist & Entitlements configuration
```

---

## Installation & Running on Device

1. Open the project in Xcode:
   ```bash
   open UniversalDownloadManager/UniversalDownloadManager.xcodeproj
   ```
2. In the project settings, select your personal Apple ID team under **Signing & Capabilities**.
3. Connect your iPhone and ensure **Developer Mode** is turned ON in iPhone Settings (`Settings > Privacy & Security > Developer Mode`).
4. Select your device and press **Run** (`⌘R`).
5. On your iPhone, trust your developer certificate under `Settings > General > VPN & Device Management`.

---

## How to Use

### Chrome & Share Sheet
1. In Chrome, tap **Share** on any link or page.
2. Select **Universal Download**.
3. Customize the filename if desired and tap **Add to Download Queue**.

### Safari Web Extension
1. Enable the extension in iPhone Settings (`Settings > Apps > Safari > Extensions > Universal Download Manager > ON`).
2. In Safari, tap the extension icon (🧩) in the address bar.
3. Select a detected link or enter a URL, and tap **Download in Background**.

---

## License
MIT License. Developed with Apple Foundation & SwiftUI.

