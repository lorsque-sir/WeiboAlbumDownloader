import SwiftUI
import WebKit

// MARK: - Cookie 获取 WebView

/// 通过内嵌 WKWebView 实现微博扫码登录并提取 Cookie
/// 替代 C# 版的 WebView2（Microsoft Edge 内核）
/// 流程：加载微博 SSO 登录页 → 用户扫码 → 提取所有 Cookie → 回调给设置界面
struct CookieWebView: View {
    let dataSource: WeiboDataSource
    let onCookieObtained: (String) -> Void

    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("扫码登录")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Button("获取 Cookie") {
                    // 通过 NotificationCenter 通知 WebView 提取 Cookie
                    NotificationCenter.default.post(name: .extractCookie, object: nil)
                }
                .buttonStyle(.borderedProminent)

                Button("取消") { dismiss() }
            }
            .padding()

            Divider()

            WebViewRepresentable(
                url: loginURL,
                dataSource: dataSource,
                onCookieObtained: onCookieObtained,
                onLoadingChanged: { isLoading = $0 }
            )
        }
    }

    /// 根据数据源类型返回对应的微博 SSO 登录地址
    private var loginURL: URL {
        switch dataSource {
        case .weiboCn:
            return URL(string: "https://passport.weibo.com/sso/signin?entry=wapsso&source=wapssowb&url=https://weibo.cn")!
        case .weiboCnMobile:
            return URL(string: "https://passport.weibo.com/sso/signin?entry=wapsso&source=wapsso&url=https://m.weibo.cn")!
        default:
            return URL(string: "https://passport.weibo.com/sso/signin?entry=miniblog&source=miniblog&url=https://weibo.com/")!
        }
    }
}

extension Notification.Name {
    /// 用于触发 Cookie 提取的通知名
    static let extractCookie = Notification.Name("extractCookie")
    /// 设置已变更，通知 DownloadViewModel 重新配置（如 Cron 调度器）
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

/// WKWebView 的 NSViewRepresentable 桥接
/// 使用 nonPersistent DataStore 确保每次打开都是全新会话（不受之前登录状态影响）
struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let dataSource: WeiboDataSource
    let onCookieObtained: (String) -> Void
    let onLoadingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 使用非持久化 DataStore，关闭后 Cookie 自动清除
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))

        // 监听"获取 Cookie"按钮的通知
        let callback = onCookieObtained
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .extractCookie, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let cookie = await context.coordinator.extractCookies(from: webView)
                if !cookie.isEmpty {
                    callback(cookie)
                }
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dataSource: dataSource, onLoadingChanged: onLoadingChanged)
    }

    /// WKNavigationDelegate 协调器，负责页面加载状态和 Cookie 提取
    class Coordinator: NSObject, WKNavigationDelegate {
        let dataSource: WeiboDataSource
        let onLoadingChanged: (Bool) -> Void
        var observer: Any?

        init(dataSource: WeiboDataSource, onLoadingChanged: @escaping (Bool) -> Void) {
            self.dataSource = dataSource
            self.onLoadingChanged = onLoadingChanged
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged(false)
        }

        /// 从 WKWebView 的 Cookie 存储中提取目标域的所有 Cookie
        /// 不同数据源需要不同域的 Cookie（weibo.cn vs weibo.com）
        func extractCookies(from webView: WKWebView) async -> String {
            let urls: [String]
            switch dataSource {
            case .weiboCn:
                urls = ["https://weibo.cn", "https://passport.weibo.com"]
            case .weiboCnMobile:
                urls = ["https://m.weibo.cn", "https://weibo.cn", "https://passport.weibo.com"]
            default:
                urls = ["https://weibo.com", "https://passport.weibo.com"]
            }

            let store = webView.configuration.websiteDataStore.httpCookieStore
            let allCookies = await store.allCookies()

            // 按名称去重（同名 Cookie 只保留最后一个），并过滤出目标域的 Cookie
            var cookieMap: [String: HTTPCookie] = [:]
            let targetDomains = urls.compactMap { URL(string: $0)?.host }

            for cookie in allCookies {
                // Cookie domain 可能带前导点（如 .weibo.cn），需统一处理
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                if targetDomains.contains(where: { $0.contains(domain) || domain.contains($0) }) {
                    cookieMap[cookie.name] = cookie
                }
            }

            // 拼接为 HTTP Header 格式：name1=value1; name2=value2
            return cookieMap.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }
}
