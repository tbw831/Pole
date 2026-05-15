import Foundation

/// 全局共享 URLSession,带 disk URLCache。
///
/// 为什么不用 `URLSession.shared`:
/// - `URLSession.shared.configuration` 是只读的,无法注入自定义 URLCache
/// - 默认 `.shared` 用 `URLCache.shared`,memory 4MB / disk 20MB,对赛车 / 新闻 / SVG 不够
///
/// 客户端可选择走此 session(默认)或显式传 `.shared`(测试用)。
public nonisolated enum SharedURLSession {
    /// 50MB 内存 + 200MB 磁盘的 URLCache,对反复进入 race detail / standings / SVG 命中率高。
    public static let cached: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,    // 50MB RAM
            diskCapacity: 200 * 1024 * 1024,     // 200MB disk
            diskPath: "pole-url-cache"
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Pole iOS)"]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        // 不让 cookies 跟到 share extension / 其它 app
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()
}
