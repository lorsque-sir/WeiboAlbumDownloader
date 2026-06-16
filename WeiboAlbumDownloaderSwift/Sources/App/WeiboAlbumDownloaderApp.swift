import SwiftUI

// MARK: - 应用入口

/// 微博相册下载器 macOS 应用入口
/// 使用 SwiftUI App 生命周期，注册主窗口和菜单栏快捷键
@main
struct WeiboAlbumDownloaderApp: App {
    @StateObject private var downloadVM = DownloadViewModel()

    private var windowTitle: String {
        if downloadVM.isDownloading {
            let p = downloadVM.progress
            let user = downloadVM.userInfo?.screenName ?? ""
            return "微博相册下载器 - \(user) 下载中 (\(p.completed + p.skipped + p.failed) 文件)"
        }
        return "微博相册下载器"
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(downloadVM)
                .frame(minWidth: 720, minHeight: 500)
                .navigationTitle(windowTitle)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            // 移除默认的"新建窗口"菜单项（单窗口应用不需要）
            CommandGroup(replacing: .newItem) {}

            // 自定义"下载"菜单
            CommandMenu("下载") {
                Button("开始/停止下载") {
                    downloadVM.toggleDownload()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("批量下载") {
                    downloadVM.batchDownload()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button("打开下载目录") {
                    downloadVM.openDownloadFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
