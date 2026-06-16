import Foundation
import Observation

// MARK: - 下载断点状态（崩溃恢复 / 暂停恢复）

/// 单用户时间流下载的断点信息，持久化后可在崩溃或暂停后从中断处继续。
struct DownloadResumeState: Codable, Sendable {
    var uid: String
    var nickname: String?
    var dataSource: WeiboDataSource
    var page: Int
    var sinceId: Int64
    var completed: Int
    var skipped: Int
    var failed: Int
    var updatedAt: Date

    var summary: String {
        "\(nickname ?? uid) · 第 \(page) 页 · 成功 \(completed)/跳过 \(skipped)/失败 \(failed)"
    }
}

// MARK: - 断点持久化（轻量文件读写）

/// 断点状态的磁盘读写。文件位于配置目录下的 resume.json。
enum ResumeStateStore {
    private static var url: URL {
        AppSettings.settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("resume.json")
    }

    static func load() -> DownloadResumeState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DownloadResumeState.self, from: data)
    }

    static func save(_ state: DownloadResumeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - 下载历史记录

/// 单条下载历史
struct DownloadHistoryEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    let uid: String
    let nickname: String?
    let date: Date
    let completed: Int
    let skipped: Int
    let failed: Int
    let isBatch: Bool

    var displayName: String { nickname.map { "\($0) (\(uid))" } ?? uid }
}

/// 下载历史的内存缓存 + 磁盘持久化（JSON 数组），供 UI 展示。
@MainActor
@Observable
final class DownloadHistoryStore {
    static let shared = DownloadHistoryStore()

    private(set) var entries: [DownloadHistoryEntry] = []

    private let maxEntries = 200
    private var url: URL {
        AppSettings.settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("history.json")
    }

    private init() {
        load()
    }

    func add(_ entry: DownloadHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DownloadHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
