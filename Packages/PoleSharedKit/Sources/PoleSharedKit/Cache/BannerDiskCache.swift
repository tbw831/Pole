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
        self.session = URLSession(configuration: config)
    }

    /// 拿到本地 UIImage。命中缓存 < 50ms;未命中走 fetch + 写盘 + 解码。
    public func image(for url: URL) async throws -> UIImage? {
        let cacheFile = cacheDir.appendingPathComponent(filename(for: url))
        if let data = try? Data(contentsOf: cacheFile), let img = UIImage(data: data) {
            return img
        }
        let (data, _) = try await session.data(from: url)
        try? data.write(to: cacheFile)
        return UIImage(data: data)
    }

    private func filename(for url: URL) -> String {
        let key = url.absoluteString
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        let ext = (url.pathExtension.isEmpty ? "img" : url.pathExtension).lowercased()
        return String(format: "%016llx.%@", hash, ext as CVarArg)
    }
}
#endif
