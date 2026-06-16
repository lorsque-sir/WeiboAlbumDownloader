import Foundation

// MARK: - 统一数据模型

/// 微博用户信息（从不同数据源 API 解析后统一存放）
struct WeiboUser: Sendable {
    let uid: String
    var screenName: String
    var avatarURL: URL?
    var description: String?
    var followersCount: String?
    var statusesCount: Int?
}

/// 统一的微博帖子模型，4 种数据源解析后都转换为此结构
struct WeiboPost: Sendable {
    let id: String
    let createdAt: Date
    let text: String
    var mediaItems: [MediaItem]
    let isRetweet: Bool

    /// 清洗微博正文用于文件命名：移除 HTML 标签、非法文件名字符，截断至 80 字符
    var cleanText: String {
        var result = text
            .replacingOccurrences(of: "<a.*?>.*?</a>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<span.*?>.*?</span>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<.*?>", with: "", options: .regularExpression)
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        result = result.components(separatedBy: invalidChars).joined()
        if result.count > 80 {
            result = String(result.prefix(80))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 统一的媒体项模型（图片/视频/LivePhoto）
struct MediaItem: Sendable {
    let url: URL
    let type: MediaType
    /// 同一条微博内的序号，从 1 开始
    let index: Int

    /// 生成下载文件名，格式：`2024-06-01 14_30_00微博正文_1.jpg`
    /// shortenName 为 true 时省略微博正文部分
    func fileName(post: WeiboPost, shortenName: Bool) -> String {
        let dateStr = Self.dateFormatter.string(from: post.createdAt)
        let caption = shortenName ? "" : post.cleanText
        let ext: String
        switch type {
        case .image:     ext = "jpg"
        case .video:     ext = "mp4"
        case .livePhoto: ext = "mov"
        }
        return "\(dateStr)\(caption)_\(index).\(ext)"
    }

    /// 使用 en_US_POSIX 确保日期格式不受系统语言设置影响
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH_mm_ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// 相册信息（仅 weiboCom1/weiboCom2 数据源使用，如"微博配图"、"头像相册"等）
struct AlbumInfo: Sendable {
    let albumId: String
    let caption: String
    let type: Int
    let coverPic: String?
}

/// 单页数据获取结果（所有 Provider 的统一返回类型）
struct FetchResult: Sendable {
    let posts: [WeiboPost]
    /// 下一页页码（仅基于页码分页的数据源使用）
    let nextPage: Int?
    /// 游标分页参数（m.weibo.cn 使用 since_id 而非页码分页）
    let nextSinceId: Int64?
    let user: WeiboUser?
    let hasMore: Bool
}

/// 相册列表获取结果
struct AlbumFetchResult: Sendable {
    let albums: [AlbumInfo]
    let user: WeiboUser?
}
