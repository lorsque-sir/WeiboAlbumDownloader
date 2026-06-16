// swift-tools-version: 5.9
// 微博相册下载器 - Swift macOS 版
// 最低支持 macOS 13 (Ventura)，使用 SwiftUI + async/await

import PackageDescription

let package = Package(
    name: "WeiboAlbumDownloader",
    platforms: [.macOS(.v13)],
    dependencies: [
        // HTML 解析库，用于 weibo.cn 数据源的网页内容提取
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        // macOS Keychain 封装，用于安全存储 Cookie（替代 C# 版的明文 JSON 存储）
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "WeiboAlbumDownloader",
            dependencies: ["SwiftSoup", "KeychainAccess"],
            path: "Sources"
        ),
    ]
)
