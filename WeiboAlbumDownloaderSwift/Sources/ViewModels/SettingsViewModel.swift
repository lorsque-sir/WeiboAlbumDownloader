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
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }

    /// 设置 weibo.cn 域 Cookie（存入 Keychain）
    func setCnCookie(_ cookie: String) {
        CookieService.saveCnCookie(cookie)
        objectWillChange.send()
    }

    /// 设置 weibo.com 域 Cookie（存入 Keychain）
    func setComCookie(_ cookie: String) {
        CookieService.saveComCookie(cookie)
        objectWillChange.send()
    }

    var hasCnCookie: Bool {
        !(CookieService.loadCnCookie() ?? "").isEmpty
    }

    var hasComCookie: Bool {
        !(CookieService.loadComCookie() ?? "").isEmpty
    }

    /// Keychain 中的 weibo.cn Cookie（用于手动粘贴 TextField 绑定）
    var cnCookieText: String {
        get { CookieService.loadCnCookie() ?? "" }
        set {
            if newValue.isEmpty {
                CookieService.saveCnCookie("")
            } else {
                CookieService.saveCnCookie(newValue)
            }
            objectWillChange.send()
        }
    }

    /// Keychain 中的 weibo.com Cookie（用于手动粘贴 TextField 绑定）
    var comCookieText: String {
        get { CookieService.loadComCookie() ?? "" }
        set {
            if newValue.isEmpty {
                CookieService.saveComCookie("")
            } else {
                CookieService.saveComCookie(newValue)
            }
            objectWillChange.send()
        }
    }

    var crontabDescription: String {
        guard let cron = settings.crontab, !cron.isEmpty else { return "未设置" }
        return "Cron: \(cron)"
    }
}
