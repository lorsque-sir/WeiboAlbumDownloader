import SwiftUI
import AppKit

// MARK: - 应用入口

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationService.requestAuthorization()
    }
}

@main
struct WeiboAlbumDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var downloadVM = DownloadViewModel()

    private var windowTitle: String {
        if downloadVM.isDownloading {
            let p = downloadVM.progress
            let user = downloadVM.userInfo?.screenName ?? ""
            return "微博相册下载器 - \(user) 下载中 (\(p.total) 文件)"
        }
        return "微博相册下载器"
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(downloadVM)
                .frame(minWidth: 720, minHeight: 500)
                .navigationTitle(windowTitle)
                .onChange(of: downloadVM.progress.completed) { _, completed in
                    updateDockBadge(completed: completed, downloading: downloadVM.isDownloading)
                }
                .onChange(of: downloadVM.isDownloading) { _, downloading in
                    updateDockBadge(completed: downloadVM.progress.completed, downloading: downloading)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}

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

    private func updateDockBadge(completed: Int, downloading: Bool) {
        NSApp.dockTile.badgeLabel = (downloading && completed > 0) ? "\(completed)" : nil
    }
}
