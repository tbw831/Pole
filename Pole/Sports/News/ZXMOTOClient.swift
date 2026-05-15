import Foundation
import PoleDomain

/// ZXMOTO(张雪机车)中文官网 news 适配器。
/// 端点返回 `{ code, msg, data }`,**msg 字段是 HTML `<li>` 列表**(不是结构化 JSON),
/// 我们 regex 解析 li 里的 href/img/title/date。
public actor ZXMOTOClient {
    public static let shared = ZXMOTOClient()
    private let session: URLSession
    private let baseURL = URL(string: "https://www.zxmoto.com")!

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
    }

    /// 抓 catid=3(WSBK 张雪赛事动态)新闻 list。
    /// page 默认 1,首页一般 8-10 条最新。
    public func fetchNews(page: Int = 1) async throws -> [NewsItem] {
        let url = URL(string: "https://www.zxmoto.com/index.php?s=api&c=api&m=template&name=list_data.html&module=news&catid=3&format=json&page=\(page)")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RSSError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(WrapperDTO.self, from: data)
        // 后端 code != 0 时 msg 不是 HTML 而是 error string,老逻辑直接当 HTML 解析返空数组无信号。
        guard decoded.code == 0 else {
            throw RSSError.decoding("ZXMOTO API code=\(decoded.code) msg=\(decoded.msg.prefix(80))")
        }
        return Self.parseLI(html: decoded.msg, baseURL: baseURL)
    }

    private struct WrapperDTO: Sendable, nonisolated Decodable {
        let code: Int
        let msg: String
    }

    private nonisolated static func parseLI(html: String, baseURL: URL) -> [NewsItem] {
        // 每个 li 块:含 href / img / title / date
        guard let liRegex = try? NSRegularExpression(pattern: #"<li>([\s\S]*?)</li>"#) else { return [] }
        let nsHtml = html as NSString
        let allRange = NSRange(location: 0, length: nsHtml.length)
        let matches = liRegex.matches(in: html, range: allRange)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")

        return matches.compactMap { m -> NewsItem? in
            guard m.numberOfRanges == 2 else { return nil }
            let inner = nsHtml.substring(with: m.range(at: 1))

            guard let href = firstCapture(inner, pattern: #"href="([^"]*c=show[^"]*)""#) else { return nil }
            // 标题在 <h3><a href=...>标题</a></h3>
            guard let title = firstCapture(inner, pattern: #"<h3>\s*<a[^>]*>([^<]+)</a>"#) else { return nil }

            let imgPath = firstCapture(inner, pattern: #"<img[^>]*src="([^"]+)""#)
            let dateStr = firstCapture(inner, pattern: #"<span>([\d\-]+)</span>"#)

            // href / img path 是相对路径,拼绝对 URL
            let absoluteURL = URL(string: href, relativeTo: baseURL)?.absoluteURL
                ?? URL(string: "https://www.zxmoto.com\(href)")
            let imgURL: URL? = imgPath.flatMap { p in
                URL(string: p, relativeTo: baseURL)?.absoluteURL
                    ?? URL(string: "https://www.zxmoto.com\(p)")
            }
            let date = dateStr.flatMap { dateFormatter.date(from: $0) }

            guard let absoluteURL else { return nil }
            return NewsItem(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: nil,
                url: absoluteURL,
                publishedAt: date,
                sourceName: "ZXMOTO 官网",
                imageUrl: imgURL
            )
        }
    }

    private nonisolated static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              m.numberOfRanges >= 2 else { return nil }
        return nsText.substring(with: m.range(at: 1))
    }
}
