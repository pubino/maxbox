import SwiftUI
import WebKit

struct HTMLContentView: NSViewRepresentable {
    let html: String
    var allowRemoteImages: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.allowRemoteImages = allowRemoteImages
        let wrapped = wrapHTML(html)
        webView.loadHTMLString(wrapped, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(allowRemoteImages: allowRemoteImages)
    }

    private func wrapHTML(_ body: String) -> String {
        let isDark = colorScheme == .dark
        let textColor = isDark ? "#e5e5e5" : "#1d1d1f"
        let bgColor = isDark ? "transparent" : "transparent"
        let linkColor = isDark ? "#6cb4f0" : "#0066cc"

        let imageBlockCSS = allowRemoteImages ? "" : """
            img[src^="http"] { display: none !important; }
        """

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
                font-size: 14px;
                line-height: 1.5;
                color: \(textColor);
                background-color: \(bgColor);
                margin: 0;
                padding: 0;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            a { color: \(linkColor); }
            img { max-width: 100%; height: auto; }
            \(imageBlockCSS)
            pre, code {
                font-family: "SF Mono", Menlo, monospace;
                font-size: 13px;
            }
            blockquote {
                border-left: 3px solid \(isDark ? "#555" : "#ccc");
                margin-left: 0;
                padding-left: 12px;
                color: \(isDark ? "#999" : "#666");
            }
            table { border-collapse: collapse; max-width: 100%; }
            td, th { padding: 4px 8px; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var allowRemoteImages: Bool

        init(allowRemoteImages: Bool) {
            self.allowRemoteImages = allowRemoteImages
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Allow initial load, open links externally
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                return .cancel
            }

            // Block remote image loads when not allowed
            if !allowRemoteImages,
               let url = navigationAction.request.url,
               let scheme = url.scheme,
               (scheme == "http" || scheme == "https"),
               navigationAction.navigationType == .other {
                let ext = url.pathExtension.lowercased()
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico"]
                if imageExtensions.contains(ext) {
                    return .cancel
                }
            }

            return .allow
        }
    }
}
