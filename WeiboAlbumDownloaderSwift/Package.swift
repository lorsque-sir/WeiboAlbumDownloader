// swift-tools-version: 6.2
// 微博相册下载器 - Swift macOS 版
// 要求 macOS 26+，Swift 6 语言模式（严格并发）+ SwiftUI Observation

import PackageDescription

let package = Package(
    name: "WeiboAlbumDownloader",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "WeiboAlbumDownloader",
            dependencies: ["SwiftSoup", "KeychainAccess"],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
