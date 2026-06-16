import Foundation

// MARK: - photo.weibo.com 相册接口响应模型 (数据源 WeiboCom1)
// 此数据源按相册分类获取图片（微博配图、头像相册、自拍等），不含视频
// 对应接口：
//   - 相册列表: https://photo.weibo.com/albums/get_all?uid=xxx&page=1
//   - 照片列表: https://photo.weibo.com/photos/get_all?uid=xxx&album_id=xxx&count=90&page=xxx

/// 相册列表接口响应
struct WeiboComAlbumListResponse: Codable {
    let result: String?
    let code: Int?
    let msg: String?
    let data: WeiboComAlbumData?
}

struct WeiboComAlbumData: Codable {
    let total: Int?
    let albumList: [WeiboComAlbumItem]?

    enum CodingKeys: String, CodingKey {
        case total
        case albumList = "album_list"
    }
}

/// 单个相册信息
struct WeiboComAlbumItem: Codable {
    let albumId: String?
    let uid: String?
    /// 相册类型（不同 type 对应不同的获取逻辑）
    let type: Int?
    /// 相册名称，如"微博配图"、"头像相册"
    let caption: String?
    let coverPic: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case albumId = "album_id"
        case uid, type, caption
        case coverPic = "cover_pic"
        case description
    }
}

/// 照片列表接口响应
struct WeiboComPhotoListResponse: Codable {
    let result: String?
    let code: Int?
    let data: WeiboComPhotoListData?
}

struct WeiboComPhotoListData: Codable {
    let albumId: String?
    let total: Int?
    let photoList: [WeiboComPhotoItem]?

    enum CodingKeys: String, CodingKey {
        case albumId = "album_id"
        case total
        case photoList = "photo_list"
    }
}

/// 单张照片信息
struct WeiboComPhotoItem: Codable {
    let photoId: String?
    /// 图片 CDN 主机（如 https://wx4.sinaimg.cn）
    let picHost: String?
    /// 图片文件名（与 picHost 拼接为完整 URL）
    let picName: String?
    let picPid: String?
    /// 照片描述
    let caption: String?
    /// 渲染后的描述（可能包含 HTML 实体转义）
    let captionRender: String?
    /// Unix 时间戳（注意：API 返回的是 UTC 时间，需 +8h 转北京时间）
    let timestamp: Int?
    let uid: Int64?

    enum CodingKeys: String, CodingKey {
        case photoId = "photo_id"
        case picHost = "pic_host"
        case picName = "pic_name"
        case picPid = "pic_pid"
        case caption
        case captionRender = "caption_render"
        case timestamp, uid
    }
}
