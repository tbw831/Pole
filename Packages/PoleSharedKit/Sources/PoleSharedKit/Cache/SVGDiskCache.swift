import Foundation

/// SVG 文件 disk cache。Round detail 顶部 banner SVG 反复访问时,
/// 第一次下载 + 存盘,第二次直接读 file:// URL,WKWebView 加载 < 50ms。
///
/// 用 `localFileURL(for:)` 拿本地 file:// URL:
/// - 本地缓存命中 → 直接返回
/// - 未命中 → 后台 fetch + 写盘,然后返回新的 file:// URL
///
/// 缓存目录:Caches/PoleSVG/<hash>.svg。系统自动 LRU 清理。
public actor SVGDiskCache {
    public static let shared = SVGDiskCache()

    private let cacheDir: URL
    private let session: URLSession

    private var writeCountSinceEvict = 0
    private let evictEvery = 50
    private let maxEntries = 200

    private init() {
        let baseCacheDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!
        self.cacheDir = baseCacheDir.appendingPathComponent("PoleSVG", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true
        )

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = false
        self.session = URLSession(configuration: config)
    }

    /// 拿到 SVG 的本地 file:// URL。
    /// - 远程 URL: download + cache + return file URL
    /// - 已是 file:// URL: 直接返回(主 app bundle 内的 SVG)
    public func localFileURL(for url: URL) async throws -> URL {
        if url.isFileURL {
            return url   // bundle 内 SVG 不需缓存
        }
        let cacheFile = cacheDir.appendingPathComponent(filename(for: url))
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            return cacheFile
        }
        let (data, _) = try await session.data(from: url)
        try data.write(to: cacheFile, options: .atomic)
        evictIfNeededOpportunistically()
        return cacheFile
    }

    /// 用 URL 的 djb2 hash 当文件名,避免特殊字符。
    private func filename(for url: URL) -> String {
        let key = url.absoluteString
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return String(format: "%016llx.svg", hash)
    }

    private func evictIfNeededOpportunistically() {
        writeCountSinceEvict += 1
        guard writeCountSinceEvict >= evictEvery else { return }
        writeCountSinceEvict = 0
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        guard entries.count > maxEntries else { return }
        let sorted = entries.compactMap { url -> (URL, Date)? in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return (url, date)
        }.sorted { $0.1 > $1.1 }  // newest first
        for (url, _) in sorted.dropFirst(maxEntries) {
            try? fm.removeItem(at: url)
        }
    }
}
