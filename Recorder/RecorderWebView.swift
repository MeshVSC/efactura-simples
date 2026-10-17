import SwiftUI
import WebKit

// Project root, resolved at compile time from this file's location.
private let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

final class CaptureLog: ObservableObject {
    @Published private(set) var count = 0
    let fileURL = projectRoot.appendingPathComponent("Capture/capture.jsonl")

    init() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func append(_ event: [String: Any]) {
        var entry = event
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
        try? handle.close()
        DispatchQueue.main.async { self.count += 1 }
    }
}

struct RecorderWebView: NSViewRepresentable {
    let log: CaptureLog

    func makeCoordinator() -> Coordinator { Coordinator(log: log) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let scriptURL = projectRoot.appendingPathComponent("Recorder/capture.js")
        if let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(script)
        } else {
            log.append(["kind": "error", "message": "capture.js not found at \(scriptURL.path)"])
        }
        config.userContentController.add(context.coordinator, name: "capture")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://faturas.portaldasfinancas.gov.pt/home.action")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let log: CaptureLog

        init(log: CaptureLog) { self.log = log }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] {
                log.append(body)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let request = navigationAction.request
            log.append([
                "kind": "navigation-request",
                "mainFrame": navigationAction.targetFrame?.isMainFrame ?? false,
                "method": request.httpMethod ?? "",
                "url": request.url?.absoluteString ?? "",
                "headers": request.allHTTPHeaderFields ?? [:],
            ])
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let response = navigationResponse.response as? HTTPURLResponse {
                var headers: [String: String] = [:]
                for (key, value) in response.allHeaderFields {
                    headers["\(key)"] = "\(value)"
                }
                log.append([
                    "kind": "navigation-response",
                    "mainFrame": navigationResponse.isForMainFrame,
                    "status": response.statusCode,
                    "url": response.url?.absoluteString ?? "",
                    "headers": headers,
                ])
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? ""
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [log] result, _ in
                log.append([
                    "kind": "page-html",
                    "url": url,
                    "html": result as? String ?? "",
                ])
            }
        }
    }
}
