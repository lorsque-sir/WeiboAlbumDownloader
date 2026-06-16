import Foundation

// MARK: - HTTP 网络客户端

/// 基于 URLSession 的 HTTP 客户端单例
/// 使用 actor 保证线程安全，替代 C# 版每次请求都 new HttpClient 的做法，
/// 复用底层 TCP 连接池，避免连接泄漏和端口耗尽
actor HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // 伪装浏览器 User-Agent，防止被微博接口拒绝
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Referer": "https://m.weibo.cn/",
        ]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
    }

    /// 请求 JSON API 并自动反序列化为指定 Codable 类型
    /// - Parameters:
    ///   - url: API 地址
    ///   - cookie: 微博登录凭证
    ///   - type: 期望的响应类型
    /// - Throws: `HTTPError.cookieExpired` 当检测到登录页面重定向时
    func fetchJSON<T: Decodable>(_ url: URL, cookie: String, type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }

        // 微博 Cookie 失效时不返回 401，而是 302 跳转到登录页
        if let body = String(data: data, encoding: .utf8),
           body.contains("<title>登录 - 微博</title>") {
            throw HTTPError.cookieExpired
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.statusCode(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    /// 请求 HTML 页面并返回字符串（用于 weiboCn 数据源的网页解析）
    func fetchHTML(_ url: URL, cookie: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.invalidResponse
        }

        if let body = String(data: data, encoding: .utf8),
           body.contains("<title>登录 - 微博</title>") {
            throw HTTPError.cookieExpired
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw HTTPError.decodingFailed
        }
        return html
    }

    /// 下载文件到指定路径（先下载到临时目录，完成后再移动，保证原子性）
    func downloadFile(_ url: URL, to destination: URL) async throws {
        let request = URLRequest(url: url)
        let (tempURL, response) = try await session.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.statusCode((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}

/// HTTP 请求错误类型
enum HTTPError: LocalizedError {
    case invalidResponse
    case statusCode(Int)
    case cookieExpired
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:     return "无效的服务器响应"
        case .statusCode(let c):   return "HTTP 错误: \(c)"
        case .cookieExpired:       return "Cookie 已失效，请重新扫码登录"
        case .decodingFailed:      return "数据解码失败"
        }
    }
}
