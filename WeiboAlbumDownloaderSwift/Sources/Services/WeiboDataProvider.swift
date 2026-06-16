import Foundation

// MARK: - 数据源 Protocol（策略模式）

/// 统一数据源协议：所有 4 种微博 API 的抽象接口
/// 每个 Provider 将各自 API 特有的响应格式转换为统一的 `FetchResult` 模型
/// 这是 C# 版架构重构的核心——C# 版在一个 1420 行的文件中用 if-else 处理 4 种数据源，
/// 此处用 Protocol + 4 个独立实现替代，新增数据源只需实现此协议
protocol WeiboDataProvider: Sendable {
    var sourceType: WeiboDataSource { get }

    /// 按页获取用户时间流（WeiboCnMobile/WeiboCn 使用）
    func fetchPage(
        uid: String,
        cookie: String,
        page: Int,
        sinceId: Int64,
        weiboComCookie: String?
    ) async throws -> FetchResult

    /// 获取用户的相册列表（WeiboCom1/WeiboCom2 使用）
    func fetchAlbums(uid: String, cookie: String) async throws -> AlbumFetchResult

    /// 获取指定相册内的照片列表（WeiboCom1/WeiboCom2 使用）
    func fetchAlbumPhotos(
        uid: String,
        cookie: String,
        album: AlbumInfo,
        page: Int,
        sinceId: Int64
    ) async throws -> FetchResult
}

/// 默认实现：时间流数据源不需要实现相册相关方法
extension WeiboDataProvider {
    func fetchAlbums(uid: String, cookie: String) async throws -> AlbumFetchResult {
        AlbumFetchResult(albums: [], user: nil)
    }

    func fetchAlbumPhotos(
        uid: String, cookie: String, album: AlbumInfo, page: Int, sinceId: Int64
    ) async throws -> FetchResult {
        FetchResult(posts: [], nextPage: nil, nextSinceId: nil, user: nil, hasMore: false)
    }
}

/// 工厂方法：根据数据源类型创建对应的 Provider 实例
func createProvider(for source: WeiboDataSource) -> WeiboDataProvider {
    switch source {
    case .weiboCnMobile: return WeiboCnMobileProvider()
    case .weiboCn:       return WeiboCnHtmlProvider()
    case .weiboCom1:     return WeiboComAlbumProvider()
    case .weiboCom2:     return WeiboComAjaxProvider()
    }
}
