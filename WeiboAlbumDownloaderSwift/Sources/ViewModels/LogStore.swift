import Foundation
import Observation

// MARK: - 日志存储

/// 集中管理日志条目，从 DownloadViewModel 中拆分出来。
/// 性能优化点：
/// 1. 维护各级别计数字典，UI 过滤栏显示数量时无需每帧 O(n) 遍历
/// 2. 超出上限时按批裁剪（分摊 O(1)），避免每条日志都触发 removeFirst 的 O(n) 拷贝
/// 3. 新消息追加到数组尾部，配合自动滚动，避免视图层 reversed() 的整段拷贝
@MainActor
@Observable
final class LogStore {
    /// 时间正序排列（最新在尾部）
    private(set) var messages: [LogMessage] = []
    /// 各级别消息计数缓存
    private(set) var counts: [LogLevel: Int] = [:]

    /// 软上限：达到 hardLimit 后一次性裁剪回 softLimit
    private let softLimit: Int
    private let hardLimit: Int

    init(softLimit: Int = 500, hardLimit: Int = 650) {
        self.softLimit = softLimit
        self.hardLimit = hardLimit
    }

    var total: Int { messages.count }

    func count(for level: LogLevel?) -> Int {
        guard let level else { return messages.count }
        return counts[level] ?? 0
    }

    func append(_ text: String, level: LogLevel = .info) {
        messages.append(LogMessage(text, level: level))
        counts[level, default: 0] += 1

        if messages.count >= hardLimit {
            let dropCount = messages.count - softLimit
            for m in messages.prefix(dropCount) {
                counts[m.level, default: 0] -= 1
            }
            messages.removeFirst(dropCount)
        }
    }

    func clear() {
        messages.removeAll()
        counts.removeAll()
    }
}
