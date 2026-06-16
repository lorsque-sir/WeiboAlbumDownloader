import Foundation

// MARK: - photo.weibo.com 相册数据源

/// photo.weibo.com 相册 API 数据源
/// 此数据源按相册分类获取照片（微博配图、头像相册、自拍等），不含视频
/// 下载流程：先获取相册列表 → 再逐个相册分页获取照片
/// 对应 C# 版 MainWindow.xaml.cs 中 case 2 的逻辑
struct WeiboComAlbumProvider: WeiboDataProvider {
    let sourceType = WeiboDataSource.weiboCom1
    private let http = HTTPClient.shared

    /// 此数据源不支持时间流模式，fetchPage 返回空结果
    func fetchPage(
        uid: String, cookie: String, page: Int, sinceId: Int64, weiboComCookie: String?
    ) async throws -> FetchResult {
        FetchResult(posts: [], nextPage: nil, nextSinceId: nil, user: nil, hasMore: false)
    }

    /// 获取用户的所有相册列表
    func fetchAlbums(uid: String, cookie: String) async throws -> AlbumFetchResult {
        let urlStr = "https://photo.weibo.com/albums/get_all?uid=\(uid)&page=1"
        guard let url = URL(string: urlStr) else { throw HTTPError.invalidResponse }

        let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboComAlbumListResponse.self)

        let albums = response.data?.albumList?.map { item in
            AlbumInfo(
                albumId: item.albumId ?? "",
                caption: item.caption ?? "",
                type: item.type ?? 0,
                coverPic: item.coverPic
            )
        } ?? []

        return AlbumFetchResult(albums: albums, user: nil)
    }

    /// 分页获取指定相册内的照片
    func fetchAlbumPhotos(
        uid: String, cookie: String, album: AlbumInfo, page: Int, sinceId: Int64
    ) async throws -> FetchResult {
        // count=90 为单页最大数量
        let urlStr = "https://photo.weibo.com/photos/get_all?uid=\(uid)&album_id=\(album.albumId)&count=90&page=\(page)&type=\(album.type)"
        guard let url = URL(string: urlStr) else { throw HTTPError.invalidResponse }

        let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboComPhotoListResponse.self)

        guard let photoList = response.data?.photoList, !photoList.isEmpty else {
            return FetchResult(posts: [], nextPage: nil, nextSinceId: nil, user: nil, hasMore: false)
        }

        // 按 timestamp + caption 分组，将同一条微博的多张图片合并为一个 WeiboPost
        var postMap: [String: (date: Date, caption: String, items: [MediaItem])] = [:]
        var orderKeys: [String] = []

        for photo in photoList {
            let caption = photo.captionRender ?? photo.caption ?? ""
            let timestamp = photo.timestamp ?? 0
            // API 返回的时间戳需要 +8h 转北京时间
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp + 8 * 3600))
            let photoUrl = "\(photo.picHost ?? "https://wx4.sinaimg.cn")/large/\(photo.picName ?? "")"

            let key = "\(timestamp)_\(caption)"
            if postMap[key] == nil {
                postMap[key] = (date: date, caption: caption, items: [])
                orderKeys.append(key)
            }
            let index = (postMap[key]?.items.count ?? 0) + 1
            if let url = URL(string: photoUrl) {
                postMap[key]?.items.append(MediaItem(url: url, type: .image, index: index))
            }
        }

        let posts = orderKeys.compactMap { key -> WeiboPost? in
            guard let entry = postMap[key] else { return nil }
            return WeiboPost(
                id: key,
                createdAt: entry.date,
                text: entry.caption,
                mediaItems: entry.items,
                isRetweet: false
            )
        }

        return FetchResult(
            posts: posts,
            nextPage: page + 1,
            nextSinceId: nil,
            user: nil,
            hasMore: !photoList.isEmpty
        )
    }
}
