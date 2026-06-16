import Foundation
import Observation
import AppKit

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
    /// 失败文件的完整目标路径，重试时写回原位置
    let destination: URL
    let errorDescription: String
}

// MARK: - 下载主视图模型

@MainActor
@Observable
final class DownloadViewModel {
    var uid: String = ""
    private(set) var isDownloading = false
    private(set) var userInfo: WeiboUser?
    var showSettings = false
    var showHistory = false
    private(set) var progress = DownloadProgress()
    private(set) var failedItems: [FailedItem] = []
    var logFilterLevel: LogLevel?

    /// 可恢复的断点（来自上次未完成的下载），非 nil 时 UI 显示「继续」横幅
    private(set) var resumableState: DownloadResumeState?
    private(set) var downloadedBytes: Int64 = 0

    let logStore = LogStore()

    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var cronScheduler: CronScheduler?
    @ObservationIgnored private var settingsObserver: Any?
    @ObservationIgnored private var pendingEvents: [DownloadCoordinator.DownloadEvent] = []
    @ObservationIgnored private var batchFlushTask: Task<Void, Never>?
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var currentUID: String = ""

    private var settings: AppSettings {
        AppSettingsManager.shared.current
    }

    init() {
        resumableState = ResumeStateStore.load()
        if let resume = resumableState {
            logStore.append("检测到上次未完成的下载：\(resume.summary)", level: .warning)
        }
        configureCronScheduler()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                AppSettingsManager.shared.reload()
                self?.configureCronScheduler()
            }
        }
    }

    // MARK: - 速度展示

    var speedText: String {
        guard isDownloading, let start = sessionStart else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0.5, downloadedBytes > 0 else { return "" }
        let bps = Int64(Double(downloadedBytes) / elapsed)
        return ByteCountFormatter.string(fromByteCount: bps, countStyle: .file) + "/s"
    }

    var downloadedSizeText: String {
        guard downloadedBytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
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

        let scheduler = CronScheduler { [weak self] in
            await MainActor.run {
                guard let self, !self.isDownloading else { return }
                self.logStore.append("Cron 定时任务触发，开始批量下载", level: .info)
                self.batchDownload()
            }
        }
        cronScheduler = scheduler

        Task {
            if let old = oldScheduler {
                await old.stop()
            }
            await scheduler.start(expression: expression)
        }
        logStore.append("Cron 定时任务已启动: \(expression)", level: .info)
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

    func startDownload(resume: DownloadResumeState? = nil) {
        guard !uid.trimmingCharacters(in: .whitespaces).isEmpty else {
            logStore.append("请输入微博 UID", level: .warning)
            return
        }

        let targetUID = uid.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .first ?? ""

        guard !targetUID.isEmpty else {
            logStore.append("没有找到有效的微博 UID", level: .warning)
            return
        }

        currentUID = targetUID
        isDownloading = true
        userInfo = nil
        sessionStart = Date()
        downloadedBytes = 0
        failedItems = []

        if let resume, resume.uid == targetUID {
            progress = DownloadProgress()
            progress.completed = resume.completed
            progress.skipped = resume.skipped
            progress.failed = resume.failed
            progress.currentPage = resume.page
        } else {
            progress = DownloadProgress()
            resumableState = nil
        }

        let currentSettings = settings
        let resumeState = resume
        downloadTask = Task {
            var stopped = false
            do {
                let coordinator = DownloadCoordinator(settings: currentSettings)
                try await coordinator.downloadUser(
                    uid: targetUID,
                    log: { [weak self] text, level in
                        Task { @MainActor in self?.logStore.append(text, level: level) }
                    },
                    onUserInfo: { [weak self] user in
                        Task { @MainActor in self?.userInfo = user }
                    },
                    onProgress: { [weak self] event in
                        Task { @MainActor in self?.enqueueProgressEvent(event) }
                    },
                    resumeFrom: resumeState
                )
                flushPendingEvents()
                let p = progress
                logStore.append("下载完成 — 成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)", level: .success)
                finishSingle(uid: targetUID, progress: p, settings: currentSettings)
            } catch is CancellationError {
                stopped = true
                flushPendingEvents()
                logStore.append("下载已停止，进度已保存，可点击「继续」恢复", level: .info)
            } catch let dlError as DownloadError {
                logStore.append(dlError.localizedDescription, level: .error)
            } catch {
                logStore.append("下载出错: \(error.localizedDescription)", level: .error)
            }
            if !stopped {
                ResumeStateStore.clear()
                resumableState = nil
            }
            isDownloading = false
            sessionStart = nil
        }
    }

    /// 停止当前下载，但保留断点以便继续
    func stopDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        logStore.append("正在停止下载...", level: .info)
    }

    /// 从断点继续下载
    func resumeDownload() {
        guard let state = resumableState, !isDownloading else { return }
        uid = state.uid
        startDownload(resume: state)
    }

    /// 放弃断点，清除已保存的恢复状态
    func discardResume() {
        ResumeStateStore.clear()
        resumableState = nil
        logStore.append("已放弃上次的下载进度", level: .info)
    }

    func batchDownload() {
        let uids = uidList
        guard !uids.isEmpty else {
            logStore.append("UID 列表为空，请在设置中添加用户", level: .warning)
            return
        }

        isDownloading = true
        sessionStart = Date()
        downloadedBytes = 0
        progress = DownloadProgress()
        progress.batchTotalCount = uids.count
        failedItems = []
        resumableState = nil
        ResumeStateStore.clear()
        logStore.append("开始批量下载 \(uids.count) 个用户", level: .info)

        let currentSettings = settings
        let interval = currentSettings.normalizedBatchInterval
        downloadTask = Task {
            for (index, batchUID) in uids.enumerated() {
                if Task.isCancelled { break }

                progress.batchCurrentIndex = index + 1
                logStore.append("[\(index + 1)/\(uids.count)] 开始下载 \(batchUID)", level: .info)

                do {
                    let coordinator = DownloadCoordinator(settings: currentSettings)
                    try await coordinator.downloadUser(
                        uid: batchUID,
                        log: { [weak self] text, level in
                            Task { @MainActor in self?.logStore.append(text, level: level) }
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
                    logStore.append("用户 \(batchUID) 下载出错: \(error.localizedDescription)", level: .error)
                }

                if index < uids.count - 1, interval > 0 {
                    logStore.append("等待 \(interval) 秒后下载下一个用户", level: .info)
                    try? await Task.sleep(for: .seconds(interval))
                }
            }

            flushPendingEvents()
            let p = progress
            logStore.append("批量下载完成 — 成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)", level: .success)

            DownloadHistoryStore.shared.add(DownloadHistoryEntry(
                uid: "batch", nickname: "批量(\(uids.count))", date: Date(),
                completed: p.completed, skipped: p.skipped, failed: p.failed, isBatch: true
            ))
            await notifyFinish(
                settings: currentSettings, title: "微博相册批量下载",
                content: "批量下载 \(uids.count) 个用户完成：成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)"
            )
            isDownloading = false
            sessionStart = nil
        }
    }

    func clearLog() {
        logStore.clear()
    }

    func retryFailedItems() {
        let items = failedItems
        guard !items.isEmpty else { return }
        failedItems.removeAll()

        isDownloading = true
        sessionStart = Date()
        logStore.append("开始重试 \(items.count) 个失败文件", level: .info)

        downloadTask = Task {
            let httpClient = HTTPClient.shared

            for item in items {
                if Task.isCancelled { break }

                do {
                    // 写回失败项记录的原始完整路径，而非默认根目录
                    let bytes = try await httpClient.downloadFile(item.url, to: item.destination)
                    downloadedBytes += bytes
                    logStore.append("重试成功: \(item.fileName)", level: .success)
                    progress.completed += 1
                } catch {
                    logStore.append("重试失败: \(item.fileName) - \(error.localizedDescription)", level: .error)
                    progress.failed += 1
                    failedItems.append(item)
                }
            }

            logStore.append("重试完成", level: .success)
            isDownloading = false
            sessionStart = nil
        }
    }

    func openDownloadFolder() {
        NSWorkspace.shared.open(AppSettings.defaultDownloadDirectory)
    }

    // MARK: - 私有方法

    private func finishSingle(uid: String, progress p: DownloadProgress, settings: AppSettings) {
        DownloadHistoryStore.shared.add(DownloadHistoryEntry(
            uid: uid, nickname: userInfo?.screenName, date: Date(),
            completed: p.completed, skipped: p.skipped, failed: p.failed, isBatch: false
        ))
        addToUidList(uid: uid, nickname: userInfo?.screenName)
        let name = userInfo?.screenName ?? uid
        Task {
            await notifyFinish(
                settings: settings, title: "微博相册下载",
                content: "\(name) 下载完成：成功 \(p.completed) / 跳过 \(p.skipped) / 失败 \(p.failed)"
            )
        }
    }

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
            case .completed(_, let bytes):
                progress.completed += 1
                downloadedBytes += bytes
            case .skipped:
                progress.skipped += 1
            case .failed(let url, let fileName, let error):
                progress.failed += 1
                let destination = AppSettings.defaultDownloadDirectory.appendingPathComponent(fileName)
                failedItems.append(FailedItem(url: url, fileName: fileName, destination: destination, errorDescription: error))
            case .pageLoaded(let page):
                progress.currentPage = page
            case .checkpoint(let page, let sinceId):
                saveCheckpoint(page: page, sinceId: sinceId)
            }
        }
    }

    private func saveCheckpoint(page: Int, sinceId: Int64) {
        guard !currentUID.isEmpty, !progress.isBatchMode else { return }
        let state = DownloadResumeState(
            uid: currentUID, nickname: userInfo?.screenName, dataSource: settings.dataSource,
            page: page, sinceId: sinceId,
            completed: progress.completed, skipped: progress.skipped, failed: progress.failed,
            updatedAt: Date()
        )
        resumableState = state
        ResumeStateStore.save(state)
    }

    private func notifyFinish(settings: AppSettings, title: String, content: String) async {
        if settings.enableSystemNotification {
            await NotificationService.notify(title: title, body: content)
        }
        if let token = settings.pushPlusToken, !token.isEmpty {
            await PushPlusService.sendMessage(token: token, title: title, content: content)
        }
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
