import Foundation

// MARK: - weibo.com Ajax 数据源（不推荐）

/// weibo.com Ajax 接口数据源
/// 此数据源的 API 不返回照片的发布时间和正文，因此：
/// - 无法按时间命名文件
/// - 无法修改文件时间戳
/// - 仅以 pid 作为文件名
/// 对应 C# 版 MainWindow.xaml.cs 中 case 3 的逻辑
struct WeiboComAjaxProvider: WeiboDataProvider {
    let sourceType = WeiboDataSource.weiboCom2
    private let http = HTTPClient.shared

    /// 此数据源不支持时间流模式
    func fetchPage(
        uid: String, cookie: String, page: Int, sinceId: Int64, weiboComCookie: String?
    ) async throws -> FetchResult {
        FetchResult(posts: [], nextPage: nil, nextSinceId: nil, user: nil, hasMore: false)
    }

    /// 获取用户相册列表（通过 Ajax 接口）
    func fetchAlbums(uid: String, cookie: String) async throws -> AlbumFetchResult {
        let urlStr = "https://weibo.com/ajax/profile/getImageWall?uid=\(uid)&sinceid=0&has_album=true"
        guard let url = URL(string: urlStr) else { throw HTTPError.invalidResponse }

        let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboAjaxAlbumListResponse.self)

        let albums = response.data?.albumList?.map { item in
            AlbumInfo(
                albumId: item.containerid ?? "",
                caption: item.picTitle ?? "",
                type: 0,
                coverPic: item.pic
            )
        } ?? []

        return AlbumFetchResult(albums: albums, user: nil)
    }

    /// 获取相册详情（使用 since_id 游标分页）
    func fetchAlbumPhotos(
        uid: String, cookie: String, album: AlbumInfo, page: Int, sinceId: Int64
    ) async throws -> FetchResult {
        let urlStr = "https://weibo.com/ajax/profile/getAlbumDetail?containerid=\(album.albumId)&since_id=\(sinceId)"
        guard let url = URL(string: urlStr) else { throw HTTPError.invalidResponse }

        let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboAjaxPhotoListResponse.self)

        guard let photoList = response.data?.list, !photoList.isEmpty else {
            return FetchResult(posts: [], nextPage: nil, nextSinceId: nil, user: nil, hasMore: false)
        }

        let nextSinceId = response.data?.sinceId ?? 0

        // 此数据源没有发布时间和正文信息，只能用 pid 作为标识
        var posts: [WeiboPost] = []
        for photo in photoList {
            guard let pid = photo.pid else { continue }
            let photoUrl = "https://wx4.sinaimg.cn/large/\(pid).jpg"
            if let url = URL(string: photoUrl) {
                posts.append(WeiboPost(
                    id: pid,
                    createdAt: Date(),
                    text: pid,
                    mediaItems: [MediaItem(url: url, type: .image, index: 1)],
                    isRetweet: false
                ))
            }
        }

        return FetchResult(
            posts: posts,
            nextPage: page + 1,
            nextSinceId: nextSinceId,
            user: nil,
            hasMore: nextSinceId > 0
        )
    }
}
