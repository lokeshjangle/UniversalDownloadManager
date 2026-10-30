// Universal Download Manager - Safari Popup Controller
document.addEventListener("DOMContentLoaded", async () => {
    const pageTitleEl = document.getElementById("pageTitle");
    const pageUrlEl = document.getElementById("pageUrl");
    const detectedCountBadge = document.getElementById("detectedCountBadge");
    const detectedLinksContainer = document.getElementById("detectedLinksContainer");
    const linksSelect = document.getElementById("linksSelect");
    const targetUrlInput = document.getElementById("targetUrlInput");
    const filenameInput = document.getElementById("filenameInput");
    const downloadBtn = document.getElementById("downloadBtn");
    const statusBanner = document.getElementById("statusBanner");

    const fileExtensions = /\.(pdf|zip|mp4|mov|dmg|pkg|iso|tar|gz|tgz|bz2|csv|xlsx|docx|mp3|m4a|epub|apk)(\?.*)?$/i;

    function showStatus(message, isError = false) {
        statusBanner.textContent = message;
        statusBanner.className = `status-banner ${isError ? 'error' : 'success'}`;
        statusBanner.classList.remove("hidden");
    }

    function suggestFilename(urlStr) {
        try {
            const url = new URL(urlStr);
            const pathname = url.pathname;
            const segments = pathname.split("/").filter(Boolean);
            if (segments.length > 0) {
                return decodeURIComponent(segments[segments.length - 1]);
            }
        } catch (_) {}
        return "download";
    }

    // 1. Query Current Active Tab
    try {
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });
        if (tabs && tabs.length > 0) {
            const currentTab = tabs[0];
            pageTitleEl.textContent = currentTab.title || "Current Page";
            pageUrlEl.textContent = currentTab.url || "";

            // Pre-fill target URL with current tab URL if it is a downloadable file
            if (currentTab.url && (currentTab.url.startsWith("http://") || currentTab.url.startsWith("https://"))) {
                targetUrlInput.value = currentTab.url;
                filenameInput.value = suggestFilename(currentTab.url);
            }

            // 2. Scan webpage for downloadable links
            if (browser.scripting && currentTab.id) {
                try {
                    const results = await browser.scripting.executeScript({
                        target: { tabId: currentTab.id },
                        func: () => {
                            const found = [];
                            const filePattern = /\.(pdf|zip|mp4|mov|dmg|pkg|iso|tar|gz|tgz|bz2|csv|xlsx|docx|mp3|m4a|epub|apk)(\?.*)?$/i;
                            document.querySelectorAll("a[href]").forEach(a => {
                                const href = a.href;
                                if (href && (href.startsWith("http://") || href.startsWith("https://"))) {
                                    if (filePattern.test(href) || a.hasAttribute("download")) {
                                        found.push({
                                            url: href,
                                            text: (a.textContent || a.title || href.split("/").pop()).trim()
                                        });
                                    }
                                }
                            });
                            return found;
                        }
                    });

                    if (results && results[0] && results[0].result && results[0].result.length > 0) {
                        const links = results[0].result;
                        detectedCountBadge.textContent = `${links.length} link${links.length === 1 ? '' : 's'} found`;
                        detectedLinksContainer.classList.remove("hidden");

                        links.forEach((item, index) => {
                            const opt = document.createElement("option");
                            opt.value = item.url;
                            opt.textContent = `${item.text || 'File ' + (index + 1)} (${item.url.split('/').pop().split('?')[0]})`;
                            linksSelect.appendChild(opt);
                        });

                        // Default to the first found file link if tab URL is not a file
                        if (!fileExtensions.test(currentTab.url)) {
                            targetUrlInput.value = links[0].url;
                            filenameInput.value = suggestFilename(links[0].url);
                            linksSelect.value = links[0].url;
                        }
                    } else {
                        detectedCountBadge.textContent = "0 file links found";
                    }
                } catch (e) {
                    detectedCountBadge.textContent = "Direct URL entry";
                }
            }
        }
    } catch (e) {
        pageTitleEl.textContent = "Unable to read active tab";
        pageUrlEl.textContent = "";
    }

    // 3. Dropdown change listener
    linksSelect.addEventListener("change", (e) => {
        if (e.target.value) {
            targetUrlInput.value = e.target.value;
            filenameInput.value = suggestFilename(e.target.value);
        }
    });

    targetUrlInput.addEventListener("input", (e) => {
        if (e.target.value) {
            filenameInput.value = suggestFilename(e.target.value);
        }
    });

    // 4. Download Button Action
    downloadBtn.addEventListener("click", async () => {
        const url = targetUrlInput.value.trim();
        const filename = filenameInput.value.trim();

        if (!url) {
            showStatus("Please enter or select a download URL.", true);
            return;
        }

        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            showStatus("Only HTTP and HTTPS links are supported.", true);
            return;
        }

        downloadBtn.disabled = true;
        downloadBtn.innerHTML = `<span>Sending to Queue...</span>`;

        try {
            // Send native message to Swift SafariWebExtensionHandler
            const response = await browser.runtime.sendNativeMessage(
                "com.lokeshjangale.UniversalDownloadManager.SafariExtension",
                {
                    action: "enqueueDownload",
                    url: url,
                    filename: filename || suggestFilename(url)
                }
            );

            if (response && response.status === "accepted") {
                showStatus(`✅ Added "${response.filename || filename}" to download queue!`);
                downloadBtn.innerHTML = `<span>✓ Added to Queue</span>`;
            } else {
                showStatus(response?.message || "Failed to enqueue download.", true);
                downloadBtn.disabled = false;
                downloadBtn.innerHTML = `<span>Download in Background</span>`;
            }
        } catch (error) {
            // Fallback for native messaging communication
            showStatus(`Error communicating with native app: ${error.message || error}`, true);
            downloadBtn.disabled = false;
            downloadBtn.innerHTML = `<span>Download in Background</span>`;
        }
    });
});

