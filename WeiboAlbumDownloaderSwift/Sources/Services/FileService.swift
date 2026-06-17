import Foundation

// MARK: - 文件管理服务

/// 负责下载目录管理、文件命名、去重、时间戳修改等磁盘操作
/// 对应 C# 版中分散在 MainWindow.xaml.cs 和 HttpHelper.cs 中的文件操作逻辑
struct FileService: Sendable {

    let baseDirectory: URL

    init(baseDirectory: URL = AppSettings.defaultDownloadDirectory) {
        self.baseDirectory = baseDirectory
    }

    /// 创建用户目录，格式：`昵称(UID)/` 或 `UID/`
    func userDirectory(uid: String, nickname: String?) -> URL {
        let folderName: String
        if let nickname, !nickname.isEmpty {
            folderName = "\(nickname)(\(uid))"
        } else {
            folderName = uid
        }
        let dir = baseDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 在用户目录下创建相册子目录（仅 WeiboCom1/WeiboCom2 数据源使用）
    func albumSubdirectory(userDir: URL, albumName: String) -> URL {
        let dir = userDir.appendingPathComponent(albumName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 将原始文件名清洗并截断为合法的磁盘文件名
    func cleanFileName(_ name: String) -> String {
        truncateFileName(sanitizeFileName(name), maxLength: 200)
    }

    /// 列出目录下所有文件名，用于建立"已下载"缓存集合，避免逐文件 syscall
    func existingFileNames(in directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names)
    }

    /// 将文件的创建时间和修改时间设置为微博发布时间
    /// 这是 C# 版的特色功能（SetFileTime），在 Finder 中按日期排序时可按发布顺序查看
    func setFileTimestamp(_ url: URL, date: Date) throws {
        try FileManager.default.setAttributes([
            .creationDate: date,
            .modificationDate: date,
        ], ofItemAtPath: url.path)

        // 通过 POSIX utimensat 同时设置 atime 和 mtime
        var times = [timespec](repeating: timespec(), count: 2)
        let epoch = Int(date.timeIntervalSince1970)
        times[0] = timespec(tv_sec: epoch, tv_nsec: 0)
        times[1] = timespec(tv_sec: epoch, tv_nsec: 0)
        utimensat(AT_FDCWD, url.path, &times, 0)
    }

    /// 在用户目录下创建一个以昵称命名的空标记文件，方便在文件管理器中识别用户
    func createNicknameMarker(in directory: URL, nickname: String) {
        let markerPath = directory.appendingPathComponent(nickname)
        if !FileManager.default.fileExists(atPath: markerPath.path) {
            FileManager.default.createFile(atPath: markerPath.path, contents: nil)
        }
    }

    // MARK: - 私有方法

    /// 移除文件名中的非法字符（适用于 macOS/Windows 通用）
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|\r\n")
        return name.components(separatedBy: invalidChars).joined()
    }

    /// 截断过长的文件名，保留扩展名
    private func truncateFileName(_ name: String, maxLength: Int) -> String {
        guard name.count > maxLength else { return name }
        let ext = (name as NSString).pathExtension
        let nameOnly = (name as NSString).deletingPathExtension
        let truncated = String(nameOnly.prefix(maxLength))
        return ext.isEmpty ? truncated : "\(truncated).\(ext)"
    }
}
