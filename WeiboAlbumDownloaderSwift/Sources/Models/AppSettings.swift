import Foundation

// MARK: - 应用配置模型

/// 应用全局配置，持久化存储到 ~/Library/Application Support/WeiboAlbumDownloader/Settings.json
/// 所有字段均为 Codable，支持 JSON 序列化/反序列化
struct AppSettings: Codable {
    /// 当前使用的数据源
    var dataSource: WeiboDataSource = .weiboCnMobile
    /// 是否下载并显示用户头像
    var showHeadImage: Bool = true
    /// weibo.cn / m.weibo.cn 域的 Cookie
    var weiboCnCookie: String?
    /// weibo.com 域的 Cookie
    var weiboComCookie: String?
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

    /// 根据当前数据源自动选择对应域的 Cookie
    var activeCookie: String? {
        dataSource.needsCnCookie ? weiboCnCookie : weiboComCookie
    }

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

    /// 从磁盘加载配置，文件不存在时返回默认值
    static func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    /// 将当前配置原子性写入磁盘
    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.settingsURL, options: .atomic)
    }
}
