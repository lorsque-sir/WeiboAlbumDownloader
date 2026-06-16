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
    /// 使用字段优先跳跃算法：按月→日→时→分逐级跳转到下一个匹配值，
    /// 避免逐分钟遍历，将最坏情况从 ~527K 次循环降低到 ~100 次
    func nextDate(after date: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0

        guard var candidate = calendar.date(from: components) else { return nil }
        candidate = calendar.date(byAdding: .minute, value: 1, to: candidate) ?? candidate

        let limit = calendar.date(byAdding: .day, value: 366, to: date) ?? date
        var iterations = 0
        let maxIterations = 1500

        while candidate < limit, iterations < maxIterations {
            iterations += 1
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: candidate)

            let cMonth = c.month ?? 1
            let cDay = c.day ?? 1
            let cHour = c.hour ?? 0
            let cMinute = c.minute ?? 0
            let cWeekday = (c.weekday ?? 1) - 1

            if !month.matches(cMonth) {
                if let next = month.nextMatch(after: cMonth) {
                    var nc = DateComponents(year: c.year, month: next, day: 1, hour: 0, minute: 0)
                    if next <= cMonth { nc.year = (c.year ?? 2024) + 1 }
                    candidate = calendar.date(from: nc) ?? candidate
                } else {
                    var nc = DateComponents(year: (c.year ?? 2024) + 1, month: month.firstValue ?? 1, day: 1, hour: 0, minute: 0)
                    nc.second = 0
                    candidate = calendar.date(from: nc) ?? candidate
                }
                continue
            }

            if !dayOfMonth.matches(cDay) || !dayOfWeek.matches(cWeekday) {
                candidate = calendar.date(byAdding: .day, value: 1, to:
                    calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 0, minute: 0))!
                ) ?? candidate
                continue
            }

            if !hour.matches(cHour) {
                if let next = hour.nextMatch(after: cHour) {
                    candidate = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: next, minute: minute.firstValue ?? 0))!
                } else {
                    candidate = calendar.date(byAdding: .day, value: 1, to:
                        calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 0, minute: 0))!
                    ) ?? candidate
                }
                continue
            }

            if !minute.matches(cMinute) {
                if let next = minute.nextMatch(after: cMinute) {
                    candidate = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour, minute: next))!
                } else {
                    candidate = calendar.date(byAdding: .hour, value: 1, to:
                        calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour, minute: 0))!
                    ) ?? candidate
                }
                continue
            }

            return candidate
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

    /// 返回大于 current 的下一个匹配值，无则返回 nil（需绕回）
    func nextMatch(after current: Int) -> Int? {
        switch self {
        case .any: return current + 1
        case .values(let set): return set.sorted().first(where: { $0 > current })
        }
    }

    /// 返回字段中最小的匹配值
    var firstValue: Int? {
        switch self {
        case .any: return 0
        case .values(let set): return set.min()
        }
    }
}
