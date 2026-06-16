import Foundation
import SwiftUI

// MARK: - 日志消息模型

/// 用于 UI 日志列表展示的消息条目
struct LogMessage: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let text: String
    let level: LogLevel

    init(_ text: String, level: LogLevel = .info) {
        self.time = Date()
        self.text = text
        self.level = level
    }

    var timeString: String {
        Self.formatter.string(from: time)
    }

    var color: Color {
        switch level {
        case .info:    return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
