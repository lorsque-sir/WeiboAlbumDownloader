import SwiftUI

// MARK: - 日志列表视图

struct LogListView: View {
    let messages: [LogMessage]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    LogRowView(message: message, isEven: index % 2 == 0)
                        .id(message.id)
                }
            }
        }
        .contextMenu {
            Button {
                copyAllLogs()
            } label: {
                Label("复制全部日志", systemImage: "doc.on.doc")
            }
            Button {
                exportLog()
            } label: {
                Label("导出日志...", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func copyAllLogs() {
        let text = messages.reversed().map { "[\($0.timeString)] \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

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

// MARK: - 单行日志

private struct LogRowView: View {
    let message: LogMessage
    let isEven: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.timeString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .leading)

            logLevelBadge

            Text(message.text)
                .font(.system(size: 12))
                .foregroundStyle(message.color)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .onHover { isHovered = $0 }
    }

    private var logLevelBadge: some View {
        Group {
            switch message.level {
            case .info:
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue.opacity(0.6))
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
        .font(.system(size: 11))
        .frame(width: 14)
    }

    private var rowBackground: some View {
        Group {
            if isHovered {
                Color.accentColor.opacity(0.06)
            } else if isEven {
                Color(nsColor: .alternatingContentBackgroundColors[1]).opacity(0.5)
            } else {
                Color.clear
            }
        }
    }
}
