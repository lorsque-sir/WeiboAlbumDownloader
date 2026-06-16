import SwiftUI

// MARK: - 日志列表视图

/// 展示下载过程中的实时日志，支持：
/// - 不同日志级别对应不同颜色和图标
/// - 文本可选中复制
/// - 右键菜单：复制全部日志、导出日志到文件
struct LogListView: View {
    let messages: [LogMessage]

    var body: some View {
        List(messages) { message in
            HStack(alignment: .top, spacing: 8) {
                Text(message.timeString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                logIcon(for: message.level)
                    .frame(width: 14)

                Text(message.text)
                    .font(.system(.caption))
                    .foregroundStyle(message.color)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .listRowSeparator(.hidden)
            .padding(.vertical, 1)
        }
        .listStyle(.plain)
        .contextMenu {
            Button("复制全部日志") {
                let text = messages.map { "[\($0.timeString)] \($0.text)" }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            Button("导出日志...") {
                exportLog()
            }
        }
    }

    /// 不同日志级别对应的图标
    private func logIcon(for level: LogLevel) -> some View {
        Group {
            switch level {
            case .info:
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    /// 通过 NSSavePanel 导出日志到文本文件
    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "weibo-download-log.txt"

        if panel.runModal() == .OK, let url = panel.url {
            let text = messages.reversed().map { "[\($0.timeString)] [\($0.level.rawValue)] \($0.text)" }.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
