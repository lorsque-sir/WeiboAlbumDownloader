import Foundation

// MARK: - m.weibo.cn 数据源（推荐）

/// m.weibo.cn 移动版 API 数据源
/// 接口地址：https://m.weibo.cn/api/container/getIndex
/// 特点：数据最全面，支持图片、视频、LivePhoto，按时间倒序排列
/// containerid 格式：107603 + UID（固定前缀）
struct WeiboCnMobileProvider: WeiboDataProvider {
    let sourceType = WeiboDataSource.weiboCnMobile
    private let http = HTTPClient.shared

    func fetchPage(
        uid: String, cookie: String, page: Int, sinceId: Int64, weiboComCookie: String?
    ) async throws -> FetchResult {
        let urlStr = "https://m.weibo.cn/api/container/getIndex?type=uid&value=\(uid)&containerid=107603\(uid)&since_id=\(sinceId)&page=\(page)"
        guard let url = URL(string: urlStr) else { throw HTTPError.invalidResponse }

        let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboCnMobileResponse.self)

        guard response.ok == 1,
              let data = response.data,
              let cards = data.cards, !cards.isEmpty else {
            return FetchResult(posts: [], nextPage: nil, nextSinceId: nil, user: nil, hasMore: false)
        }

        let nextSinceId = data.cardlistInfo?.sinceId ?? 0
        var user: WeiboUser?

        // 从最后一个有效卡片中提取用户信息
        if let lastCard = cards.last(where: { $0.mblog?.user != nil }),
           let u = lastCard.mblog?.user {
            user = WeiboUser(
                uid: uid,
                screenName: u.screenName ?? "",
                avatarURL: avatarLargeURL(u.avatarHd),
                description: u.description,
                followersCount: u.followersCount,
                statusesCount: u.statusesCount
            )
        }

        var posts: [WeiboPost] = []
        for card in cards {
            // card_type=9 为微博正文卡片，其他类型（广告、推荐等）跳过
            guard card.cardType == 9, let mblog = card.mblog else { continue }
            // 跳过转发微博（只下载原创内容）
            if mblog.retweetedStatus?.isNotNil == true { continue }

            guard let createdAt = mblog.createdAt, let date = parseMobileDate(createdAt) else { continue }

            var mediaItems: [MediaItem] = []
            var index = 1

            // 处理图片：当 picIds 数量与 picNum 不一致时，说明有超过 9 张图
            // 需要通过 WeiboMidHelper 调用状态详情接口获取完整 pic_ids
            if let picIds = mblog.picIds, !picIds.isEmpty {
                let ids: [String]
                if picIds.count == (mblog.picNum ?? picIds.count) {
                    ids = picIds
                } else if let comCookie = weiboComCookie {
                    ids = await WeiboMidHelper.getImageIds(mid: mblog.mid ?? "", cookie: comCookie)
                } else {
                    ids = picIds
                }

                // 使用 wx4.sinaimg.cn/large/ 前缀获取最大尺寸原图
                for picId in ids {
                    if let url = URL(string: "https://wx4.sinaimg.cn/large/\(picId).jpg") {
                        mediaItems.append(MediaItem(url: url, type: .image, index: index))
                        index += 1
                    }
                }
            }

            // 处理视频：从 page_info.urls 中选取最高画质
            if let videoURL = mblog.pageInfo?.urls?.bestQualityURL,
               let url = URL(string: videoURL) {
                mediaItems.append(MediaItem(url: url, type: .video, index: index))
                index += 1
            }

            // 处理 LivePhoto（iOS 实况照片的视频部分）
            if let livePhotos = mblog.livePhoto {
                for lp in livePhotos where !lp.isEmpty {
                    if let url = URL(string: lp) {
                        mediaItems.append(MediaItem(url: url, type: .livePhoto, index: index))
                        index += 1
                    }
                }
            }

            posts.append(WeiboPost(
                id: mblog.id ?? mblog.mid ?? UUID().uuidString,
                createdAt: date,
                text: mblog.text ?? "",
                mediaItems: mediaItems,
                isRetweet: false
            ))
        }

        return FetchResult(
            posts: posts,
            nextPage: page + 1,
            nextSinceId: nextSinceId,
            user: user,
            hasMore: !posts.isEmpty
        )
    }

    // MARK: - 日期解析

    private static let mobileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func parseMobileDate(_ string: String) -> Date? {
        Self.mobileDateFormatter.date(from: string)
    }

    /// 将 avatar_hd URL 转换为最大尺寸头像 URL
    /// 例：https://tvax2.sinaimg.cn/orj480/xxx.jpg → https://tvax2.sinaimg.cn/large/xxx.jpg
    private func avatarLargeURL(_ avatarHd: String?) -> URL? {
        guard let hd = avatarHd, let avatarURL = URL(string: hd) else { return nil }
        let filename = avatarURL.lastPathComponent.components(separatedBy: "?").first ?? avatarURL.lastPathComponent
        return URL(string: "https://tvax2.sinaimg.cn/large/\(filename)")
    }
}
