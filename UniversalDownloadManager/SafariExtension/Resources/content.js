// Universal Download Manager - Safari Content Script
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "scanPage") {
        const filePattern = /\.(pdf|zip|mp4|mov|dmg|pkg|iso|tar|gz|tgz|bz2|csv|xlsx|docx|mp3|m4a|epub|apk)(\?.*)?$/i;
        const links = [];
        
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

