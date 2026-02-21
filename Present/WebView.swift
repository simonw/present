import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: String
    var pageZoom: Double = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = pageZoom
        context.coordinator.webView = webView
        context.coordinator.startListening()
        loadURL(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.pageZoom = pageZoom
        context.coordinator.webView = webView
        loadURL(in: webView)
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
