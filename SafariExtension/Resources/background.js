// Universal Download Manager - Safari Extension Service Worker
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "sendNativeDownload") {
        browser.runtime.sendNativeMessage("com.lokeshjangale.UniversalDownloadManager.SafariExtension", {
            action: "enqueueDownload",
            url: request.url,
            filename: request.filename
        }).then(response => {
            sendResponse(response);
        }).catch(error => {
            sendResponse({ status: "error", message: error.message || "Failed to communicate with native app" });
        });
        return true; // Indicates async response
    }
});

