import Network
import SwiftUI
import WebKit

@MainActor
final class BrowserState: ObservableObject {
    @Published var title = "绅士漫画"
    @Published var isLoading = true
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var error: String?
    weak var webView: WKWebView?
}

struct HomeView: View {
    @StateObject private var browser = BrowserState()
    private let homeURL = URL(string: "https://www.wnacg.com/")!

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SiteWebView(browser: browser, url: homeURL)
                    .ignoresSafeArea(edges: .bottom)

                if browser.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.mint)
                }
            }
            .navigationTitle(browser.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        browser.webView?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!browser.canGoBack)

                    Button {
                        browser.webView?.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!browser.canGoForward)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        browser.webView?.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button {
                        browser.webView?.load(URLRequest(url: homeURL))
                    } label: {
                        Image(systemName: "house")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let error = browser.error {
                    Text(error)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct SiteWebView: UIViewRepresentable {
    @ObservedObject var browser: BrowserState
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let store = WKWebsiteDataStore.default()

        if #available(iOS 17.0, *) {
            let port = LocalProxy.shared.port
            if port > 0, let nwPort = NWEndpoint.Port(rawValue: port) {
                var proxy = ProxyConfiguration(
                    httpCONNECTProxy: .hostPort(
                        host: "127.0.0.1", port: nwPort
                    )
                )
                proxy.excludedDomains = ["localhost", "127.0.0.1"]
                store.proxyConfigurations = [proxy]
            } else {
                browser.error = "本地代理未启动，网页可能无法加载"
            }
        }
        configuration.websiteDataStore = store

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.load(URLRequest(url: url))
        browser.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browser: BrowserState

        init(browser: BrowserState) {
            self.browser = browser
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            browser.isLoading = true
            browser.error = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            browser.isLoading = false
            browser.title = webView.title?.isEmpty == false ? webView.title! : "绅士漫画"
            updateNavigation(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            updateNavigation(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            browser.isLoading = false
            browser.error = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            browser.isLoading = false
            browser.error = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func updateNavigation(_ webView: WKWebView) {
            browser.canGoBack = webView.canGoBack
            browser.canGoForward = webView.canGoForward
        }
    }
}
