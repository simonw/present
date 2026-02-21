import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: String
    var pageZoom: Double = 1.0
    var scrollDelta: Double = 0

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = pageZoom
        loadURL(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = pageZoom
        loadURL(in: webView)
        if scrollDelta != 0 {
            let js = "window.scrollBy(0, \(scrollDelta));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func loadURL(in webView: WKWebView) {
        guard let parsed = URL(string: url), parsed.scheme != nil else {
            if let parsed = URL(string: "https://\(url)") {
                let request = URLRequest(url: parsed)
                webView.load(request)
            }
            return
        }
        let request = URLRequest(url: parsed)
        if webView.url != parsed {
            webView.load(request)
        }
    }
}
