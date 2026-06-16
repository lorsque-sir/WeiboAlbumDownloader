import SwiftUI

// MARK: - 日志列表视图

struct LogListView: View {
    let logStore: LogStore
    @Binding var filterLevel: LogLevel?

    var body: some View {
        VStack(spacing: 0) {
            logFilterBar
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredMessages) { message in
                            LogRowView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .onChange(of: logStore.messages.count) {
                    if let last = filteredMessages.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
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
    }

    private var filteredMessages: [LogMessage] {
        guard let level = filterLevel else { return logStore.messages }
        return logStore.messages.filter { $0.level == level }
    }

    // MARK: - 过滤栏

    private var logFilterBar: some View {
        HStack(spacing: 4) {
            Text("日志")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            filterButton(level: nil, label: "全部", icon: "list.bullet")
            filterButton(level: .error, label: "错误", icon: "xmark.circle.fill")
            filterButton(level: .warning, label: "警告", icon: "exclamationmark.triangle.fill")
            filterButton(level: .success, label: "成功", icon: "checkmark.circle.fill")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func filterButton(level: LogLevel?, label: String, icon: String) -> some View {
        let isActive = filterLevel == level
        let count = logStore.count(for: level)

        return Button {
            filterLevel = level
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, design: .rounded))
                }
            }
            .foregroundStyle(isActive ? .white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func copyAllLogs() {
        let text = logStore.messages.map { "[\($0.timeString)] \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "weibo-download-log.txt"

        if panel.runModal() == .OK, let url = panel.url {
            let text = logStore.messages.map { "[\($0.timeString)] [\($0.level.rawValue)] \($0.text)" }.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 单行日志

private struct LogRowView: View {
    let message: LogMessage
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
        .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
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
}
