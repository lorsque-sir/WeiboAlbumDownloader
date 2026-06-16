import Foundation
import SwiftSoup

// MARK: - weibo.cn HTML 解析数据源

/// weibo.cn 精简版网页数据源
/// 通过解析 HTML 获取微博内容（filter=1 仅获取原创微博），使用 SwiftSoup 解析
/// 特点：仅原创微博，支持组图和视频
/// 对应 C# 版 MainWindow.xaml.cs 中 case 1 的逻辑
struct WeiboCnHtmlProvider: WeiboDataProvider {
    let sourceType = WeiboDataSource.weiboCn
    private let http = HTTPClient.shared

    func fetchPage(
        uid: String, cookie: String, page: Int, sinceId: Int64, weiboComCookie: String?
    ) async throws -> FetchResult {
        // filter=1 表示仅原创微博
        let urlStr = "https://weibo.cn/\(uid)/profile?page=\(page)&filter=1"
        guard let url = URL(string: urlStr) else { throw HTTPError.invalidResponse }

        let html = try await http.fetchHTML(url, cookie: cookie)
        let doc = try SwiftSoup.parse(html)

        // 从隐藏 input 中提取总页数
        let hiddenInputs = try doc.select("input[type=hidden]")
        var totalPages: Int?
        if let last = hiddenInputs.last(), let val = try? last.attr("value"), let tp = Int(val) {
            totalPages = tp
        }

        // 从页面头部解析用户信息
        var user: WeiboUser?
        if let userDiv = try doc.select("div.u").first() {
            let avatarSrc = try userDiv.select("img[alt=头像]").first()?.attr("src") ?? ""
            let nickName = try userDiv.select("span.ctt").first()?.text().components(separatedBy: " ").first ?? ""
            let filename = URL(string: avatarSrc)?.lastPathComponent.components(separatedBy: "?").first ?? ""
            let avatarURL = filename.isEmpty ? nil : URL(string: "https://tvax2.sinaimg.cn/large/\(filename)")

            user = WeiboUser(uid: uid, screenName: nickName, avatarURL: avatarURL)
        }

        // 解析每条微博内容（div.c 为微博容器）
        let nodes = try doc.select("div.c")
        var posts: [WeiboPost] = []

        for node in nodes.array() {
            let outerHtml = try node.outerHtml()

            // 跳过页面底部的设置/隐私链接区域
            if outerHtml.contains("设置") && outerHtml.contains("隐私") { continue }

            let innerDoc = try SwiftSoup.parse(outerHtml)

            // 微博正文在 span.ctt 中
            let content = try innerDoc.select("span.ctt").first()?.text() ?? ""

            // 发布时间在 span.ct 中
            let timeText = try innerDoc.select("span.ct").first()?.text() ?? ""
            guard let timestamp = parseWeiboCnTime(timeText) else { continue }

            var mediaItems: [MediaItem] = []
            var index = 1
            let links = try innerDoc.select("a")

            var isGroupPic = false
            var groupPicURL: String?
            var isVideo = false
            var videoObjectURL: String?

            // 遍历链接，识别媒体类型
            for link in links.array() {
                let text = try link.text()
                let href = try link.attr("href")

                if text.contains("组图共") {
                    // 组图需要额外请求图片页面
                    isGroupPic = true
                    groupPicURL = href
                } else if href.contains("s/video/show") {
                    // 视频需要将 show 替换为 object 获取视频流地址
                    isVideo = true
                    videoObjectURL = href.replacingOccurrences(of: "s/video/show", with: "s/video/object")
                } else if text.contains("原图") {
                    // 单张原图，URL 参数 u= 后面是图片 ID
                    if let picId = href.components(separatedBy: "u=").last {
                        if let url = URL(string: "https://wx4.sinaimg.cn/large/\(picId).jpg") {
                            mediaItems.append(MediaItem(url: url, type: .image, index: index))
                            index += 1
                        }
                    }
                }
            }

            // 处理组图：请求组图页面，从 img 标签提取所有图片
            if isGroupPic, let groupURL = groupPicURL, let gurl = URL(string: groupURL) {
                let picPageHTML = try await http.fetchHTML(gurl, cookie: cookie)
                let picDoc = try SwiftSoup.parse(picPageHTML)
                let imgs = try picDoc.select("img")
                for img in imgs.array() {
                    let src = try img.attr("src")
                    let filename = URL(string: src)?.lastPathComponent ?? ""
                    if !filename.isEmpty, let url = URL(string: "https://wx4.sinaimg.cn/large/\(filename)") {
                        mediaItems.append(MediaItem(url: url, type: .image, index: index))
                        index += 1
                    }
                }
            }

            // 处理视频：调用 video/object 接口获取视频流 URL
            if isVideo, let videoURL = videoObjectURL, let vurl = URL(string: videoURL) {
                do {
                    let videoResp = try await http.fetchJSON(vurl, cookie: cookie, type: WeiboVideoDetailResponse.self)
                    if videoResp.ok == 1,
                       let hdUrl = videoResp.data?.object?.stream?.hdUrl ?? videoResp.data?.object?.stream?.url,
                       let url = URL(string: hdUrl) {
                        mediaItems.append(MediaItem(url: url, type: .video, index: index))
                        index += 1
                    }
                } catch {
                    // 视频解析失败时静默跳过，不中断整体下载
                }
            }

            if !mediaItems.isEmpty || !content.isEmpty {
                posts.append(WeiboPost(
                    id: UUID().uuidString,
                    createdAt: timestamp,
                    text: content,
                    mediaItems: mediaItems,
                    isRetweet: false
                ))
            }
        }

        let hasMore: Bool
        if let tp = totalPages {
            hasMore = page < tp
        } else {
            hasMore = !posts.isEmpty
        }

        return FetchResult(
            posts: posts,
            nextPage: page + 1,
            nextSinceId: nil,
            user: user,
            hasMore: hasMore
        )
    }

    // MARK: - 缓存的 DateFormatter

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateTimeFormatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "MM月dd日 HH:mm"].map { format in
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    private func parseWeiboCnTime(_ text: String) -> Date? {
        let parts = text.components(separatedBy: " ")
        guard !parts.isEmpty else { return nil }

        let timePart = parts[0]

        if timePart.contains("分钟前") {
            let minuteStr = timePart.replacingOccurrences(of: "分钟前", with: "")
            if let minutes = Int(minuteStr) {
                return Date().addingTimeInterval(TimeInterval(-minutes * 60))
            }
        }

        if timePart.contains("今天") {
            let timeStr = timePart.replacingOccurrences(of: "今天", with: "")
            if let time = Self.timeOnlyFormatter.date(from: timeStr) {
                let calendar = Calendar.current
                let now = Date()
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                return calendar.date(from: components)
            }
        }

        for formatter in Self.dateTimeFormatters {
            if let date = formatter.date(from: timePart) { return date }
        }

        return Date()
    }
}
