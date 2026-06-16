import Foundation

// MARK: - 媒体文件下载服务

/// 负责单个媒体文件的下载操作，包含跳过已存在文件、设置时间戳等逻辑
/// 使用 actor 保证并发下载时的线程安全
actor DownloadService {
    private let httpClient = HTTPClient.shared
    private let fileService: FileService

    init(fileService: FileService) {
        self.fileService = fileService
    }

    /// 单次下载操作的结果
    struct DownloadResult: Sendable {
        let url: URL
        let destination: URL
        /// 文件已存在被跳过
        let skipped: Bool
        let error: Error?

        static func skipped(url: URL, destination: URL) -> DownloadResult {
            DownloadResult(url: url, destination: destination, skipped: true, error: nil)
        }

        static func success(url: URL, destination: URL) -> DownloadResult {
            DownloadResult(url: url, destination: destination, skipped: false, error: nil)
        }

        static func failure(url: URL, destination: URL, error: Error) -> DownloadResult {
            DownloadResult(url: url, destination: destination, skipped: false, error: error)
        }
    }

    /// 下载单个媒体项（图片/视频/LivePhoto）
    /// - Parameters:
    ///   - item: 媒体项信息
    ///   - post: 所属微博（用于生成文件名和设置时间戳）
    ///   - directory: 目标目录
    ///   - shortenName: 是否使用短文件名
    ///   - setTimestamp: 是否将文件时间设置为微博发布时间（WeiboCom2 数据源无发布时间，应为 false）
    func downloadMedia(
        item: MediaItem,
        post: WeiboPost,
        directory: URL,
        shortenName: Bool,
        setTimestamp: Bool = true
    ) async -> DownloadResult {
        let fileName = item.fileName(post: post, shortenName: shortenName)
        let destination = fileService.destinationURL(directory: directory, fileName: fileName)

        if fileService.fileExists(directory: directory, fileName: fileName) {
            return .skipped(url: item.url, destination: destination)
        }

        do {
            try await httpClient.downloadFile(item.url, to: destination)

            if setTimestamp {
                try fileService.setFileTimestamp(destination, date: post.createdAt)
            }

            return .success(url: item.url, destination: destination)
        } catch {
            return .failure(url: item.url, destination: destination, error: error)
        }
    }

    /// 下载用户头像到指定目录，已存在则跳过
    func downloadAvatar(url: URL, to directory: URL) async -> Bool {
        let fileName = url.lastPathComponent.components(separatedBy: "?").first ?? url.lastPathComponent
        let destination = directory.appendingPathComponent(fileName)

        guard !FileManager.default.fileExists(atPath: destination.path) else { return true }

        do {
            try await httpClient.downloadFile(url, to: destination)
            return true
        } catch {
            return false
        }
    }
}
