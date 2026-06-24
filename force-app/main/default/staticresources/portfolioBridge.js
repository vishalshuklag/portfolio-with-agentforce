/**
 * Page-context bridge for the portfolioHome LWC.
 *
 * The component runs under Lightning Web Security and cannot reliably (a) call the
 * Embedded Messaging API (embeddedservice_bootstrap lives in page context) or
 * (b) trigger a Blob/anchor download. This script is loaded by the component via
 * lightning/platformResourceLoader, so it executes in page context where both work.
 * The component communicates by dispatching window CustomEvents.
 */
(function () {
    if (window.__portfolioBridgeInstalled) {
        return;
    }
    window.__portfolioBridgeInstalled = true;

    function launchChat() {
        try {
            var b = window.embeddedservice_bootstrap;
            if (b && b.utilAPI && typeof b.utilAPI.launchChat === 'function') {
                b.utilAPI.launchChat();
                return true;
            }
        } catch (e) {
            /* not ready yet */
        }
        return false;
    }

    window.addEventListener('portfolioLaunchChat', function () {
        if (launchChat()) {
            return;
        }
        // Embedded Messaging may still be initializing — retry for a few seconds.
        var tries = 0;
        var timer = setInterval(function () {
            tries += 1;
            if (launchChat() || tries > 20) {
                clearInterval(timer);
            }
        }, 300);
    });

    window.addEventListener('portfolioDownloadPdf', function (evt) {
        try {
            var detail = (evt && evt.detail) || {};
            var b64 = detail.base64;
            var filename = detail.filename || 'portfolio.pdf';
            if (!b64) {
                return;
            }
            var binary = atob(b64);
            var len = binary.length;
            var bytes = new Uint8Array(len);
            for (var i = 0; i < len; i++) {
                bytes[i] = binary.charCodeAt(i);
            }
            var blob = new Blob([bytes], { type: 'application/pdf' });
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(function () {
                URL.revokeObjectURL(url);
            }, 5000);
        } catch (e) {
            // As a last resort, open the PDF in a new tab.
            try {
                var w = window.open('', '_blank');
                if (w) {
                    w.document.write(
                        '<iframe width="100%" height="100%" src="data:application/pdf;base64,' +
                            (evt.detail && evt.detail.base64) +
                            '"></iframe>'
                    );
                }
            } catch (e2) {
                /* ignore */
            }
        }
    });
})();
