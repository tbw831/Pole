import Foundation

/// 一条新闻——跨 RSS 源统一 schema。
public nonisolated struct NewsItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String { url.absoluteString }
    public let title: String
    public let summary: String?
    public let url: URL
    public let publishedAt: Date?
    public let sourceName: String   // "crash.net" / "motorsport.com" / "F1官方" / "ZXMOTO"
    public let imageUrl: URL?

    public init(
        title: String,
        summary: String? = nil,
        url: URL,
        publishedAt: Date? = nil,
        sourceName: String,
        imageUrl: URL? = nil
    ) {
        self.title = title
        self.summary = summary
        self.url = url
        self.publishedAt = publishedAt
        self.sourceName = sourceName
        self.imageUrl = imageUrl
    }
}
