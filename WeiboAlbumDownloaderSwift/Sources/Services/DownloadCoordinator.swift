import Foundation

// MARK: - 下载编排器

/// 统一的下载编排器，协调数据获取和文件下载的完整流程
/// 核心改进点（相比 C# 版 MainWindow.xaml.cs 的 1420 行代码）：
/// 1. 通过 WeiboDataProvider 协议消除 4 种数据源的代码重复
/// 2. 使用 TaskGroup 实现同一条微博内多张图片的并发下载
/// 3. 使用 actor 保证并发安全，无需手动锁
/// 4. 通过 Task.isCancelled 实现优雅取消
actor DownloadCoordinator {
    private let provider: WeiboDataProvider
    private let downloadService: DownloadService
    private let fileService: FileService
    private let settings: AppSettings

    typealias LogHandler = @Sendable (String, LogLevel) -> Void
    typealias UserInfoHandler = @Sendable (WeiboUser) -> Void
    /// 单文件下载结果回调（completed/skipped/failed），用于 UI 进度统计
    enum DownloadEvent: Sendable {
        case completed(fileName: String)
        case skipped(fileName: String)
        case failed(url: URL, fileName: String, error: String)
        case pageLoaded(page: Int)
    }
    typealias ProgressHandler = @Sendable (DownloadEvent) -> Void

    init(settings: AppSettings) {
        self.settings = settings
        self.provider = createProvider(for: settings.dataSource)
        self.fileService = FileService()
        self.downloadService = DownloadService(fileService: fileService)
    }

    /// 下载单个用户的全部媒体内容
    /// 根据数据源类型自动选择时间流模式或相册模式
    func downloadUser(
        uid: String,
        log: LogHandler,
        onUserInfo: UserInfoHandler,
        onProgress: ProgressHandler? = nil
    ) async throws {
        let cookie = settings.activeCookie ?? ""
        guard !cookie.isEmpty else {
            log("没有检测到 Cookie，请在设置中扫码获取", .error)
            throw DownloadError.noCookie
        }

        guard Int64(uid) != nil else {
            log("错误的微博 UID: \(uid)", .error)
            throw DownloadError.invalidUID(uid)
        }

        log("开始下载 \(uid)", .info)
        let progress = onProgress ?? { _ in }

        switch settings.dataSource {
        case .weiboCnMobile, .weiboCn:
            try await downloadTimeline(uid: uid, cookie: cookie, log: log, onUserInfo: onUserInfo, onProgress: progress)
        case .weiboCom1, .weiboCom2:
            try await downloadAlbums(uid: uid, cookie: cookie, log: log, onUserInfo: onUserInfo, onProgress: progress)
        }
    }

    // MARK: - 时间流模式（WeiboCnMobile / WeiboCn）

    /// 按时间线翻页下载，适用于 m.weibo.cn 和 weibo.cn 数据源
    private func downloadTimeline(
        uid: String, cookie: String, log: LogHandler, onUserInfo: UserInfoHandler, onProgress: ProgressHandler
    ) async throws {
        var page = 1
        var sinceId: Int64 = 0
        var skipCount = 0
        var userDir = fileService.userDirectory(uid: uid, nickname: nil)
        var didSetUserInfo = false

        while !Task.isCancelled {
            let result = try await provider.fetchPage(
                uid: uid, cookie: cookie, page: page, sinceId: sinceId,
                weiboComCookie: CookieService.loadComCookie()
            )

            guard result.hasMore, !result.posts.isEmpty else {
                log("没有更多数据了", .info)
                break
            }

            if let nextSinceId = result.nextSinceId, nextSinceId > 0 {
                sinceId = nextSinceId
            }

            log("正在下载第 \(page) 页，获取到 \(result.posts.count) 条微博", .info)
            onProgress(.pageLoaded(page: page))

            if !didSetUserInfo, let user = result.user {
                onUserInfo(user)
                userDir = fileService.userDirectory(uid: uid, nickname: user.screenName)
                fileService.createNicknameMarker(in: userDir, nickname: user.screenName)

                if settings.showHeadImage, let avatarURL = user.avatarURL {
                    let _ = await downloadService.downloadAvatar(url: avatarURL, to: userDir)
                }
                didSetUserInfo = true
            }

            for post in result.posts {
                if Task.isCancelled {
                    log("用户手动终止，Page: \(page), SinceId: \(sinceId)", .info)
                    return
                }

                if settings.enableDatetimeRange, let startDate = settings.startDateTime {
                    if post.createdAt < startDate {
                        log("翻页到截至日期 \(startDate)，停止下载", .info)
                        return
                    }
                }

                guard !post.mediaItems.isEmpty else { continue }

                let results = await downloadMediaConcurrently(
                    items: post.mediaItems, post: post, directory: userDir
                )

                for r in results {
                    let name = r.destination.lastPathComponent
                    if r.skipped {
                        skipCount += 1
                        log("文件已存在，跳过: \(name)", .warning)
                        onProgress(.skipped(fileName: name))
                    } else if let error = r.error {
                        log("下载失败: \(r.url) - \(error.localizedDescription)", .error)
                        onProgress(.failed(url: r.url, fileName: name, error: error.localizedDescription))
                    } else {
                        log("已完成: \(name)", .success)
                        onProgress(.completed(fileName: name))
                    }
                }

                if settings.countDownloadedSkipToNextUser > 0,
                   skipCount > settings.countDownloadedSkipToNextUser {
                    log("已存在 \(skipCount) 个文件超过阈值 \(settings.countDownloadedSkipToNextUser)，跳到下一用户", .info)
                    return
                }
            }

            page = result.nextPage ?? (page + 1)

            // 反爬延迟：5~10 秒随机间隔，模拟人工操作
            let delay = Int.random(in: 5000...10000)
            log("随机等待 \(delay)ms，避免被限流", .info)
            try await Task.sleep(for: .milliseconds(delay))
        }
    }

    // MARK: - 相册模式（WeiboCom1 / WeiboCom2）

    /// 按相册逐个下载，适用于 photo.weibo.com 和 weibo.com Ajax 数据源
    private func downloadAlbums(
        uid: String, cookie: String, log: LogHandler, onUserInfo: UserInfoHandler, onProgress: ProgressHandler
    ) async throws {
        let albumResult = try await provider.fetchAlbums(uid: uid, cookie: cookie)

        guard !albumResult.albums.isEmpty else {
            log("没有获取到相册数据", .warning)
            return
        }

        if let user = albumResult.user {
            onUserInfo(user)
        }

        let userDir = fileService.userDirectory(uid: uid, nickname: nil)
        var skipCount = 0

        // 从头像相册中获取头像
        if let avatarAlbum = albumResult.albums.first(where: { $0.caption == "头像相册" }),
           let coverPic = avatarAlbum.coverPic, let url = URL(string: coverPic) {
            let _ = await downloadService.downloadAvatar(url: url, to: userDir)
        }

        for album in albumResult.albums {
            if Task.isCancelled { break }

            let albumDir = fileService.albumSubdirectory(userDir: userDir, albumName: album.caption)
            log("开始下载相册: \(album.caption)", .info)

            var page = 1
            var sinceId: Int64 = 0
            var consecutiveEmpty = 0

            while !Task.isCancelled {
                let result = try await provider.fetchAlbumPhotos(
                    uid: uid, cookie: cookie, album: album, page: page, sinceId: sinceId
                )

                // 连续 3 次空页面视为相册已遍历完毕
                if result.posts.isEmpty {
                    consecutiveEmpty += 1
                    if consecutiveEmpty >= 3 {
                        log("连续 3 次空页面，停止当前相册", .info)
                        break
                    }
                    page += 1
                    continue
                }

                consecutiveEmpty = 0

                if let nextSinceId = result.nextSinceId, nextSinceId > 0 {
                    sinceId = nextSinceId
                }

                for post in result.posts {
                    if Task.isCancelled { break }

                    // 仅"微博配图"相册应用时间范围过滤
                    if settings.enableDatetimeRange, let startDate = settings.startDateTime,
                       album.caption == "微博配图", post.createdAt < startDate {
                        log("翻页到截至日期，停止下载", .info)
                        return
                    }

                    let results = await downloadMediaConcurrently(
                        items: post.mediaItems, post: post, directory: albumDir
                    )

                    for r in results {
                        let name = r.destination.lastPathComponent
                        if r.skipped {
                            skipCount += 1
                            log("文件已存在，跳过: \(name)", .warning)
                            onProgress(.skipped(fileName: name))
                        } else if let error = r.error {
                            log("下载失败: \(error.localizedDescription)", .error)
                            onProgress(.failed(url: r.url, fileName: name, error: error.localizedDescription))
                        } else {
                            log("已完成: \(name)", .success)
                            onProgress(.completed(fileName: name))
                        }
                    }

                    if settings.countDownloadedSkipToNextUser > 0,
                       skipCount > settings.countDownloadedSkipToNextUser {
                        log("已存在文件超过阈值，跳到下一用户", .info)
                        return
                    }
                }

                guard result.hasMore else { break }
                page = result.nextPage ?? (page + 1)

                let delay = Int.random(in: 5000...10000)
                log("随机等待 \(delay)ms", .info)
                try await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    // MARK: - 并发下载（改进 C# 版的串行下载）

    /// 使用 TaskGroup 并发下载同一条微博的多个媒体文件
    /// 通过 maxConcurrentDownloads 控制并发上限，避免触发限流
    private func downloadMediaConcurrently(
        items: [MediaItem], post: WeiboPost, directory: URL
    ) async -> [DownloadService.DownloadResult] {
        let filtered = items.filter { item in
            switch item.type {
            case .video:     return settings.enableDownloadVideo
            case .livePhoto: return settings.enableDownloadLivePhoto
            case .image:     return true
            }
        }

        let setTimestamp = settings.dataSource != .weiboCom2
        let shortenName = settings.enableShortenName
        let maxConcurrent = settings.maxConcurrentDownloads
        let svc = downloadService

        return await withTaskGroup(of: DownloadService.DownloadResult.self, returning: [DownloadService.DownloadResult].self) { group in
            var results: [DownloadService.DownloadResult] = []
            var running = 0

            for item in filtered {
                if running >= maxConcurrent {
                    if let result = await group.next() {
                        results.append(result)
                        running -= 1
                    }
                }

                group.addTask {
                    await svc.downloadMedia(
                        item: item, post: post, directory: directory,
                        shortenName: shortenName,
                        setTimestamp: setTimestamp
                    )
                }
                running += 1
            }

            for await result in group {
                results.append(result)
            }

            return results
        }
    }
}

// MARK: - 下载错误

enum DownloadError: LocalizedError {
    case noCookie
    case invalidUID(String)

    var errorDescription: String? {
        switch self {
        case .noCookie:
            return "没有检测到 Cookie，请在设置中扫码获取"
        case .invalidUID(let uid):
            return "错误的微博 UID: \(uid)"
        }
    }
}
