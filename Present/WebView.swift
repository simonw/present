import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: String
    var pageZoom: Double = 1.0

    private var isImageURL: Bool {
        let lower = url.lowercased().split(separator: "?").first.map(String.init) ?? url.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".gif") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") || lower.hasSuffix(".svg")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.startListening()
        applyContent(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        applyContent(in: webView)
    }

    private func applyContent(in webView: WKWebView) {
        if isImageURL {
            webView.pageZoom = 1.0
            let resolvedURL = resolveURL(url)
            let currentBaseURL = webView.url?.absoluteString
            let imagePageID = "image:" + resolvedURL
            if currentBaseURL != imagePageID {
                let html = """
                <!DOCTYPE html>
                <html><head><meta name="viewport" content="width=device-width">
                <style>*{margin:0;padding:0}body{background:#000;display:flex;align-items:center;justify-content:center;min-height:100vh}img{width:100%;height:auto}</style>
                </head><body><img src="\(resolvedURL)"></body></html>
                """
                webView.loadHTMLString(html, baseURL: URL(string: imagePageID))
            }
        } else {
            webView.pageZoom = pageZoom
            loadURL(in: webView)
        }
    }

    private func resolveURL(_ raw: String) -> String {
        if let parsed = URL(string: raw), parsed.scheme != nil {
            return raw
        }
        return "https://\(raw)"
    }

    private func loadURL(in webView: WKWebView) {
        guard let parsed = URL(string: url), parsed.scheme != nil else {
            if let parsed = URL(string: "https://\(url)") {
                webView.load(URLRequest(url: parsed))
            }
            return
        }
        if webView.url != parsed {
            webView.load(URLRequest(url: parsed))
        }
    }

    class Coordinator {
        weak var webView: WKWebView?
        private var observer: NSObjectProtocol?

        func startListening() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .remoteScroll, object: nil, queue: .main
            ) { [weak self] notification in
                guard let dy = notification.userInfo?["dy"] as? Double,
                      let webView = self?.webView else { return }
                webView.evaluateJavaScript("window.scrollBy(0, \(dy));", completionHandler: nil)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
