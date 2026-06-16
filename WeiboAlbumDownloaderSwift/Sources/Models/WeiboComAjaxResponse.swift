import Foundation

// MARK: - weibo.com Ajax 接口响应模型 (数据源 WeiboCom2)
// 此数据源通过 Ajax 接口获取相册照片，缺点是无法获取发布时间和正文信息
// 因此下载的文件无法按时间命名和修改时间戳，不推荐使用
// 对应接口：
//   - 相册列表: https://weibo.com/ajax/profile/getImageWall?uid=xxx&sinceid=0&has_album=true
//   - 照片详情: https://weibo.com/ajax/profile/getAlbumDetail?containerid=xxx&since_id=xxx

/// 相册列表接口响应
struct WeiboAjaxAlbumListResponse: Codable {
    let data: WeiboAjaxAlbumData?
    let ok: Int?
}

struct WeiboAjaxAlbumData: Codable {
    let albumList: [WeiboAjaxAlbumItem]?
    let albumSinceId: Int64?
    let sinceId: String?

    enum CodingKeys: String, CodingKey {
        case albumList = "album_list"
        case albumSinceId = "album_since_id"
        case sinceId = "since_id"
    }
}

/// 单个相册信息
struct WeiboAjaxAlbumItem: Codable {
    let picTitle: String?
    /// 相册的 containerid，作为获取详情的参数
    let containerid: String?
    let pic: String?

    enum CodingKeys: String, CodingKey {
        case picTitle = "pic_title"
        case containerid, pic
    }
}

/// 照片详情接口响应
struct WeiboAjaxPhotoListResponse: Codable {
    let data: WeiboAjaxPhotoData?
    let ok: Int?
}

struct WeiboAjaxPhotoData: Codable {
    let type: String?
    let list: [WeiboAjaxPhotoItem]?
    /// 游标分页参数，为 0 表示没有更多数据
    let sinceId: Int64?

    enum CodingKeys: String, CodingKey {
        case type, list
        case sinceId = "since_id"
    }
}

/// 单张照片信息（仅有 pid，无发布时间和正文）
struct WeiboAjaxPhotoItem: Codable {
    /// 图片 ID，用于拼接大图 URL
    let pid: String?
    let mid: String?
    let isPaid: Bool?
    let timelineMonth: String?
    let timelineYear: String?

    enum CodingKeys: String, CodingKey {
        case pid, mid
        case isPaid = "is_paid"
        case timelineMonth = "timeline_month"
        case timelineYear = "timeline_year"
    }
}
