import Foundation

// MARK: - PushPlus 微信推送服务

/// 通过 PushPlus（https://www.pushplus.plus）发送微信通知
/// 用于在下载完成后推送消息到用户微信，方便批量/定时任务监控
/// 对应 C# 版的 PushPlusHelper.cs
enum PushPlusService {

    /// 发送推送消息（失败时静默忽略，不影响主流程）
    static func sendMessage(token: String, title: String, content: String) async {
        guard !token.isEmpty else { return }

        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let encodedContent = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? content

        guard let url = URL(string: "http://www.pushplus.plus/send?token=\(token)&title=\(encodedTitle)&content=\(encodedContent)") else {
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // 推送成功
            }
        } catch {
            // 推送通知失败不应中断下载流程
        }
    }
}
