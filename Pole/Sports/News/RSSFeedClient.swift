import Foundation
import PoleDomain

public enum RSSError: Error, LocalizedError {
    case invalidResponse(Int)
    case network(Error)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return "RSS HTTP \(code)"
        case .network(let err):          return L10n.t(zh: "RSS 网络异常:\(err.localizedDescription)", en: "RSS network error: \(err.localizedDescription)")
        case .decoding(let msg):         return L10n.t(zh: "RSS 解析失败:\(msg)", en: "RSS decode failed: \(msg)")
        }
    }
}

/// 通用 RSS 2.0 feed 客户端——用 NSRegularExpression 解析 `<item>` 块,不依赖 XMLParser delegate。
/// 字段:title / link / pubDate / description,CDATA 自动剥离。
public actor RSSFeedClient {
    public static let shared = RSSFeedClient()
    private let session: URLSession

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
    }

    public func fetch(url: URL, sourceName: String) async throws -> [NewsItem] {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/rss+xml,application/xml,*/*", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RSSError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RSSError.invalidResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RSSError.invalidResponse(http.statusCode)
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw RSSError.decoding("非 UTF-8")
        }
        return Self.parseRSS(xml: xml, sourceName: sourceName)
    }

    // MARK: - Parsing

    private nonisolated static func parseRSS(xml: String, sourceName: String) -> [NewsItem] {
        guard let itemRegex = try? NSRegularExpression(pattern: #"<item[^>]*>([\s\S]*?)</item>"#) else { return [] }
        let nsXml = xml as NSString
        let allRange = NSRange(location: 0, length: nsXml.length)
        let matches = itemRegex.matches(in: xml, range: allRange)

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)   // RFC822 zzz token 跨 locale 行为不一致,显式设 GMT 避免 publishedAt 漂移

        return matches.compactMap { m -> NewsItem? in
            guard m.numberOfRanges == 2 else { return nil }
            let inner = nsXml.substring(with: m.range(at: 1))
            return parseItem(inner: inner, sourceName: sourceName, dateFormatter: formatter)
        }
    }

    private nonisolated static func parseItem(inner: String, sourceName: String, dateFormatter: DateFormatter) -> NewsItem? {
        guard let title = extractTag("title", in: inner) else { return nil }
        guard let linkRaw = extractTag("link", in: inner),
              let url = URL(string: linkRaw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }

        let summary = extractTag("description", in: inner)
        let pubDateStr = extractTag("pubDate", in: inner)
        let publishedAt = pubDateStr.flatMap { dateFormatter.date(from: $0) }

        // <enclosure url="..." type="image/jpeg"/> 或 <media:content url="..."/>
        var imageUrl: URL? = nil
        if let r = try? NSRegularExpression(pattern: #"<(?:enclosure|media:content|media:thumbnail)\s+[^>]*url="([^"]+)""#) {
            let nsInner = inner as NSString
            if let m = r.firstMatch(in: inner, range: NSRange(location: 0, length: nsInner.length)),
               m.numberOfRanges == 2 {
                imageUrl = URL(string: nsInner.substring(with: m.range(at: 1)))
            }
        }

        return NewsItem(
            title: cleanText(title),
            summary: summary.map { cleanText($0) },
            url: url,
            publishedAt: publishedAt,
            sourceName: sourceName,
            imageUrl: imageUrl
        )
    }

    private nonisolated static func extractTag(_ tag: String, in xml: String) -> String? {
        let pattern = "<\(tag)(?:\\s[^>]*)?>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsXml = xml as NSString
        guard let m = regex.firstMatch(in: xml, range: NSRange(location: 0, length: nsXml.length)),
              m.numberOfRanges == 2 else { return nil }
        var value = nsXml.substring(with: m.range(at: 1))
        // 剥 CDATA <![CDATA[...]]>
        if value.hasPrefix("<![CDATA[") && value.hasSuffix("]]>") {
            value = String(value.dropFirst(9).dropLast(3))
        }
        return value
    }

    /// 剥 HTML tags + decode 常见 entity。新闻 description 经常含 <p>/<a> markup。
    private nonisolated static func cleanText(_ raw: String) -> String {
        var s = raw
        // 去 HTML tags
        if let r = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            s = r.stringByReplacingMatches(
                in: s,
                range: NSRange(location: 0, length: (s as NSString).length),
                withTemplate: ""
            )
        }
        // decode 常见 entity
        s = s
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&apos;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
