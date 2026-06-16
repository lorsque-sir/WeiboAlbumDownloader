import Foundation

// MARK: - 微博数据源枚举

/// 微博提供 4 种不同的数据获取接口，各有优劣：
/// - weiboCnMobile: 推荐使用，数据最全（图片+视频+LivePhoto），支持按时间排序
/// - weiboCn: 仅原创微博，通过 HTML 解析获取，需要 SwiftSoup
/// - weiboCom1: 基于相册 API，按相册分类下载，不含视频
/// - weiboCom2: Ajax 接口，无法获取发布时间和正文，不推荐
enum WeiboDataSource: Int, Codable, CaseIterable, Identifiable {
    case weiboCnMobile = 0
    case weiboCn = 1
    case weiboCom1 = 2
    case weiboCom2 = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .weiboCnMobile: return "m.weibo.cn"
        case .weiboCn:       return "weibo.cn"
        case .weiboCom1:     return "weibo.com (相册)"
        case .weiboCom2:     return "weibo.com (Ajax)"
        }
    }

    var description: String {
        switch self {
        case .weiboCnMobile:
            return "获取用户时间流，推荐使用"
        case .weiboCn:
            return "获取用户时间流，仅原创微博"
        case .weiboCom1:
            return "获取相册信息（微博配图、头像、自拍等），不含视频"
        case .weiboCom2:
            return "Ajax 相册，无法重命名/改日期，不推荐"
        }
    }

    /// weiboCnMobile 和 weiboCn 使用 weibo.cn 域的 Cookie，
    /// weiboCom1 和 weiboCom2 使用 weibo.com 域的 Cookie
    var needsCnCookie: Bool {
        self == .weiboCnMobile || self == .weiboCn
    }
}

/// 媒体文件类型
enum MediaType: String, Codable {
    case image
    case video
    case livePhoto
}

/// 日志级别，对应 UI 中不同颜色显示
enum LogLevel: String, Codable {
    case info
    case success
    case warning
    case error
}
