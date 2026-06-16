import Foundation

// MARK: - 轻量级 Cron 定时调度器

/// 简易 Cron 调度器，支持标准 5 字段格式：分 时 日 月 周
/// 替代 C# 版依赖的 TimeCrontab + CronExpressionDescriptor 两个 NuGet 包
/// 使用 actor 保证定时任务的启动/停止线程安全
actor CronScheduler {
    private var task: Task<Void, Never>?
    private let action: @Sendable () async -> Void

    init(action: @Sendable @escaping () async -> Void) {
        self.action = action
    }

    /// 启动定时调度（如已有运行中的任务会先停止）
    func start(expression: String) {
        stop()
        guard let cron = CronExpression(expression) else { return }

        task = Task {
            while !Task.isCancelled {
                let now = Date()
                guard let nextFire = cron.nextDate(after: now) else {
                    try? await Task.sleep(for: .seconds(60))
                    continue
                }

                // 休眠至下次触发时间
                let delay = nextFire.timeIntervalSince(now)
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }

                guard !Task.isCancelled else { break }
                await action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// Cron 表达式解析器（5 字段：分 时 日 月 周）
/// 支持通配符 *、步长 */n、范围 a-b、逗号列表 a,b,c
struct CronExpression: Sendable {
    let minute: CronField
    let hour: CronField
    let dayOfMonth: CronField
    let month: CronField
    let dayOfWeek: CronField

    init?(_ expression: String) {
        let parts = expression.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
        guard parts.count == 5 else { return nil }

        guard let min = CronField(parts[0], range: 0...59),
              let hr = CronField(parts[1], range: 0...23),
              let dom = CronField(parts[2], range: 1...31),
              let mon = CronField(parts[3], range: 1...12),
              let dow = CronField(parts[4], range: 0...6) else {
            return nil
        }

        self.minute = min
        self.hour = hr
        self.dayOfMonth = dom
        self.month = mon
        self.dayOfWeek = dow
    }

    /// 计算指定时间之后的下一个触发时间
    /// 通过逐分钟递增匹配的方式查找，最远查找 366 天
    func nextDate(after date: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0

        guard var candidate = calendar.date(from: components) else { return nil }
        candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate

        let limit = calendar.date(byAdding: .day, value: 366, to: date) ?? date

        while candidate < limit {
            let c = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)

            if minute.matches(c.minute ?? 0)
                && hour.matches(c.hour ?? 0)
                && dayOfMonth.matches(c.day ?? 1)
                && month.matches(c.month ?? 1)
                // Calendar 中 Sunday=1，Cron 中 Sunday=0，需转换
                && dayOfWeek.matches((c.weekday ?? 1) - 1) {
                return candidate
            }

            candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate
        }

        return nil
    }
}

/// Cron 字段：表示通配符（*）或一组特定值
enum CronField: Sendable {
    /// 匹配任意值
    case any
    /// 匹配特定值集合
    case values(Set<Int>)

    /// 解析单个 Cron 字段
    /// 支持格式：* (任意)、*/n (步长)、a-b (范围)、a,b,c (列表)、单个数字
    init?(_ string: String, range: ClosedRange<Int>) {
        if string == "*" {
            self = .any
            return
        }

        var result = Set<Int>()

        for part in string.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)

            // 步长格式：*/n
            if trimmed.hasPrefix("*/"), let step = Int(trimmed.dropFirst(2)), step > 0 {
                for v in stride(from: range.lowerBound, through: range.upperBound, by: step) {
                    result.insert(v)
                }
                continue
            }

            // 范围格式：a-b
            if trimmed.contains("-") {
                let bounds = trimmed.components(separatedBy: "-").compactMap { Int($0) }
                guard bounds.count == 2 else { return nil }
                for v in bounds[0]...bounds[1] where range.contains(v) {
                    result.insert(v)
                }
                continue
            }

            // 单个数值
            if let v = Int(trimmed), range.contains(v) {
                result.insert(v)
            } else {
                return nil
            }
        }

        self = result.isEmpty ? .any : .values(result)
    }

    func matches(_ value: Int) -> Bool {
        switch self {
        case .any: return true
        case .values(let set): return set.contains(value)
        }
    }
}
