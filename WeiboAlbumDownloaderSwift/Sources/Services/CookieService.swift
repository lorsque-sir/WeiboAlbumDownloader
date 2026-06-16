import Foundation
import KeychainAccess

// MARK: - Cookie 安全存储服务

/// 使用 macOS Keychain 安全存储微博 Cookie
/// 替代 C# 版将 Cookie 明文保存在 Settings.json 中的做法，
/// Keychain 数据经系统级加密，其他应用无法读取
enum CookieService {
    private static let keychain = Keychain(service: "com.weiboalbum.downloader")

    /// 保存 weibo.cn / m.weibo.cn Cookie
    static func saveCnCookie(_ cookie: String) {
        keychain["weiboCnCookie"] = cookie
    }

    /// 保存 weibo.com Cookie
    static func saveComCookie(_ cookie: String) {
        keychain["weiboComCookie"] = cookie
    }

    static func loadCnCookie() -> String? {
        keychain["weiboCnCookie"]
    }

    static func loadComCookie() -> String? {
        keychain["weiboComCookie"]
    }

    /// 清除所有存储的 Cookie
    static func clearAll() {
        try? keychain.removeAll()
    }
}
