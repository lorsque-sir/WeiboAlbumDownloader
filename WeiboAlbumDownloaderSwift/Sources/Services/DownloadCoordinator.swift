import Foundation

// MARK: - 下载编排器

/// 统一的下载编排器，协调数据获取和文件下载的完整流程。
/// - 通过 WeiboDataProvider 协议消除 4 种数据源的代码重复
/// - 使用 TaskGroup 滑动窗口实现同一条微博内多张图片的并发下载
/// - 使用 actor 保证并发安全，并在 actor 内维护目录文件缓存以消除逐文件 syscall
/// - 通过 Task.isCancelled 实现优雅取消，通过 checkpoint 支持断点续传
actor DownloadCoordinator {
    private let provider: WeiboDataProvider
    private let downloadService: DownloadService
    private let fileService: FileService
    private let settings: AppSettings

    /// 目录已存在文件名缓存：key 为目录 path，避免对每个文件单独调用 fileExists
    private var dirCache: [String: Set<String>] = [:]

    typealias LogHandler = @Sendable (String, LogLevel) -> Void
    typealias UserInfoHandler = @Sendable (WeiboUser) -> Void

    /// 下载过程事件回调，用于 UI 进度统计与断点保存
    enum DownloadEvent: Sendable {
        case completed(fileName: String, bytes: Int64)
        case skipped(fileName: String)
        case failed(url: URL, fileName: String, error: String)
        case pageLoaded(page: Int)
        /// 翻页后的断点：下一页页码与游标
        case checkpoint(page: Int, sinceId: Int64)
    }
    typealias ProgressHandler = @Sendable (DownloadEvent) -> Void

    init(settings: AppSettings) {
        self.settings = settings
        self.provider = createProvider(for: settings.dataSource)
        self.fileService = FileService()
        self.downloadService = DownloadService(fileService: fileService)
    }

    /// 下载单个用户的全部媒体内容
    /// - Parameter resumeFrom: 断点状态，非空时从中断处继续（仅时间流模式）
    func downloadUser(
        uid: String,
        log: LogHandler,
        onUserInfo: UserInfoHandler,
        onProgress: ProgressHandler? = nil,
        resumeFrom: DownloadResumeState? = nil
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

        let progress = onProgress ?? { _ in }

        switch settings.dataSource {
        case .weiboCnMobile, .weiboCn:
            if let resume = resumeFrom, resume.uid == uid {
                log("从断点继续：第 \(resume.page) 页", .info)
            } else {
                log("开始下载 \(uid)", .info)
            }
            try await downloadTimeline(
                uid: uid, cookie: cookie, log: log, onUserInfo: onUserInfo, onProgress: progress,
                startPage: resumeFrom?.page ?? 1, startSinceId: resumeFrom?.sinceId ?? 0
            )
        case .weiboCom1, .weiboCom2:
            log("开始下载 \(uid)", .info)
            try await downloadAlbums(uid: uid, cookie: cookie, log: log, onUserInfo: onUserInfo, onProgress: progress)
        }
    }

    // MARK: - 时间流模式（WeiboCnMobile / WeiboCn）

    private func downloadTimeline(
        uid: String, cookie: String, log: LogHandler, onUserInfo: UserInfoHandler,
        onProgress: ProgressHandler, startPage: Int, startSinceId: Int64
    ) async throws {
        var page = startPage
        var sinceId = startSinceId
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
                    _ = await downloadService.downloadAvatar(url: avatarURL, to: userDir)
                }
                didSetUserInfo = true
            }

            for post in result.posts {
                if Task.isCancelled {
                    log("用户手动终止，Page: \(page), SinceId: \(sinceId)", .info)
                    return
                }

                if settings.enableDatetimeRange, let startDate = settings.startDateTime,
                   post.createdAt < startDate {
                    log("翻页到截至日期 \(startDate)，停止下载", .info)
                    return
                }

                guard !post.mediaItems.isEmpty else { continue }

                let results = await downloadMediaConcurrently(
                    items: post.mediaItems, post: post, directory: userDir
                )
                emit(results, log: log, onProgress: onProgress, skipCount: &skipCount)

                if settings.countDownloadedSkipToNextUser > 0,
                   skipCount > settings.countDownloadedSkipToNextUser {
                    log("已存在 \(skipCount) 个文件超过阈值 \(settings.countDownloadedSkipToNextUser)，跳到下一用户", .info)
                    return
                }
            }

            page = result.nextPage ?? (page + 1)
            onProgress(.checkpoint(page: page, sinceId: sinceId))

            let delay = Int.random(in: settings.antiCrawlDelayRange)
            log("随机等待 \(delay)ms，避免被限流", .info)
            try await Task.sleep(for: .milliseconds(delay))
        }
    }

    // MARK: - 相册模式（WeiboCom1 / WeiboCom2）

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

        if let avatarAlbum = albumResult.albums.first(where: { $0.caption == "头像相册" }),
           let coverPic = avatarAlbum.coverPic, let url = URL(string: coverPic) {
            _ = await downloadService.downloadAvatar(url: url, to: userDir)
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

                    if settings.enableDatetimeRange, let startDate = settings.startDateTime,
                       album.caption == "微博配图", post.createdAt < startDate {
                        log("翻页到截至日期，停止下载", .info)
                        return
                    }

                    let results = await downloadMediaConcurrently(
                        items: post.mediaItems, post: post, directory: albumDir
                    )
                    emit(results, log: log, onProgress: onProgress, skipCount: &skipCount)

                    if settings.countDownloadedSkipToNextUser > 0,
                       skipCount > settings.countDownloadedSkipToNextUser {
                        log("已存在文件超过阈值，跳到下一用户", .info)
                        return
                    }
                }

                guard result.hasMore else { break }
                page = result.nextPage ?? (page + 1)

                let delay = Int.random(in: settings.antiCrawlDelayRange)
                log("随机等待 \(delay)ms", .info)
                try await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    // MARK: - 结果分发

    /// 将一批下载结果转换为日志与进度事件，并更新目录缓存
    private func emit(
        _ results: [DownloadService.DownloadResult],
        log: LogHandler, onProgress: ProgressHandler, skipCount: inout Int
    ) {
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
                markDownloaded(name, in: r.destination.deletingLastPathComponent())
                log("已完成: \(name)", .success)
                onProgress(.completed(fileName: name, bytes: r.byteCount))
            }
        }
    }

    // MARK: - 并发下载（滑动窗口）

    /// 使用 TaskGroup 滑动窗口并发下载同一条微博的多个媒体文件，
    /// 并发上限由 maxConcurrentDownloads 控制；已存在文件经目录缓存直接跳过。
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
        guard !filtered.isEmpty else { return [] }

        let existing = existingNames(in: directory)
        let shortenName = settings.enableShortenName
        var results: [DownloadService.DownloadResult] = []
        var pending: [(url: URL, destination: URL)] = []

        for item in filtered {
            let name = fileService.cleanFileName(item.fileName(post: post, shortenName: shortenName))
            let destination = directory.appendingPathComponent(name)
            if existing.contains(name) {
                results.append(.skipped(url: item.url, destination: destination))
            } else {
                pending.append((item.url, destination))
            }
        }

        guard !pending.isEmpty else { return results }

        let setTimestamp = settings.dataSource != .weiboCom2
        let date = post.createdAt
        let maxConcurrent = max(1, settings.maxConcurrentDownloads)
        let svc = downloadService

        let downloaded = await withTaskGroup(of: DownloadService.DownloadResult.self) { group in
            var collected: [DownloadService.DownloadResult] = []
            var index = 0
            var running = 0

            func addNext() -> Bool {
                guard index < pending.count else { return false }
                let job = pending[index]
                index += 1
                group.addTask {
                    await svc.downloadMedia(
                        url: job.url, destination: job.destination, date: date, setTimestamp: setTimestamp
                    )
                }
                return true
            }

            for _ in 0..<maxConcurrent where addNext() { running += 1 }

            while running > 0, let result = await group.next() {
                collected.append(result)
                running -= 1
                if addNext() { running += 1 }
            }
            return collected
        }

        results.append(contentsOf: downloaded)
        return results
    }

    // MARK: - 目录缓存

    private func existingNames(in directory: URL) -> Set<String> {
        if let cached = dirCache[directory.path] { return cached }
        let names = fileService.existingFileNames(in: directory)
        dirCache[directory.path] = names
        return names
    }

    private func markDownloaded(_ name: String, in directory: URL) {
        dirCache[directory.path, default: []].insert(name)
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
