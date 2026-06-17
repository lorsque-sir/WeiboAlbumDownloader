import SwiftUI

// MARK: - 下载历史界面

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    private var store: DownloadHistoryStore { DownloadHistoryStore.shared }
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("下载历史")
                    .font(.title2.bold())
            }

            Spacer()

            if !store.entries.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .confirmationDialog("确定清空全部历史记录？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                    Button("清空历史", role: .destructive) { store.clear() }
                    Button("取消", role: .cancel) {}
                }
            }

            Button("完成") { dismiss() }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func historyRow(_ entry: DownloadHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isBatch ? "person.2.fill" : "person.fill")
                .font(.system(size: 14))
                .foregroundStyle(entry.isBatch ? .indigo : .blue)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                statBadge(value: entry.completed, color: .green, icon: "checkmark")
                statBadge(value: entry.skipped, color: .orange, icon: "arrow.right")
                if entry.failed > 0 {
                    statBadge(value: entry.failed, color: .red, icon: "xmark")
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    private func statBadge(value: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("暂无下载历史")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
