import SwiftUI
import WebKit
import Observation

// MARK: - Cookie 获取 WebView

/// 通过内嵌 WKWebView 实现微博扫码登录并提取 Cookie。
/// 流程：加载微博 SSO 登录页 → 用户扫码 → 提取目标域 Cookie → 回调给设置界面。
struct CookieWebView: View {
    let dataSource: WeiboDataSource
    let onCookieObtained: (String) -> Void

    @State private var controller = CookieWebController()
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
                    controller.extract()
                }
                .buttonStyle(.borderedProminent)

                Button("取消") { dismiss() }
            }
            .padding()

            Divider()

            WebViewRepresentable(
                url: loginURL,
                controller: controller,
                onLoadingChanged: { isLoading = $0 }
            )
        }
        .onAppear {
            controller.dataSource = dataSource
            controller.onCookieObtained = onCookieObtained
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
    /// 设置已变更，通知 DownloadViewModel 重新配置（如 Cron 调度器）
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

// MARK: - WebView 控制器

/// 持有 WKWebView 弱引用并在用户点击「获取 Cookie」时提取目标域 Cookie。
@MainActor
@Observable
final class CookieWebController {
    weak var webView: WKWebView?
    var dataSource: WeiboDataSource = .weiboCnMobile
    var onCookieObtained: ((String) -> Void)?

    func extract() {
        guard let webView else { return }
        let source = dataSource
        Task { @MainActor in
            let cookie = await CookieExtractor.extract(from: webView, dataSource: source)
            if !cookie.isEmpty {
                onCookieObtained?(cookie)
            }
        }
    }
}

// MARK: - Cookie 提取逻辑

@MainActor
enum CookieExtractor {
    /// 从 WKWebView 的 Cookie 存储中提取目标域的所有 Cookie，拼接为 HTTP Header 格式
    static func extract(from webView: WKWebView, dataSource: WeiboDataSource) async -> String {
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

        var cookieMap: [String: HTTPCookie] = [:]
        let targetDomains = urls.compactMap { URL(string: $0)?.host }

        for cookie in allCookies {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            if targetDomains.contains(where: { $0.contains(domain) || domain.contains($0) }) {
                cookieMap[cookie.name] = cookie
            }
        }

        return cookieMap.values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

// MARK: - WKWebView 桥接

/// 使用 nonPersistent DataStore 确保每次打开都是全新会话（不受之前登录状态影响）
struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    let controller: CookieWebController
    let onLoadingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        controller.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadingChanged: onLoadingChanged)
    }

    /// WKNavigationDelegate 协调器，负责页面加载状态
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onLoadingChanged: (Bool) -> Void

        init(onLoadingChanged: @escaping (Bool) -> Void) {
            self.onLoadingChanged = onLoadingChanged
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadingChanged(false)
        }
    }
}
