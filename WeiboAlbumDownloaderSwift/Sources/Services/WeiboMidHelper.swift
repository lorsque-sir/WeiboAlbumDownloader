import Foundation

// MARK: - 超 9 图处理辅助

/// 处理微博超过 9 张图片的情况
/// m.weibo.cn API 的 pic_ids 字段在图片 > 9 张时只返回前 9 个 ID，
/// 需要通过微博状态详情接口获取完整的 pic_ids 列表
/// 对应 C# 版的 WeiboMidHelper.cs
enum WeiboMidHelper {
    private static let http = HTTPClient.shared

    /// 获取微博的完整图片 ID 列表
    /// 策略：先尝试 PC API（数据更完整），失败后降级到移动 API
    /// - Parameters:
    ///   - mid: 微博 ID
    ///   - cookie: weibo.com 域的 Cookie（PC API 需要）
    static func getImageIds(mid: String, cookie: String) async -> [String] {
        guard !mid.isEmpty else { return [] }

        if let ids = await tryPCAPI(mid: mid, cookie: cookie), !ids.isEmpty {
            return ids
        }

        if let ids = await tryMobileAPI(mid: mid, cookie: cookie), !ids.isEmpty {
            return ids
        }

        return []
    }

    /// 通过 weibo.com PC Ajax 接口获取完整 pic_ids
    private static func tryPCAPI(mid: String, cookie: String) async -> [String]? {
        let urlStr = "https://weibo.com/ajax/statuses/show?id=\(mid)&locale=zh-CN&isGetLongText=true"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboStatusShowResponse.self)
            let ids = response.allPicIds
            return ids.isEmpty ? nil : ids
        } catch {
            return nil
        }
    }

    /// 通过 m.weibo.cn 移动接口获取（备用方案）
    private static func tryMobileAPI(mid: String, cookie: String) async -> [String]? {
        let urlStr = "https://m.weibo.cn/statuses/show?id=\(mid)"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            let response = try await http.fetchJSON(url, cookie: cookie, type: WeiboStatusShowResponse.self)
            let ids = response.allPicIds
            return ids.isEmpty ? nil : ids
        } catch {
            return nil
        }
    }
}
