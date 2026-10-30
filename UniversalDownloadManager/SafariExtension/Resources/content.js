// Universal Download Manager - Safari Content Script
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "scanPage") {
        const filePattern = /\.(pdf|zip|mp4|mov|dmg|pkg|iso|tar|gz|tgz|bz2|csv|xlsx|docx|mp3|m4a|epub|apk)(\?.*)?$/i;
        const links = [];
        
        // 1. Detect on-page video elements (e.g. Instagram, Web players)
        document.querySelectorAll("video").forEach((video, idx) => {
            const src = video.currentSrc || video.src;
            if (src && (src.startsWith("http://") || src.startsWith("https://"))) {
                links.push({
                    url: src,
                    text: `🎬 Video Stream ${idx + 1} (.mp4)`
                });
            }
        });
        
        // 2. Detect OpenGraph video meta tag
        const ogVideo = document.querySelector('meta[property="og:video"]')?.content ||
                        document.querySelector('meta[property="og:video:secure_url"]')?.content;
        if (ogVideo && (ogVideo.startsWith("http://") || ogVideo.startsWith("https://"))) {
            links.push({
                url: ogVideo,
                text: `🎬 ${document.title || 'Page Video'} (.mp4)`
            });
        }
        
        // 3. Scan standard file links
        document.querySelectorAll("a[href]").forEach(a => {
            const href = a.href;
            if (href && (href.startsWith("http://") || href.startsWith("https://"))) {
                if (filePattern.test(href) || a.hasAttribute("download")) {
                    links.push({
                        url: href,
                        text: (a.textContent || a.title || href.split("/").pop()).trim()
                    });
                }
            }
        });
        
        sendResponse({
            title: document.title,
            url: window.location.href,
            links: links
        });
        return false;
    }
});

