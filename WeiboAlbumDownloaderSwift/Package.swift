// swift-tools-version: 5.9
// 微博相册下载器 - Swift macOS 版
// 最低支持 macOS 13 (Ventura)，使用 SwiftUI + async/await

import PackageDescription

let package = Package(
    name: "WeiboAlbumDownloader",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
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
