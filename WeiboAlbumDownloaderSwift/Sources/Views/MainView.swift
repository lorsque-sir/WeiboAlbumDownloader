import SwiftUI

// MARK: - 主界面

struct MainView: View {
    @EnvironmentObject var viewModel: DownloadViewModel
    @State private var isHoveringDownload = false
    @State private var showFailedItems = false

    var body: some View {
        HSplitView {
            sidebarPanel
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            VStack(spacing: 0) {
                controlBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)

                Divider()

                if viewModel.isDownloading || viewModel.progress.total > 0 {
                    progressPanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Divider()
                }

                if viewModel.messages.isEmpty && !viewModel.isDownloading {
                    emptyStateView
                } else {
                    LogListView(messages: viewModel.messages)
                }
            }
            .frame(minWidth: 500)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
                .frame(minWidth: 560, minHeight: 640)
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isDownloading)
        .animation(.easeInOut(duration: 0.25), value: viewModel.progress.total)
    }

    // MARK: - 侧边栏

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Spacer().frame(height: 24)
                avatarView
                userInfoSection
            }
            .padding(.horizontal, 16)

            Spacer()

            if viewModel.isDownloading || viewModel.progress.total > 0 {
                statsCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            sidebarButtons
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.8),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - 头像

    private var avatarView: some View {
        Group {
            if let avatarURL = viewModel.userInfo?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.gray.opacity(0.2), .gray.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 88, height: 88)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .overlay(
                Circle().stroke(.quaternary, lineWidth: 1)
            )
    }

    // MARK: - 用户信息

    private var userInfoSection: some View {
        VStack(spacing: 6) {
            if let user = viewModel.userInfo {
                Text(user.screenName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                Text("UID: \(user.uid)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let desc = user.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            } else {
                Text("未连接")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("输入 UID 开始下载")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 统计卡片

    private var statsCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("下载统计")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isDownloading, viewModel.progress.currentPage > 0 {
                    Text("第 \(viewModel.progress.currentPage) 页")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 0) {
                statItem(
                    value: viewModel.progress.completed,
                    label: "完成",
                    color: .green,
                    icon: "checkmark.circle.fill"
                )
                Divider().frame(height: 28)
                statItem(
                    value: viewModel.progress.skipped,
                    label: "跳过",
                    color: .orange,
                    icon: "arrow.right.circle.fill"
                )
                Divider().frame(height: 28)
                if viewModel.progress.failed > 0 {
                    Button { showFailedItems = true } label: {
                        statItem(
                            value: viewModel.progress.failed,
                            label: "失败",
                            color: .red,
                            icon: "xmark.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFailedItems) {
                        failedItemsPopover
                    }
                } else {
                    statItem(
                        value: 0,
                        label: "失败",
                        color: .secondary,
                        icon: "xmark.circle.fill"
                    )
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    private func statItem(value: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text("\(value)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 侧边栏按钮

    private var sidebarButtons: some View {
        VStack(spacing: 6) {
            sidebarButton(
                title: "批量下载",
                icon: "arrow.down.circle.fill",
                color: .blue
            ) {
                viewModel.batchDownload()
            }
            .disabled(viewModel.isDownloading)

            sidebarButton(
                title: "打开下载目录",
                icon: "folder.fill",
                color: .secondary
            ) {
                viewModel.openDownloadFolder()
            }

            sidebarButton(
                title: "设置",
                icon: "gearshape.fill",
                color: .secondary
            ) {
                viewModel.showSettings = true
            }
        }
    }

    private func sidebarButton(
        title: String, icon: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 控制栏

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 13))

                TextField("输入微博 UID", text: $viewModel.uid)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        viewModel.startDownload()
                    }

                if !viewModel.uid.isEmpty {
                    Button {
                        viewModel.uid = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 0.5)
            )

            Button(action: { viewModel.toggleDownload() }) {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.isDownloading ? "stop.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 12))
                    Text(viewModel.isDownloading ? "停止" : "下载")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(minWidth: 72)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isDownloading ? .red : .accentColor)
            .onHover { isHoveringDownload = $0 }
            .scaleEffect(isHoveringDownload ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHoveringDownload)

            Button {
                viewModel.clearLog()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .help("清空日志")
        }
    }

    // MARK: - 进度面板

    private var progressPanel: some View {
        HStack(spacing: 12) {
            if viewModel.isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }

            if !viewModel.isDownloading && viewModel.progress.total > 0 {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            }

            Text(progressText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.progress.total > 0 {
                Text("共 \(viewModel.progress.total) 个文件")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var progressText: String {
        if viewModel.isDownloading {
            if viewModel.progress.currentPage > 0 {
                return "正在下载第 \(viewModel.progress.currentPage) 页..."
            }
            return "准备中..."
        }
        return viewModel.progress.summaryText
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                Text("微博相册下载器")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("输入微博 UID 即可开始下载用户的全部图片和视频")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 20) {
                tipItem(icon: "1.circle.fill", text: "输入 UID")
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                tipItem(icon: "2.circle.fill", text: "点击下载")
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                tipItem(icon: "3.circle.fill", text: "自动保存")
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tipItem(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue.opacity(0.7))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 失败项弹窗

    private var failedItemsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("下载失败的文件")
                    .font(.headline)
            }
            .padding(.bottom, 2)

            if viewModel.failedItems.isEmpty {
                Text("暂无失败项")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.failedItems) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.fileName)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                Text(item.errorDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
