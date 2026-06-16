import Foundation

// MARK: - HTTP 网络客户端

/// 基于 URLSession 的 HTTP 客户端单例
/// URLSession 本身线程安全，无需 actor 串行化——直接用 final class 避免请求排队瓶颈
final class HTTPClient: Sendable {
    static let shared = HTTPClient()

    private let apiSession: URLSession
    private let downloadSession: URLSession

    private static let defaultHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Referer": "https://m.weibo.cn/",
    ]

    private init() {
        let apiConfig = URLSessionConfiguration.default
        apiConfig.httpAdditionalHeaders = Self.defaultHeaders
        apiConfig.timeoutIntervalForRequest = 30
        apiConfig.timeoutIntervalForResource = 120
        apiSession = URLSession(configuration: apiConfig)

        let dlConfig = URLSessionConfiguration.default
        dlConfig.httpAdditionalHeaders = Self.defaultHeaders
        dlConfig.timeoutIntervalForRequest = 60
        dlConfig.timeoutIntervalForResource = 300
        downloadSession = URLSession(configuration: dlConfig)
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

        let (data, response) = try await apiSession.data(for: request)

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

        let (data, response) = try await apiSession.data(for: request)

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

    /// 下载文件到指定路径，自动重试最多 3 次（指数退避: 2s, 4s, 8s）
    func downloadFile(_ url: URL, to destination: URL, maxRetries: Int = 3) async throws {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try await performDownload(url, to: destination)
                return
            } catch let error as HTTPError where error.isRetryable {
                lastError = error
            } catch let error as URLError {
                lastError = error
            } catch {
                throw error
            }

            if attempt < maxRetries {
                let delay = UInt64(pow(2.0, Double(attempt + 1)))
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        throw lastError ?? HTTPError.invalidResponse
    }

    private func performDownload(_ url: URL, to destination: URL) async throws {
        let request = URLRequest(url: url)
        let (tempURL, response) = try await downloadSession.download(for: request)

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

    /// 是否可重试（Cookie 过期和解码失败不应重试）
    var isRetryable: Bool {
        switch self {
        case .cookieExpired, .decodingFailed: return false
        case .invalidResponse: return true
        case .statusCode(let code): return code >= 500 || code == 429
        }
    }
}
