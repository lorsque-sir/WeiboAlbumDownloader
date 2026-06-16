import SwiftUI

// MARK: - 主界面

/// 应用主界面，采用左右分栏布局：
/// - 左侧：用户信息面板（头像、昵称、操作按钮）
/// - 右侧：UID 输入栏 + 下载日志列表
struct MainView: View {
    @EnvironmentObject var viewModel: DownloadViewModel

    var body: some View {
        HSplitView {
            userInfoPanel
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

            VStack(spacing: 0) {
                controlBar
                    .padding()

                if viewModel.isDownloading || viewModel.progress.total > 0 {
                    progressPanel
                    Divider()
                }

                Divider()

                LogListView(messages: viewModel.messages)
            }
            .frame(minWidth: 500)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
                .frame(minWidth: 520, minHeight: 600)
        }
    }

    // MARK: - 用户信息面板

    private var userInfoPanel: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            // 头像（使用 AsyncImage 异步加载网络图片）
            if let avatarURL = viewModel.userInfo?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }

            // 昵称和 UID
            if let user = viewModel.userInfo {
                Text(user.screenName)
                    .font(.headline)
                    .lineLimit(1)
                Text("UID: \(user.uid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let desc = user.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            } else {
                Text("未连接")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("输入 UID 开始下载")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // 操作按钮区
            VStack(spacing: 8) {
                Button {
                    viewModel.batchDownload()
                } label: {
                    Label("批量下载", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(viewModel.isDownloading)

                Button {
                    viewModel.openDownloadFolder()
                } label: {
                    Label("打开下载目录", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    viewModel.showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
    }

    /// 默认头像占位图
    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 100, height: 100)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - 进度面板

    @State private var showFailedItems = false

    private var progressPanel: some View {
        HStack(spacing: 16) {
            if viewModel.isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)

                if viewModel.progress.currentPage > 0 {
                    Text("第 \(viewModel.progress.currentPage) 页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label("\(viewModel.progress.completed)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(viewModel.progress.skipped)", systemImage: "arrow.right.circle.fill")
                    .foregroundStyle(.orange)

                if viewModel.progress.failed > 0 {
                    Button {
                        showFailedItems = true
                    } label: {
                        Label("\(viewModel.progress.failed)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFailedItems) {
                        failedItemsPopover
                    }
                } else {
                    Label("0", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            Spacer()

            if !viewModel.isDownloading && viewModel.progress.total > 0 {
                Text(viewModel.progress.summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var failedItemsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("下载失败的文件")
                .font(.headline)
                .padding(.bottom, 4)

            if viewModel.failedItems.isEmpty {
                Text("暂无失败项")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.failedItems) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.fileName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(item.errorDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .frame(width: 350)
    }

    // MARK: - 控制栏

    private var controlBar: some View {
        HStack(spacing: 12) {
            TextField("输入微博 UID", text: $viewModel.uid)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.startDownload()
                }

            // 下载/停止按钮（下载中切换为红色停止按钮）
            Button(action: { viewModel.toggleDownload() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isDownloading ? "stop.fill" : "arrow.down.circle.fill")
                    Text(viewModel.isDownloading ? "停止" : "下载")
                }
                .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isDownloading ? .red : .accentColor)

            Button {
                viewModel.clearLog()
            } label: {
                Image(systemName: "trash")
            }
            .help("清空日志")
        }
    }
}
