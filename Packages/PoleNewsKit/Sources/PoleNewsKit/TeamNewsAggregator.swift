import Foundation
import PoleDomain

/// 内置 RSS 源——按 series 分组,每个源有 sourceName(UI 显示)。
public nonisolated enum NewsSources {
    public struct Source: Sendable {
        public let url: URL
        public let name: String
    }

    public static let f1: [Source] = [
        Source(url: URL(string: "https://www.formula1.com/en/latest/all.xml")!, name: "F1官方"),
        Source(url: URL(string: "https://www.crash.net/rss/f1")!, name: "Crash.net"),
        Source(url: URL(string: "https://www.motorsport.com/rss/f1/news/")!, name: "Motorsport.com"),
    ]

    public static let motogp: [Source] = [
        Source(url: URL(string: "https://www.crash.net/rss/motogp")!, name: "Crash.net"),
        Source(url: URL(string: "https://www.motorsport.com/rss/motogp/news/")!, name: "Motorsport.com"),
    ]

    public static let wsbk: [Source] = [
        Source(url: URL(string: "https://www.crash.net/rss/wsbk")!, name: "Crash.net"),
        Source(url: URL(string: "https://www.motorsport.com/rss/wsbk/news/")!, name: "Motorsport.com"),
    ]
}

/// 多源 RSS 聚合 + keyword 过滤——给定 series 和 keywords,并发拉所有源,过滤含任一 keyword 的 item。
public actor TeamNewsAggregator {
    public static let shared = TeamNewsAggregator()

    /// 仅按 series 拉聚合 feed(不过滤),用于 series 顶层"新闻"页。
    public func fetchAll(series: MotorsportSeries) async -> [NewsItem] {
        let sources = sources(for: series)
        return await fetchSources(sources)
    }

    /// 按 series + keywords 过滤——车队/厂商详情页用。
    /// keywords 中英文混合,case insensitive 匹配 title + summary。
    public func fetchTeamNews(series: MotorsportSeries, keywords: [String]) async -> [NewsItem] {
        let all = await fetchAll(series: series)
        let lcKeywords = keywords.map { $0.lowercased() }
        return all.filter { item in
            let haystack = (item.title + " " + (item.summary ?? "")).lowercased()
            return lcKeywords.contains { haystack.contains($0) }
        }
    }

    // MARK: Private

    private func sources(for series: MotorsportSeries) -> [NewsSources.Source] {
        switch series {
        case .f1:     return NewsSources.f1
        case .motogp: return NewsSources.motogp
        case .wssp:   return NewsSources.wsbk
        case .fe:     return []   // 暂未配 RSS 源
        }
    }

    private func fetchSources(_ sources: [NewsSources.Source]) async -> [NewsItem] {
        await withTaskGroup(of: [NewsItem].self) { group in
            for src in sources {
                group.addTask {
                    (try? await RSSFeedClient.shared.fetch(url: src.url, sourceName: src.name)) ?? []
                }
            }
            var all: [NewsItem] = []
            for await items in group {
                all.append(contentsOf: items)
            }
            // 去重:同 URL 算同一条
            var seen: Set<String> = []
            let unique = all.filter { seen.insert($0.id).inserted }
            // 最新在前
            return unique.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        }
    }
}
