import Foundation
import SwiftUI

// MARK: - 下载主视图模型

/// 下载功能的核心 ViewModel，管理 UI 状态和下载任务生命周期
/// 使用 @MainActor 确保所有 @Published 属性在主线程更新（替代 C# 的 Dispatcher.InvokeAsync）
@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var uid: String = ""
    @Published var messages: [LogMessage] = []
    @Published var isDownloading = false
    @Published var userInfo: WeiboUser?
    @Published var showSettings = false

    /// 当前下载任务句柄（用于取消操作）
    private var downloadTask: Task<Void, Never>?
    private var settings = AppSettings.load()

    /// 从 uidList.txt 文件读取批量下载的 UID 列表
    /// 文件格式：每行一个用户，支持 `UID,昵称` 格式，// 开头为注释
    var uidList: [String] {
        let url = AppSettings.settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("uidList.txt")

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            .map { $0.components(separatedBy: ",").first ?? $0 }
    }

    /// 切换下载/停止状态
    func toggleDownload() {
        if isDownloading {
            stopDownload()
        } else {
            startDownload()
        }
    }

    /// 开始单用户下载
    func startDownload() {
        guard !uid.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog("请输入微博 UID", level: .warning)
            return
        }

        // 从输入中提取纯数字 UID（支持用户粘贴带前缀的 URL 等格式）
        let targetUID = uid.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .first ?? ""

        guard !targetUID.isEmpty else {
            appendLog("没有找到有效的微博 UID", level: .warning)
            return
        }
        isDownloading = true
        settings = AppSettings.load()

        downloadTask = Task {
            do {
                let coordinator = DownloadCoordinator(settings: settings)
                try await coordinator.downloadUser(
                    uid: targetUID,
                    log: { [weak self] text, level in
                        Task { @MainActor in
                            self?.appendLog(text, level: level)
                        }
                    },
                    onUserInfo: { [weak self] user in
                        Task { @MainActor in
                            self?.userInfo = user
                        }
                    }
                )
                appendLog("下载完成", level: .success)

                // 下载完成后发送 PushPlus 微信推送
                if let token = settings.pushPlusToken, !token.isEmpty {
                    let info = "\(userInfo?.screenName ?? targetUID) 于 \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)) 结束下载"
                    await PushPlusService.sendMessage(token: token, title: "微博相册下载", content: info)
                }

                // 自动将下载过的 UID 追加到 uidList.txt
                addToUidList(uid: targetUID, nickname: userInfo?.screenName)
            } catch is CancellationError {
                appendLog("下载已取消", level: .info)
            } catch {
                appendLog("下载出错: \(error.localizedDescription)", level: .error)
            }
            isDownloading = false
        }
    }

    /// 停止当前下载（通过取消 Task 实现协作式取消）
    func stopDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        appendLog("正在停止下载...", level: .info)
    }

    /// 批量下载 uidList.txt 中的所有用户
    /// 用户之间间隔 60 秒，避免触发微博反爬
    func batchDownload() {
        let uids = uidList
        guard !uids.isEmpty else {
            appendLog("UID 列表为空，请先配置 uidList.txt", level: .warning)
            return
        }

        isDownloading = true
        settings = AppSettings.load()
        appendLog("开始批量下载 \(uids.count) 个用户", level: .info)

        downloadTask = Task {
            for (index, batchUID) in uids.enumerated() {
                if Task.isCancelled { break }

                appendLog("[\(index + 1)/\(uids.count)] 开始下载 \(batchUID)", level: .info)

                do {
                    let coordinator = DownloadCoordinator(settings: settings)
                    try await coordinator.downloadUser(
                        uid: batchUID,
                        log: { [weak self] text, level in
                            Task { @MainActor in self?.appendLog(text, level: level) }
                        },
                        onUserInfo: { [weak self] user in
                            Task { @MainActor in self?.userInfo = user }
                        }
                    )
                } catch is CancellationError {
                    break
                } catch {
                    appendLog("用户 \(batchUID) 下载出错: \(error.localizedDescription)", level: .error)
                }

                if index < uids.count - 1 {
                    appendLog("等待 60 秒后下载下一个用户", level: .info)
                    try? await Task.sleep(for: .seconds(60))
                }
            }

            appendLog("批量下载完成", level: .success)
            isDownloading = false
        }
    }

    func clearLog() {
        messages.removeAll()
    }

    /// 在 Finder 中打开下载目录
    func openDownloadFolder() {
        let url = AppSettings.defaultDownloadDirectory
        NSWorkspace.shared.open(url)
    }

    // MARK: - 私有方法

    /// 添加日志消息（新消息插入列表头部，限制最多 500 条防止内存溢出）
    private func appendLog(_ text: String, level: LogLevel = .info) {
        let msg = LogMessage(text, level: level)
        messages.insert(msg, at: 0)
        if messages.count > 500 {
            messages.removeLast(messages.count - 500)
        }
    }

    /// 将已下载的 UID 追加到 uidList.txt（去重，方便下次批量下载）
    private func addToUidList(uid: String, nickname: String?) {
        let url = AppSettings.settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("uidList.txt")

        if !FileManager.default.fileExists(atPath: url.path) {
            let header = "//可以是多用户，换行隔开。\n//行内用英文逗号隔开，用户id(必填),用户名(可选)\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !existing.contains(uid) else { return }

        let entry = nickname.map { "\(uid),\($0)" } ?? uid
        let line = "\n\(entry)"
        if let data = line.data(using: .utf8), let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }
}
