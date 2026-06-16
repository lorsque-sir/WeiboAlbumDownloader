import Foundation

// MARK: - m.weibo.cn API 响应模型
// 对应接口：https://m.weibo.cn/api/container/getIndex
// 这是推荐数据源，返回数据最全面（图片、视频、LivePhoto、picIds 等）

/// m.weibo.cn 容器接口顶层响应
struct WeiboCnMobileResponse: Codable {
    /// 1 表示成功
    let ok: Int?
    let data: MobileData?
}

/// 容器数据，包含分页信息和微博卡片列表
struct MobileData: Codable {
    let cardlistInfo: MobileCardlistInfo?
    let cards: [MobileCard]?

    enum CodingKeys: String, CodingKey {
        case cardlistInfo = "cardlistInfo"
        case cards
    }
}

/// 分页信息
struct MobileCardlistInfo: Codable {
    let containerid: String?
    let total: Int?
    /// 游标分页参数，下次请求时传入此值获取下一页
    let sinceId: Int64?

    enum CodingKeys: String, CodingKey {
        case containerid
        case total
        case sinceId = "since_id"
    }
}

/// 单张卡片（card_type=9 为微博内容卡片）
struct MobileCard: Codable {
    /// 9 表示微博正文卡片，其他值为广告/推荐等
    let cardType: Int?
    let profileTypeId: String?
    let mblog: MobileMblog?

    enum CodingKeys: String, CodingKey {
        case cardType = "card_type"
        case profileTypeId = "profile_type_id"
        case mblog
    }
}

/// 微博正文信息
struct MobileMblog: Codable {
    /// 发布时间，格式 "Tue Jun 04 12:34:56 +0800 2024"
    let createdAt: String?
    let id: String?
    let mid: String?
    /// 正文 HTML，包含 <a>/<span> 等标签
    let text: String?
    /// 图片 ID 列表，用于拼接大图 URL（当图片 > 9 张时此列表可能不完整）
    let picIds: [String]?
    /// 实际图片数量（与 picIds.count 不一致时说明有超 9 图）
    let picNum: Int?
    let user: MobileUser?
    /// 转发的原微博（非 nil 说明是转发微博，下载时通常跳过）
    let retweetedStatus: AnyCodable?
    /// 视频信息挂在此字段下
    let pageInfo: MobilePageInfo?
    let pics: AnyCodable?
    /// LivePhoto 的视频 URL 列表
    let livePhoto: [String]?
    let bid: String?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case id, mid, text
        case picIds = "pic_ids"
        case picNum = "pic_num"
        case user
        case retweetedStatus = "retweeted_status"
        case pageInfo = "page_info"
        case pics
        case livePhoto = "live_photo"
        case bid
    }
}

/// 微博用户信息
struct MobileUser: Codable {
    let id: Int64?
    let screenName: String?
    let profileImageUrl: String?
    /// 高清头像 URL，需进一步替换域名为 tvax2.sinaimg.cn/large 获取最大尺寸
    let avatarHd: String?
    let description: String?
    /// 粉丝数（API 返回的是字符串类型，可能包含"万"等后缀）
    let followersCount: String?
    let statusesCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case screenName = "screen_name"
        case profileImageUrl = "profile_image_url"
        case avatarHd = "avatar_hd"
        case description
        case followersCount = "followers_count"
        case statusesCount = "statuses_count"
    }
}

/// 视频/文章等附加内容信息
struct MobilePageInfo: Codable {
    let type: String?
    let pageUrl: String?
    let mediaInfo: MobileMediaInfo?
    /// 多清晰度视频 URL
    let urls: MobileVideoUrls?

    enum CodingKeys: String, CodingKey {
        case type
        case pageUrl = "page_url"
        case mediaInfo = "media_info"
        case urls
    }
}

struct MobileMediaInfo: Codable {
    let streamUrl: String?
    let streamUrlHd: String?
    let duration: String?

    enum CodingKeys: String, CodingKey {
        case streamUrl = "stream_url"
        case streamUrlHd = "stream_url_hd"
        case duration
    }
}

/// 多清晰度视频 URL，按质量从高到低排列
struct MobileVideoUrls: Codable {
    let mp4_8k_mp4: String?
    let mp4_4k_mp4: String?
    let mp4_2k_mp4: String?
    let mp4_1080p_mp4: String?
    let mp4_720p_mp4: String?
    let mp4_hd_mp4: String?
    let mp4_ld_mp4: String?

    /// 返回可用的最高画质 URL，优先级：8K > 4K > 2K > 1080P > 720P > HD > LD
    var bestQualityURL: String? {
        mp4_8k_mp4 ?? mp4_4k_mp4 ?? mp4_2k_mp4 ?? mp4_1080p_mp4 ?? mp4_720p_mp4 ?? mp4_hd_mp4 ?? mp4_ld_mp4
    }
}

/// 类型擦除的 Codable 包装器
/// 微博 API 中部分字段类型不固定（如 `pics` 可能是数组或 null，`retweeted_status` 可能是对象或 null），
/// 使用此包装器避免解码失败，仅用于判断字段是否存在
struct AnyCodable: Codable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }

    var isNotNil: Bool { value != nil }
}
