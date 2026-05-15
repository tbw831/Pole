import Foundation
#if canImport(UIKit)
import UIKit

/// 通用图片 disk cache(banner / artwork 等)。
/// 第一次 fetch + 写盘,后续直接读 file:// URL → UIImage。
/// 缓存目录:Caches/PoleBanners/<hash>.<ext>。系统按需 LRU 清理。
public actor BannerDiskCache {
    public static let shared = BannerDiskCache()

    private let cacheDir: URL
    private let session: URLSession

    private var writeCountSinceEvict = 0
    private let evictEvery = 50
    private let maxEntries = 200

    private init() {
        let baseCacheDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!
        self.cacheDir = baseCacheDir.appendingPathComponent("PoleBanners", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true
        )

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = false
        self.session = URLSession(configuration: config)
    }

    /// 拿到本地 UIImage。命中缓存 < 50ms;未命中走 fetch + 写盘 + 解码。
    public func image(for url: URL) async throws -> UIImage? {
        let cacheFile = cacheDir.appendingPathComponent(filename(for: url))
        if let data = try? Data(contentsOf: cacheFile), let img = UIImage(data: data) {
            return img
        }
        let (data, _) = try await session.data(from: url)
        do {
            try data.write(to: cacheFile, options: .atomic)
            evictIfNeededOpportunistically()
        } catch {
            // 写盘失败不影响返回的 image
        }
        return UIImage(data: data)
    }

    private func filename(for url: URL) -> String {
        let key = url.absoluteString
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let ext = (url.pathExtension.isEmpty ? "img" : url.pathExtension).lowercased()
        return String(format: "%016llx.%@", hash, ext as CVarArg)
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
#endif
