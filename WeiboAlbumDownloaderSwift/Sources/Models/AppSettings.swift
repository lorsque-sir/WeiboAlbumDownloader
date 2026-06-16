import Foundation
import Observation

// MARK: - 应用配置管理器

/// 配置单例，避免每次下载都从磁盘读取，并作为全局唯一配置来源。
/// 使用 Observation 框架，SwiftUI 视图可直接观察 `current` 的变化。
@MainActor
@Observable
final class AppSettingsManager {
    static let shared = AppSettingsManager()

    private(set) var current: AppSettings

    private init() {
        self.current = AppSettings.load()
    }

    func reload() {
        current = AppSettings.load()
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&current)
        try? current.save()
    }

    /// 用编辑后的完整配置覆盖当前配置并持久化（设置界面保存时调用）
    func apply(_ newSettings: AppSettings) {
        current = newSettings
        try? current.save()
    }
}

// MARK: - 应用配置模型

/// 应用配置。Cookie 仅存于 Keychain，绝不写入此 JSON。
struct AppSettings: Codable, Sendable {
    /// 当前使用的数据源
    var dataSource: WeiboDataSource = .weiboCnMobile
    /// 是否下载并显示用户头像
    var showHeadImage: Bool = true
    /// PushPlus 微信推送 Token，留空则不推送
    var pushPlusToken: String?
    /// 是否启用定时任务
    var enableCrontab: Bool = false
    /// Cron 表达式，默认每天凌晨 2:14 执行
    var crontab: String? = "14 2 * * *"
    /// 智能跳过阈值：连续遇到 N 个已存在文件时跳到下一用户（增量下载优化）
    var countDownloadedSkipToNextUser: Int = 20
    /// 是否启用时间范围过滤
    var enableDatetimeRange: Bool = false
    /// 起始日期（早于此日期的微博将被跳过）
    var startDateTime: Date?
    /// 是否下载视频
    var enableDownloadVideo: Bool = true
    /// 是否下载 LivePhoto
    var enableDownloadLivePhoto: Bool = true
    /// 短文件名模式：仅保留日期+编号，不含微博正文
    var enableShortenName: Bool = false
    /// 同一条微博内媒体文件的最大并发下载数
    var maxConcurrentDownloads: Int = 3
    /// 批量下载时，相邻两个用户之间的等待间隔（秒），过短易触发限流
    var batchIntervalSeconds: Int = 60
    /// 反爬翻页延迟下限（毫秒）
    var antiCrawlMinDelayMs: Int = 5000
    /// 反爬翻页延迟上限（毫秒）
    var antiCrawlMaxDelayMs: Int = 10000
    /// 是否在下载完成时发送 macOS 系统通知
    var enableSystemNotification: Bool = true

    /// 根据当前数据源自动选择对应域的 Cookie（从 Keychain 读取）
    var activeCookie: String? {
        dataSource.needsCnCookie ? CookieService.loadCnCookie() : CookieService.loadComCookie()
    }

    /// 规范化后的反爬延迟区间（毫秒），保证 min ≤ max 且非负
    var antiCrawlDelayRange: ClosedRange<Int> {
        let lower = max(0, antiCrawlMinDelayMs)
        let upper = max(lower, antiCrawlMaxDelayMs)
        return lower...upper
    }

    /// 规范化后的批量用户间隔（秒），下限 0
    var normalizedBatchInterval: Int { max(0, batchIntervalSeconds) }

    /// 配置文件存储路径：~/Library/Application Support/WeiboAlbumDownloader/Settings.json
    static let settingsURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WeiboAlbumDownloader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Settings.json")
    }()

    /// 默认下载目录：~/Downloads/WeiboAlbum/
    static let defaultDownloadDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Downloads/WeiboAlbum", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 从磁盘加载配置，文件不存在或损坏时返回默认值。
    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    /// 原子性写入磁盘
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.settingsURL, options: .atomic)
    }
}
