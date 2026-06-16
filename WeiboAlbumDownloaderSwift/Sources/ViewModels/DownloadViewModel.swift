import Foundation
import SwiftUI

// MARK: - 下载进度模型

struct DownloadProgress: Sendable {
    var completed: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var currentPage: Int = 0
    var batchCurrentIndex: Int = 0
    var batchTotalCount: Int = 0

    var total: Int { completed + skipped + failed }

    var isBatchMode: Bool { batchTotalCount > 0 }

    var summaryText: String {
        var text = "完成 \(completed) | 跳过 \(skipped) | 失败 \(failed)"
        if isBatchMode {
            text += " | 用户 \(batchCurrentIndex)/\(batchTotalCount)"
        }
        return text
    }
}

struct FailedItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let fileName: String
    let errorDescription: String
}

// MARK: - 下载主视图模型

@MainActor
final class DownloadViewModel: ObservableObject {
    @Published var uid: String = ""
    @Published var messages: [LogMessage] = []
    @Published var isDownloading = false
    @Published var userInfo: WeiboUser?
    @Published var showSettings = false
    @Published var progress = DownloadProgress()
    @Published var failedItems: [FailedItem] = []
    @Published var logFilterLevel: LogLevel?

    private var downloadTask: Task<Void, Never>?
    private var cronScheduler: CronScheduler?
    private var settingsObserver: Any?

    private var pendingEvents: [DownloadCoordinator.DownloadEvent] = []
    private var batchFlushTask: Task<Void, Never>?

    private var settings: AppSettings {
        AppSettingsManager.shared.current
    }

    init() {
        configureCronScheduler()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppSettingsManager.shared.reload()
                self?.configureCronScheduler()
            }
        }
    }

    // MARK: - Cron 调度

    func configureCronScheduler() {
        let oldScheduler = cronScheduler
        cronScheduler = nil

        guard settings.enableCrontab,
              let expression = settings.crontab, !expression.isEmpty else {
            if let old = oldScheduler {
                Task { await old.stop() }
            }
            return
        }

        let scheduler = CronScheduler { @MainActor [weak self] in
            guard let self, !self.isDownloading else { return }
            self.appendLog("Cron 定时任务触发，开始批量下载", level: .info)
            self.batchDownload()
        }
        cronScheduler = scheduler

        Task {
            if let old = oldScheduler {
                await old.stop()
            }
            await scheduler.start(expression: expression)
        }
        appendLog("Cron 定时任务已启动: \(expression)", level: .info)
    }

    // MARK: - UID 列表读取

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

    // MARK: - 下载控制

    func toggleDownload() {
        if isDownloading {
            stopDownload()
        } else {
            startDownload()
        }
    }

    func startDownload() {
        guard !uid.trimmingCharacters(in: .whitespaces).isEmpty else {
            appendLog("请输入微博 UID", level: .warning)
            return
        }

        let targetUID = uid.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .first ?? ""

        guard !targetUID.isEmpty else {
            appendLog("没有找到有效的微博 UID", level: .warning)
            return
        }

        isDownloading = true
        userInfo = nil
        progress = DownloadProgress()
        failedItems = []

        let currentSettings = settings
        downloadTask = Task {
            do {
                let coordinator = DownloadCoordinator(settings: currentSettings)
                try await coordinator.downloadUser(
                    uid: targetUID,
                    log: { [weak self] text, level in
                        Task { @MainActor in self?.appendLog(text, level: level) }
                    },
                    onUserInfo: { [weak self] user in
                        Task { @MainActor in self?.userInfo = user }
                    },
                    onProgress: { [weak self] event in
                        Task { @MainActor in self?.enqueueProgressEvent(event) }
                    }
                )
                flushPendingEvents()
                let p = progress
                appendLog("下载完成 — 成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)", level: .success)

                await sendPushNotification(
                    settings: currentSettings,
                    title: "微博相册下载",
                    content: "\(userInfo?.screenName ?? targetUID) 下载完成：成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)"
                )
                addToUidList(uid: targetUID, nickname: userInfo?.screenName)
            } catch is CancellationError {
                appendLog("下载已取消", level: .info)
            } catch let dlError as DownloadError {
                appendLog(dlError.localizedDescription, level: .error)
            } catch {
                appendLog("下载出错: \(error.localizedDescription)", level: .error)
            }
            isDownloading = false
        }
    }

    func stopDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        appendLog("正在停止下载...", level: .info)
    }

    func batchDownload() {
        let uids = uidList
        guard !uids.isEmpty else {
            appendLog("UID 列表为空，请在设置中添加用户", level: .warning)
            return
        }

        isDownloading = true
        progress = DownloadProgress()
        progress.batchTotalCount = uids.count
        failedItems = []
        appendLog("开始批量下载 \(uids.count) 个用户", level: .info)

        let currentSettings = settings
        downloadTask = Task {
            for (index, batchUID) in uids.enumerated() {
                if Task.isCancelled { break }

                progress.batchCurrentIndex = index + 1
                appendLog("[\(index + 1)/\(uids.count)] 开始下载 \(batchUID)", level: .info)

                do {
                    let coordinator = DownloadCoordinator(settings: currentSettings)
                    try await coordinator.downloadUser(
                        uid: batchUID,
                        log: { [weak self] text, level in
                            Task { @MainActor in self?.appendLog(text, level: level) }
                        },
                        onUserInfo: { [weak self] user in
                            Task { @MainActor in self?.userInfo = user }
                        },
                        onProgress: { [weak self] event in
                            Task { @MainActor in self?.enqueueProgressEvent(event) }
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

            flushPendingEvents()
            let p = progress
            appendLog("批量下载完成 — 成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)", level: .success)

            await sendPushNotification(
                settings: currentSettings,
                title: "微博相册批量下载",
                content: "批量下载 \(uids.count) 个用户完成：成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)"
            )
            isDownloading = false
        }
    }

    func clearLog() {
        messages.removeAll()
    }

    func retryFailedItems() {
        let items = failedItems
        guard !items.isEmpty else { return }
        failedItems.removeAll()

        isDownloading = true
        appendLog("开始重试 \(items.count) 个失败文件", level: .info)

        downloadTask = Task {
            let httpClient = HTTPClient.shared

            for item in items {
                if Task.isCancelled { break }

                do {
                    let destination = AppSettings.defaultDownloadDirectory
                        .appendingPathComponent(item.fileName)
                    try await httpClient.downloadFile(item.url, to: destination)
                    appendLog("重试成功: \(item.fileName)", level: .success)
                    progress.completed += 1
                } catch {
                    appendLog("重试失败: \(item.fileName) - \(error.localizedDescription)", level: .error)
                    progress.failed += 1
                    failedItems.append(FailedItem(
                        url: item.url,
                        fileName: item.fileName,
                        errorDescription: error.localizedDescription
                    ))
                }
            }

            appendLog("重试完成", level: .success)
            isDownloading = false
        }
    }

    func openDownloadFolder() {
        NSWorkspace.shared.open(AppSettings.defaultDownloadDirectory)
    }

    // MARK: - 私有方法

    private func enqueueProgressEvent(_ event: DownloadCoordinator.DownloadEvent) {
        pendingEvents.append(event)
        if batchFlushTask == nil {
            batchFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                self?.flushPendingEvents()
            }
        }
    }

    private func flushPendingEvents() {
        let events = pendingEvents
        pendingEvents.removeAll()
        batchFlushTask = nil

        for event in events {
            switch event {
            case .completed:
                progress.completed += 1
            case .skipped:
                progress.skipped += 1
            case .failed(let url, let fileName, let error):
                progress.failed += 1
                failedItems.append(FailedItem(url: url, fileName: fileName, errorDescription: error))
            case .pageLoaded(let page):
                progress.currentPage = page
            }
        }
    }

    private func appendLog(_ text: String, level: LogLevel = .info) {
        let msg = LogMessage(text, level: level)
        messages.append(msg)
        if messages.count > 500 {
            messages.removeFirst(messages.count - 500)
        }
    }

    private func sendPushNotification(settings: AppSettings, title: String, content: String) async {
        guard let token = settings.pushPlusToken, !token.isEmpty else { return }
        await PushPlusService.sendMessage(token: token, title: title, content: content)
    }

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
