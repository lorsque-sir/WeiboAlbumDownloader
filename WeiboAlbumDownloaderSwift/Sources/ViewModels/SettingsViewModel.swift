import Foundation
import SwiftUI

// MARK: - 设置视图模型

/// 管理应用设置的 ViewModel
/// 负责设置的加载、修改和持久化，以及 Cookie 获取弹窗的状态管理
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var showCnCookieSheet = false
    @Published var showComCookieSheet = false

    init() {
        self.settings = AppSettings.load()
    }

    /// 重新从磁盘加载设置
    func reload() {
        settings = AppSettings.load()
    }

    /// 保存设置到磁盘（启用时间范围过滤但未设置起始日期时不保存，防止无效配置）
    func save() {
        if settings.enableDatetimeRange && settings.startDateTime == nil {
            return
        }
        try? settings.save()
    }

    /// 设置 weibo.cn 域 Cookie 并立即保存
    func setCnCookie(_ cookie: String) {
        settings.weiboCnCookie = cookie
        save()
    }

    /// 设置 weibo.com 域 Cookie 并立即保存
    func setComCookie(_ cookie: String) {
        settings.weiboComCookie = cookie
        save()
    }

    var hasCnCookie: Bool {
        !(settings.weiboCnCookie ?? "").isEmpty
    }

    var hasComCookie: Bool {
        !(settings.weiboComCookie ?? "").isEmpty
    }

    var crontabDescription: String {
        guard let cron = settings.crontab, !cron.isEmpty else { return "未设置" }
        return "Cron: \(cron)"
    }
}
