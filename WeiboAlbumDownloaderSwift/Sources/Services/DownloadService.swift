import Foundation

// MARK: - 媒体文件下载服务

/// 负责单个媒体文件的下载操作，包含跳过已存在文件、设置时间戳等逻辑
/// 方法均为无状态纯函数调用，无需 actor 串行化
struct DownloadService: Sendable {
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
        /// 下载字节数（用于速度统计），跳过/失败为 0
        let byteCount: Int64

        static func skipped(url: URL, destination: URL) -> DownloadResult {
            DownloadResult(url: url, destination: destination, skipped: true, error: nil, byteCount: 0)
        }

        static func success(url: URL, destination: URL, byteCount: Int64) -> DownloadResult {
            DownloadResult(url: url, destination: destination, skipped: false, error: nil, byteCount: byteCount)
        }

        static func failure(url: URL, destination: URL, error: Error) -> DownloadResult {
            DownloadResult(url: url, destination: destination, skipped: false, error: error, byteCount: 0)
        }
    }

    /// 下载单个媒体项到指定目标路径（是否跳过由调用方的目录缓存决定）
    /// - Parameters:
    ///   - url: 媒体下载地址
    ///   - destination: 目标文件完整路径
    ///   - date: 微博发布时间（用于设置文件时间戳）
    ///   - setTimestamp: 是否将文件时间设置为微博发布时间（WeiboCom2 数据源无发布时间，应为 false）
    func downloadMedia(
        url: URL,
        destination: URL,
        date: Date,
        setTimestamp: Bool
    ) async -> DownloadResult {
        do {
            let bytes = try await httpClient.downloadFile(url, to: destination)

            if setTimestamp {
                try? fileService.setFileTimestamp(destination, date: date)
            }

            return .success(url: url, destination: destination, byteCount: bytes)
        } catch {
            return .failure(url: url, destination: destination, error: error)
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
