import Foundation

// MARK: - weibo.cn 视频详情接口响应模型
// 对应接口：https://weibo.cn/s/video/object?object_id=xxx
// weiboCn 数据源通过 HTML 中的视频链接提取 object_id，再调用此接口获取视频流地址

/// 视频详情接口响应
struct WeiboVideoDetailResponse: Codable {
    let ok: Int?
    let data: WeiboVideoData?
}

struct WeiboVideoData: Codable {
    let objectId: String?
    let objectType: String?
    let object: WeiboVideoObject?

    enum CodingKeys: String, CodingKey {
        case objectId = "object_id"
        case objectType = "object_type"
        case object
    }
}

struct WeiboVideoObject: Codable {
    let summary: String?
    let stream: WeiboVideoStream?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case summary, stream
        case createdAt = "created_at"
    }
}

/// 视频流信息
struct WeiboVideoStream: Codable {
    let duration: Double?
    let format: String?
    let width: Int?
    let height: Int?
    /// 高清视频 URL（优先使用）
    let hdUrl: String?
    /// 标清视频 URL（备用）
    let url: String?

    enum CodingKeys: String, CodingKey {
        case duration, format, width, height
        case hdUrl = "hd_url"
        case url
    }
}

// MARK: - 微博状态详情接口响应模型（用于获取超 9 图的完整 pic_ids）
// 当 m.weibo.cn 返回的 pic_ids 数量与 pic_num 不一致时，
// 需要通过此接口获取完整的图片 ID 列表
// 对应接口：
//   - PC: https://weibo.com/ajax/statuses/show?id=xxx
//   - 移动: https://m.weibo.cn/statuses/show?id=xxx

/// 微博状态详情响应
struct WeiboStatusShowResponse: Codable {
    let ok: Int?
    let data: WeiboStatusData?
    let picIds: [String]?
    let pics: [WeiboStatusPic]?

    enum CodingKeys: String, CodingKey {
        case ok, data
        case picIds = "pic_ids"
        case pics
    }

    /// 合并 picIds 和 pics 中的 pid，去重后返回完整列表
    var allPicIds: [String] {
        if let data = data {
            return data.allPicIds
        }
        var result = Set<String>()
        if let ids = picIds { result.formUnion(ids) }
        if let p = pics { result.formUnion(p.compactMap(\.pid)) }
        return Array(result)
    }
}

struct WeiboStatusData: Codable {
    let picIds: [String]?
    let pics: [WeiboStatusPic]?

    enum CodingKeys: String, CodingKey {
        case picIds = "pic_ids"
        case pics
    }

    var allPicIds: [String] {
        var result = Set<String>()
        if let ids = picIds { result.formUnion(ids) }
        if let p = pics { result.formUnion(p.compactMap(\.pid)) }
        return Array(result)
    }
}

struct WeiboStatusPic: Codable {
    let pid: String?
    let url: String?
}
