import Foundation
import UserNotifications

// MARK: - macOS 原生通知服务

/// 通过 UNUserNotificationCenter 在下载完成时推送系统通知，
/// 补充 PushPlus（需联网+配置 Token）之外的本地即时提醒。
/// 失败时静默忽略，不影响主流程。
enum NotificationService {

    /// 请求通知授权（应用启动时调用一次）
    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 发送一条本地通知
    static func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
