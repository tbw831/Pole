import Foundation
import PDFKit
import os
import PoleDomain

nonisolated fileprivate let wsbkLog = Logger(subsystem: "com.tiebowen.Pole", category: "WSBKClient")

// MARK: - Errors

public enum WSBKError: Error, LocalizedError {
    case invalidResponse(Int)
    case decoding(String)
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return L10n.t(zh: "WSBK 服务器返回 HTTP \(code)", en: "WSBK server HTTP \(code)")
        case .decoding(let msg):         return L10n.t(zh: "WSBK 解析失败:\(msg)", en: "WSBK decode failed: \(msg)")
        case .network(let err):          return L10n.t(zh: "WSBK 网络异常:\(err.localizedDescription)", en: "WSBK network error: \(err.localizedDescription)")
        }
    }
}

// MARK: - Client

/// WorldSBK 数据客户端——worldsbk.com 是传统 SSR 站,无公开 JSON API,
/// 直接抓 /en/calendar 和 /en/event/{cc}/{year} 的 HTML 解析。
/// 仅自用,HTML 结构稳定;若官方改版需要同步更新正则。
public actor WSBKClient {
    public static let shared = WSBKClient()

    private let session: URLSession

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
    }

    // MARK: - Cache 层(避免 Timeline + RaceList + Standings + AI agent 各拉一份重复 HTML 解析)
    //
    // WSBK 是 HTML 抓取 + 字符级 bounds 重组 PDF,fetch 成本最高的 client,缓存收益最大。

    private let roundsCache         = SeasonCache<[WSBKRound]>(ttl: 3600)               // 赛历 1h
    private let sspStandingsCache   = SeasonCache<[WSSPRiderStanding]>(ttl: 300)        // 车手榜 5min
    /// PDF 解析结果按 URL 缓存(已结束赛果不会变)。Standings 进入即触发 12 round × ~1.5 race
    /// = 18 次 HTTP + PDFKit 字符级 bounds 重组,首次 5–10s,无缓存每次重跑。
    private let pdfResultsCache     = SeasonCache<[WSSPRaceResult]>(ttl: 24 * 3600)     // 24h
    /// `fetchSSPRiderWins` 聚合结果(整季胜场数 map),整体也缓存避免每次重新遍历。
    private let winsCache           = SeasonCache<[String: Int]>(ttl: 1800)             // 30min

    // MARK: Public API

    /// 当年所有 round。
    public func fetchSeasonRounds() async throws -> [WSBKRound] {
        try await roundsCache.fetchOr(key: "current") {
            let url = URL(string: "https://www.worldsbk.com/en/calendar")!
            let html = try await self.fetchHTML(url: url)
            let rounds = Self.parseCalendar(html: html)
            if rounds.isEmpty {
                throw WSBKError.decoding("赛历解析为空(HTML \(html.count) 字符)")
            }
            // WSBK 年度通常 12-13 round;< 8 强烈暗示 worldsbk.com markup 改了我们 selector 失效。
            // 不抛错(让用户至少看到部分数据),但 log warning 让 Console 能定位问题。
            if rounds.count < 8 {
                wsbkLog.warning("parseCalendar parsed=\(rounds.count) expected≥12 — markup 可能变化")
            }
            return rounds
        }
    }

    /// 单 round 周末完整 sessions(只取 WorldSSP 中量级,过滤掉 WorldSBK 主组 / WorldSSP300)。
    /// 返回 `WSSPSessionWithResults` 而非裸 `Session`,带上 worldsbk 官方 Results.pdf 链接(已结束的 session 才有)。
    public func fetchEventSessions(countryCode: String, year: String) async throws -> [WSSPSessionWithResults] {
        let url = URL(string: "https://www.worldsbk.com/en/event/\(countryCode)/\(year)")!
        let html = try await fetchHTML(url: url)
        return Self.parseSessions(html: html, eventId: "wssp-\(year)-\(countryCode)")
    }

    /// 下载 WSSP 单场 Results PDF 原始 Data(用于 PDFView inline 渲染备用)。
    public func fetchSSPSessionPDFData(pdfURL: URL) async throws -> Data {
        do {
            let (data, _) = try await session.data(from: pdfURL)
            return data
        } catch {
            throw WSBKError.network(error)
        }
    }

    /// 解析 WSSP 单场 Results PDF 成结构化 timing rows。
    /// PDFKit `.string` 在 worldsbk PDF 上按列重排无法用,改成"字符级 bounds + (x,y) 重组行":
    ///   1. 遍历 PDFPage 每个字符 + 取它的 CGRect
    ///   2. 按 y 坐标 group 成 visual 行(同行 y 容差 2pt)
    ///   3. 行内按 x 排序,大间距(>5pt)处加空格
    ///   4. 每行用正则提 position / number / name / nat / team / time / gap / laps
    public func fetchSSPSessionResults(pdfURL: URL) async throws -> [WSSPRaceResult] {
        try await pdfResultsCache.fetchOr(key: pdfURL.absoluteString) {
            try await self._fetchSSPSessionResultsImpl(pdfURL: pdfURL)
        }
    }

    private func _fetchSSPSessionResultsImpl(pdfURL: URL) async throws -> [WSSPRaceResult] {
        let data: Data
        do {
            (data, _) = try await session.data(from: pdfURL)
        } catch {
            throw WSBKError.network(error)
        }
        guard let doc = PDFDocument(data: data) else {
            throw WSBKError.decoding("PDF 加载失败")
        }
        var visualLines: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            visualLines.append(contentsOf: Self.extractVisualRows(page: page))
        }
        let rows = Self.parseVisualLines(visualLines)
        if rows.isEmpty {
            // 找含 "MASIA" / "FERRARI" / "ONCU" 任一关键词的行,以及它们前后几行
            var hits: [String] = []
            for (i, line) in visualLines.enumerated() {
                if line.contains("MASIA") || line.contains("FERRARI") || line.contains("ONCU") {
                    let from = max(0, i - 1)
                    let to = min(visualLines.count - 1, i + 2)
                    for j in from...to {
                        hits.append("L\(j):\(visualLines[j])")
                    }
                    break  // 只 dump 第一个命中周围
                }
            }
            let sample = hits.isEmpty ? visualLines.prefix(5).joined(separator: " // ") : hits.joined(separator: " // ")
            throw WSBKError.decoding("PDF \(visualLines.count) 行: \(sample.prefix(400))")
        }
        return rows
    }

    /// 客户端聚合车手胜场数——遍历整年已结束 round,对每个 race(含 Race 1/Race 2)PDF
    /// 解析 first place 累加。**key 用 rider lastname**(PDF "J. MASIA" 跟 standings "JAUME MASIA"
    /// 用 last word 对齐;不能直接 fullName 匹配)。
    /// 性能:12 round × 平均 1.5 race × 1 PDF ≈ 18 个 HTTP+解析,首次 5-10s。
    public func fetchSSPRiderWins() async -> [String: Int] {
        // 整季胜场聚合也缓存 30min,避免 Standings 反复进入 → 反复跑 12 round × ~1.5 race 遍历
        // (单 PDF 已被 pdfResultsCache 兜底,但聚合本身的字典构造也要避免)。
        if let cached = try? await winsCache.fetchOr(key: "current", {
            guard let rounds = try? await self.fetchSeasonRounds() else { return [:] }
            return await self.aggregateWins(rounds: rounds)
        }) {
            return cached
        }
        return [:]
    }

    private func aggregateWins(rounds: [WSBKRound]) async -> [String: Int] {
        var wins: [String: Int] = [:]
        let finished = rounds.filter { $0.currentStatus == .finished }
        for round in finished {
            guard let items = try? await fetchEventSessions(
                countryCode: round.countryCode,
                year: round.season
            ) else { continue }
            let races = items.filter { item in
                let kind = item.session.kind
                return (kind == .race || kind == .superpoleRace) && item.resultsPdfURL != nil
            }
            for race in races {
                guard let url = race.resultsPdfURL else { continue }
                guard let rows = try? await fetchSSPSessionResults(pdfURL: url) else { continue }
                if let winner = rows.first(where: { $0.position == 1 }) {
                    wins[winner.lastName.uppercased(), default: 0] += 1
                }
            }
        }
        return wins
    }

    /// 单 rider 整季 round-by-round 积分(给积分趋势图用)。
    /// `riderLastName` 是该 rider 姓的大写形式("MASIA" / "BAYLISS" / "ZHANG" 等)。
    public func fetchSSPRiderRoundPoints(riderLastName: String) async -> [WSSPRiderRoundPoints] {
        let upperLast = riderLastName.uppercased()
        guard let rounds = try? await fetchSeasonRounds() else { return [] }
        let finished = rounds.filter { $0.currentStatus == .finished }
            .sorted { $0.round < $1.round }
        var result: [WSSPRiderRoundPoints] = []
        for round in finished {
            guard let items = try? await fetchEventSessions(
                countryCode: round.countryCode,
                year: round.season
            ) else { continue }
            // race / superpoleRace 都视作"正赛"
            let races = items
                .filter { ($0.session.kind == .race || $0.session.kind == .superpoleRace)
                          && $0.resultsPdfURL != nil }
                .sorted { $0.session.startTime < $1.session.startTime }
            var r1 = 0.0
            var r2 = 0.0
            for (idx, race) in races.enumerated() {
                guard let url = race.resultsPdfURL,
                      let rows = try? await fetchSSPSessionResults(pdfURL: url) else { continue }
                guard let row = rows.first(where: { $0.lastName.uppercased() == upperLast }) else { continue }
                let pts = Self.sspRacePoints(forPosition: row.position)
                if idx == 0 { r1 = pts } else if idx == 1 { r2 = pts }
            }
            result.append(WSSPRiderRoundPoints(
                round: round.round,
                roundName: round.name,
                race1Points: r1,
                race2Points: r2
            ))
        }
        return result
    }

    /// WSSP 正赛标准积分表(15 名进分,1st = 25 分)。
    private nonisolated static func sspRacePoints(forPosition position: Int) -> Double {
        let table = [25.0, 20, 16, 13, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
        guard position >= 1, position <= table.count else { return 0 }
        return table[position - 1]
    }

    /// WSSP 厂商榜——抓 results statistics 页面的 #champ-manufacturer-standing-ssp 块。
    public func fetchSSPBuilderStandings() async throws -> [WSSPBuilderStanding] {
        let url = URL(string: "https://www.worldsbk.com/en/results%20statistics")!
        let html = try await fetchHTML(url: url)
        let rows = Self.parseSSPBuilderStandings(html: html)
        if rows.isEmpty {
            throw WSBKError.decoding("WSSP 厂商榜解析为空(HTML \(html.count) 字符)")
        }
        return rows
    }

    /// WSSP 车手榜——抓 results statistics 页面的 #champ-standing-ssp 块(23 名 rider)。
    public func fetchSSPRiderStandings() async throws -> [WSSPRiderStanding] {
        try await sspStandingsCache.fetchOr(key: "current") {
            try await self._fetchSSPRiderStandingsImpl()
        }
    }

    private func _fetchSSPRiderStandingsImpl() async throws -> [WSSPRiderStanding] {
        // URL 带空格,Foundation 会自动 percent-encode
        let url = URL(string: "https://www.worldsbk.com/en/results%20statistics")!
        let html = try await fetchHTML(url: url)
        let rows = Self.parseSSPStandings(html: html)
        if rows.isEmpty {
            // 诊断:看是哪步漏
            let hasSSPAnchor = html.contains("champ-standing-ssp")
            let hasRanking = html.contains("rider-ranking")
            let olCount = html.components(separatedBy: "<ol class=rider-ranking").count - 1
            // 如果都有但 parser 漏,dump ssp 块前 300 字
            var snippet = ""
            if hasSSPAnchor, let r = html.range(of: "champ-standing-ssp") {
                let s = r.upperBound
                let e = html.index(s, offsetBy: 400, limitedBy: html.endIndex) ?? html.endIndex
                snippet = String(html[s..<e]).replacingOccurrences(of: "\n", with: " ")
            }
            throw WSBKError.decoding(
                "WSSP 空 [HTML=\(html.count) ssp=\(hasSSPAnchor) ranking=\(hasRanking) ol=\(olCount)] snippet: \(snippet)"
            )
        }
        // WSSP grid 通常 23 名 rider;< 15 暗示部分匹配丢失(可能 markup 改了某个字段位置)。
        if rows.count < 15 {
            wsbkLog.warning("parseSSPStandings parsed=\(rows.count) expected≥23 — markup 可能变化")
        }
        return rows
    }

    // MARK: HTTP

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        // worldsbk.com 按 UA 区分桌面/移动响应:
        //   iPhone UA → 给精简版 <li><a>名字</a></li>(无日期/round 数,无法用)
        //   桌面 UA   → 给完整 calendar-round-item 富 markup
        // 用桌面 Safari UA 拿富 markup。
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WSBKError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WSBKError.invalidResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WSBKError.invalidResponse(http.statusCode)
        }
        guard let str = String(data: data, encoding: .utf8) else {
            throw WSBKError.decoding("HTML 不是 UTF-8")
        }
        return str
    }

    // MARK: HTML parsing (nonisolated 静态方法,actor 内 sync 调用)

    private nonisolated static func parseCalendar(html: String) -> [WSBKRound] {
        // NSRegularExpression 在大 HTML 上对 .*? 长跨度回溯会 catastrophic backtrack 返 0 matches。
        // 改成两步:先用紧 anchor 找出所有"卡片入口"位置,再在每个小卡片片段里跑简单正则。
        // worldsbk 的 HTML 不规范:`<a` 和 `href` 之间有多个空格,attr 引号有时省略,
        // 链接绝对/相对都可能。所有正则都用 \s+ / 引号可选来兼容。
        let anchorPattern = #"<a\s+href=["'](?:https?://[^/]+)?/en/event/([A-Z]+)/(\d+)["']"#
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern),
              let roundRegex = try? NSRegularExpression(pattern: #"Round-(\d+)"#),
              let nameRegex  = try? NSRegularExpression(pattern: #"<h2[^>]*>([^<]+)</h2>"#),
              let dateRegex  = try? NSRegularExpression(pattern: #"<span\s+class=["']?date["']?[^>]*>([^<]+)</span>"#),
              let svgRegex   = try? NSRegularExpression(pattern: #"circuit_tracks_(\w+)\.svg"#)
        else { return [] }

        let nsRange = NSRange(html.startIndex..., in: html)
        let anchors = anchorRegex.matches(in: html, options: [], range: nsRange)
        let now = Date()
        let totalLength = (html as NSString).length

        var results: [WSBKRound] = []
        for (i, anchor) in anchors.enumerated() {
            guard anchor.numberOfRanges == 3,
                  let cc = stringRange(anchor, 1, in: html),
                  let yearStr = stringRange(anchor, 2, in: html),
                  let year = Int(yearStr) else { continue }

            // 卡片内容范围:从这个 anchor 之后到下一个 anchor 之前(末卡到 EOF)
            let segmentStart = anchor.range.location + anchor.range.length
            let segmentEnd = (i + 1 < anchors.count) ? anchors[i + 1].range.location : totalLength
            guard segmentEnd > segmentStart else { continue }
            let cardRange = NSRange(location: segmentStart, length: segmentEnd - segmentStart)

            guard let roundStr = firstCapture(html, roundRegex, cardRange, 1),
                  let round = Int(roundStr),
                  let nameRaw = firstCapture(html, nameRegex, cardRange, 1),
                  let dateText = firstCapture(html, dateRegex, cardRange, 1)
            else { continue }

            let name = nameRaw.trimmingCharacters(in: .whitespaces)
            guard let (start, end) = parseDateRange(dateText, year: year) else { continue }

            let status: EventStatus = {
                if end < now { return .finished }
                if start <= now && now <= end { return .live }
                return .upcoming
            }()

            let circuit = Circuit(id: cc.lowercased(), name: name, locality: "", country: cc)

            // SVG 文件名(如 PHILL/PORTI/BALAT)在卡片内部 img tag 里,跟 country code 不同
            let svgURL: URL? = firstCapture(html, svgRegex, cardRange, 1).flatMap { code in
                URL(string: "https://www.worldsbk.com/themes/responsive/static/img/event/tracks/circuit_tracks_\(code).svg")
            }

            results.append(WSBKRound(
                id: "wssp-\(year)-\(cc)",
                leagueId: "wssp-\(year)",
                season: yearStr,
                round: round,
                countryCode: cc,
                name: name,
                dateRangeText: dateText,
                circuit: circuit,
                dateStart: start,
                dateEnd: end,
                sessions: [],
                status: status,
                circuitMapImageURL: svgURL
            ))
        }
        return results
    }

    private nonisolated static func firstCapture(_ text: String, _ regex: NSRegularExpression, _ range: NSRange, _ group: Int) -> String? {
        guard let m = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return stringRange(m, group, in: text)
    }

    private nonisolated static func parseSessions(html: String, eventId: String) -> [WSSPSessionWithResults] {
        // worldsbk 的 schedule HTML 周五/六 vs 周日格式不一致:
        //   已发生 session:  <div data_ini="..."></div> ... text</div>
        //   未发生 session:  <div data_ini='...'></div> ... text<span class='ico video'>Live Video</span></div>
        // 单大正则套不住两种,改成"先 anchor 找 timeIso 块,再在小块里提字段",每个小 regex 都接受单/双引号。
        guard let anchorRegex = try? NSRegularExpression(pattern: #"timeIso[^"']*["']?\s*>"#),
              let iniRegex    = try? NSRegularExpression(pattern: #"data_ini=["']([^"']+)["']"#),
              let catRegex    = try? NSRegularExpression(pattern: #"cat-session end (\w+)["']?[^>]*>\s*([^<]+?)\s*(?:<|$)"#),
              let pdfRegex    = try? NSRegularExpression(pattern: #"href=["'](https?://[^"']*/SSP/[^"']*Results\.pdf[^"']*)["']"#)
        else { return [] }

        let nsRange = NSRange(html.startIndex..., in: html)
        let anchors = anchorRegex.matches(in: html, options: [], range: nsRange)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let totalLength = (html as NSString).length

        var sessions: [WSSPSessionWithResults] = []
        for (i, anchor) in anchors.enumerated() {
            let segStart = anchor.range.location + anchor.range.length
            let segEnd = (i + 1 < anchors.count) ? anchors[i + 1].range.location : totalLength
            guard segEnd > segStart else { continue }
            let segRange = NSRange(location: segStart, length: segEnd - segStart)

            guard let iniStr = firstCapture(html, iniRegex, segRange, 1),
                  let startTime = formatter.date(from: iniStr) else { continue }

            // cat + text 在同一个 cat-session 块,需要拿 group 1+2
            guard let catMatch = catRegex.firstMatch(in: html, options: [], range: segRange),
                  catMatch.numberOfRanges == 3,
                  let cat = stringRange(catMatch, 1, in: html),
                  let textRaw = stringRange(catMatch, 2, in: html)
            else { continue }

            // 只要 ssp 中量级(WorldSSP),过滤 sbk 主组 / wcr / yr3ec / ssp300 等
            guard cat == "ssp" else { continue }

            let text = textRaw.trimmingCharacters(in: .whitespaces)
            // text 形如 "WorldSSP - Race 2",剥 "WorldSSP - " 前缀
            let label: String
            if let dashRange = text.range(of: " - ") {
                label = String(text[dashRange.upperBound...])
            } else {
                label = text
            }
            let kind = sessionKind(forLabel: label)
            let id = "\(eventId)-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))"
            let displayLabel = displayLabel(forRaw: label)
            let session = Session(id: id, kind: kind, label: displayLabel, startTime: startTime)

            // Results.pdf URL——只在已结束的 session 块里有。同 segRange 内找。
            let pdfURL: URL? = firstCapture(html, pdfRegex, segRange, 1).flatMap(URL.init(string:))

            sessions.append(WSSPSessionWithResults(session: session, resultsPdfURL: pdfURL))
        }
        return sessions.sorted { $0.session.startTime < $1.session.startTime }
    }

    /// 解析 results statistics 页 #champ-standing-ssp 块下 ol.rider-ranking 的 li 列表。
    /// iOS 端拿到的 HTML attribute 都用双引号(Linux curl 拿到的省略),所有 attr 引号都做成可选。
    private nonisolated static func parseSSPStandings(html: String) -> [WSSPRiderStanding] {
        // 1. 找 ssp tab-pane 容器:`<div id="?champ-standing-ssp"?` 后面紧跟到下一个 ssp 兄弟前
        //    页面里 "champ-standing-ssp" 出现两次:一次在 tab nav (<a href="#...">),一次在 div container (<div id=...>)
        //    我们要的是 div container,用 `id=["']?champ-standing-ssp` 锚点
        guard let containerRegex = try? NSRegularExpression(pattern: #"id=["']?champ-standing-ssp"#) else { return [] }
        let nsAll = NSRange(html.startIndex..., in: html)
        let containerMatches = containerRegex.matches(in: html, options: [], range: nsAll)
        // 第一个 match 通常是 tab nav(<a href="#champ-standing-ssp">),第二个才是真正的 div container
        // 但 iOS 拿到的 markup 里 nav 是 `href="#..."`,div 是 `id="..."`,我们只匹配 `id=...`
        guard let container = containerMatches.first else { return [] }

        // 2. 在 container 之后找 ol.rider-ranking..</ol> 块
        let fromContainer = (html as NSString).substring(from: container.range.location + container.range.length)
        let fromContainerNS = fromContainer as NSString
        guard let olStartRegex = try? NSRegularExpression(pattern: #"<ol class=["']?rider-ranking["']?[^>]*>"#) else { return [] }
        guard let olStart = olStartRegex.firstMatch(in: fromContainer, options: [], range: NSRange(location: 0, length: fromContainerNS.length)) else { return [] }
        let olInnerStart = olStart.range.location + olStart.range.length
        // 找下一个 </ol>
        let searchRange = NSRange(location: olInnerStart, length: fromContainerNS.length - olInnerStart)
        let olEndRange = fromContainerNS.range(of: "</ol>", options: [], range: searchRange)
        guard olEndRange.location != NSNotFound else { return [] }
        let block = fromContainerNS.substring(with: NSRange(location: olInnerStart, length: olEndRange.location - olInnerStart))

        // 3. 每个 li 块解析。引号都可选
        guard let liRegex = try? NSRegularExpression(pattern: #"<li[^>]*>(.*?)</li>"#, options: [.dotMatchesLineSeparators]),
              let countryRegex = try? NSRegularExpression(pattern: #"mini_flag (\w+)"#),
              let nameRegex = try? NSRegularExpression(pattern: #"<span>([^<]+)</span>"#),
              let pointsRegex = try? NSRegularExpression(pattern: #"<span class=["']?rider-points["']?[^>]*>(\d+(?:\.\d+)?)</span>"#)
        else { return [] }

        let blockRange = NSRange(block.startIndex..., in: block)
        let liMatches = liRegex.matches(in: block, options: [], range: blockRange)

        var rows: [WSSPRiderStanding] = []
        for (idx, li) in liMatches.enumerated() {
            guard li.numberOfRanges == 2,
                  let inner = stringRange(li, 1, in: block) else { continue }
            let innerRange = NSRange(inner.startIndex..., in: inner)

            let countryISO = firstCapture(inner, countryRegex, innerRange, 1)
            guard let nameRaw = firstCapture(inner, nameRegex, innerRange, 1),
                  let pointsStr = firstCapture(inner, pointsRegex, innerRange, 1),
                  let points = Double(pointsStr) else { continue }

            let name = nameRaw
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let rider = WSSPRider(fullName: name, countryISO: countryISO)
            rows.append(WSSPRiderStanding(position: idx + 1, points: points, rider: rider))
        }
        return rows
    }

    /// 解析 #champ-manufacturer-standing-ssp 容器内 ol.builder-ranking 的 li 列表。
    /// 字段:国家(mini_flag class 后 token) / name(里层 span) / points
    private nonisolated static func parseSSPBuilderStandings(html: String) -> [WSSPBuilderStanding] {
        guard let containerRegex = try? NSRegularExpression(pattern: #"id=["']?champ-manufacturer-standing-ssp"#) else { return [] }
        let nsAll = NSRange(html.startIndex..., in: html)
        let containerMatches = containerRegex.matches(in: html, options: [], range: nsAll)
        guard let container = containerMatches.first else { return [] }

        let fromContainer = (html as NSString).substring(from: container.range.location + container.range.length)
        let fromContainerNS = fromContainer as NSString
        guard let olStartRegex = try? NSRegularExpression(pattern: #"<ol class=["']?builder-ranking["']?[^>]*>"#) else { return [] }
        guard let olStart = olStartRegex.firstMatch(in: fromContainer, options: [], range: NSRange(location: 0, length: fromContainerNS.length)) else { return [] }
        let olInnerStart = olStart.range.location + olStart.range.length
        let searchRange = NSRange(location: olInnerStart, length: fromContainerNS.length - olInnerStart)
        let olEndRange = fromContainerNS.range(of: "</ol>", options: [], range: searchRange)
        guard olEndRange.location != NSNotFound else { return [] }
        let block = fromContainerNS.substring(with: NSRange(location: olInnerStart, length: olEndRange.location - olInnerStart))

        guard let liRegex = try? NSRegularExpression(pattern: #"<li[^>]*>(.*?)</li>"#, options: [.dotMatchesLineSeparators]),
              let countryRegex = try? NSRegularExpression(pattern: #"mini_flag (\w+)"#),
              let nameRegex = try? NSRegularExpression(pattern: #"<span>([^<]+)</span>"#),
              let pointsRegex = try? NSRegularExpression(pattern: #"<span class=["']?builder-points["']?[^>]*>(\d+(?:\.\d+)?)</span>"#)
        else { return [] }

        let blockRange = NSRange(block.startIndex..., in: block)
        let liMatches = liRegex.matches(in: block, options: [], range: blockRange)

        var rows: [WSSPBuilderStanding] = []
        for (idx, li) in liMatches.enumerated() {
            guard li.numberOfRanges == 2,
                  let inner = stringRange(li, 1, in: block) else { continue }
            let innerRange = NSRange(inner.startIndex..., in: inner)

            let countryISO = firstCapture(inner, countryRegex, innerRange, 1)
            guard let nameRaw = firstCapture(inner, nameRegex, innerRange, 1),
                  let pointsStr = firstCapture(inner, pointsRegex, innerRange, 1),
                  let points = Double(pointsStr) else { continue }

            let name = nameRaw
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let builder = WSSPBuilder(name: name, countryISO: countryISO)
            rows.append(WSSPBuilderStanding(position: idx + 1, points: points, builder: builder))
        }
        return rows
    }

    /// 用 PDFSelection 按 visual 行切 PDF 内容,然后按 y 坐标 group fragment 还原 visual 行。
    /// 直接 selectionsByLine() 在 worldsbk PDF 上把每个 cell 切成独立 fragment(因为 PDF 内部
    /// 每 cell 是独立 text frame),需要再做一次坐标 group 才能拼成真正的 visual 行。
    private nonisolated static func extractVisualRows(page: PDFPage) -> [String] {
        let pageBounds = page.bounds(for: .mediaBox)
        guard let pageSelection = page.selection(for: pageBounds) else { return [] }
        let lineSelections = pageSelection.selectionsByLine()

        struct Fragment {
            let text: String
            let x: CGFloat
            let y: CGFloat
            let endX: CGFloat
        }

        var fragments: [Fragment] = []
        for selection in lineSelections {
            let raw = selection.string ?? ""
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let bounds = selection.bounds(for: page)
            fragments.append(Fragment(
                text: text,
                x: bounds.minX,
                y: bounds.minY,
                endX: bounds.maxX
            ))
        }
        guard !fragments.isEmpty else { return [] }

        // 按 y 降序(PDF y 向上,顶部行 y 大);group 容差 6pt——worldsbk PDF 的同行 cell
        // y 抖动可能 3-5pt,3pt 太严会把同行切成多个
        let yTolerance: CGFloat = 6
        let sorted = fragments.sorted { a, b in
            if abs(a.y - b.y) > yTolerance { return a.y > b.y }
            return a.x < b.x
        }

        var rows: [[Fragment]] = []
        for f in sorted {
            if let lastFirst = rows.last?.first,
               abs(lastFirst.y - f.y) < yTolerance {
                rows[rows.count - 1].append(f)
            } else {
                rows.append([f])
            }
        }

        // 行内按 x 排序拼接,大间距处保证有空格
        return rows.compactMap { row -> String? in
            let sortedRow = row.sorted { $0.x < $1.x }
            var s = ""
            var prevEndX: CGFloat = -1000
            for f in sortedRow {
                if !s.isEmpty {
                    if f.x - prevEndX > 4 || !s.hasSuffix(" ") {
                        s.append(" ")
                    }
                }
                s.append(f.text)
                prevEndX = f.endX
            }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// 调度入口——worldsbk PDF 有两种 layout:
    ///   - Race / Sprint:position number{initial.lastname} bike laps best_time ... nat team ...
    ///   - Superpole / WUP:position speed×3 number initial. avg_speed lastname nat laps team bike best_time ...
    /// 先 try Race format,匹配到非空就用;否则 fallback Superpole/speed-first format。
    private nonisolated static func parseVisualLines(_ lines: [String]) -> [WSSPRaceResult] {
        let raceRows = parseRaceFormatLines(lines)
        if !raceRows.isEmpty { return raceRows }
        return parseSpeedFirstFormatLines(lines)
    }

    /// Race / Sprint format。
    private nonisolated static func parseRaceFormatLines(_ lines: [String]) -> [WSSPRaceResult] {
        // anchor 不锚定到 line 起始/末尾——line 前可能有 padding 字符;
        // 用 word boundary 在 line 任意位置找 "position number{rider缩写名}" 模式
        guard let anchorRegex = try? NSRegularExpression(pattern:
            #"\b(\d{1,2})\s+(\d{1,3})([A-Z]\.\s+[A-Z][A-Z\s\-']{1,30}?)\s+"#
        ) else { return [] }
        guard let timeRegex = try? NSRegularExpression(pattern: #"\d{1,2}'\d{2}\.\d{2,3}"#) else { return [] }
        guard let natRegex = try? NSRegularExpression(pattern: #"\b[A-Z]{3}\b"#) else { return [] }
        guard let gapRegex = try? NSRegularExpression(pattern: #"\b\d+\.\d{3}\b"#) else { return [] }

        var rows: [WSSPRaceResult] = []
        for line in lines {
            let nsLine = line as NSString
            let m = anchorRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard let m, m.numberOfRanges == 4,
                  let position = Int(nsLine.substring(with: m.range(at: 1))),
                  let number = Int(nsLine.substring(with: m.range(at: 2)))
            else { continue }
            guard position >= 1, position <= 60 else { continue }

            let name = nsLine.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            // rest = anchor 末尾(空格之后)到 line 末
            let restStart = m.range.location + m.range.length
            let rest = nsLine.substring(from: restStart).trimmingCharacters(in: .whitespaces)
            guard name.count >= 3 else { continue }

            let restNS = rest as NSString
            let restAll = NSRange(location: 0, length: restNS.length)

            // 第一个 time 是 best_time
            let bestTimeMatch = timeRegex.firstMatch(in: rest, range: restAll)
            let timeText: String? = bestTimeMatch.map { restNS.substring(with: $0.range) }

            // bike: rest 起头到 best_time 之前(再剥末尾的 laps 数字)
            var bike: String? = nil
            if let tm = bestTimeMatch {
                var beforeTime = restNS.substring(with: NSRange(location: 0, length: tm.range.location))
                    .trimmingCharacters(in: .whitespaces)
                // 末尾通常是 laps 整数(1-2 位),剥掉
                if let last = beforeTime.split(separator: " ").last,
                   let lapNum = Int(last), lapNum >= 1, lapNum <= 50 {
                    beforeTime = beforeTime.dropLast(last.count).trimmingCharacters(in: .whitespaces)
                }
                bike = beforeTime.isEmpty ? nil : beforeTime
            }

            // nat: 三大写字母 word(过滤掉 bike 里可能的 "ZX" 等),从 best_time 后开始找
            var nat = ""
            var natMatchEnd: Int? = nil
            if let tm = bestTimeMatch {
                let afterTime = tm.range.location + tm.range.length
                let searchRange = NSRange(location: afterTime, length: restNS.length - afterTime)
                if let nm = natRegex.firstMatch(in: rest, range: searchRange) {
                    nat = restNS.substring(with: nm.range)
                    natMatchEnd = nm.range.location + nm.range.length
                }
            }

            // team: nat 之后到下个 time(avg_lap)之前
            var team = ""
            if let natEnd = natMatchEnd {
                let after = NSRange(location: natEnd, length: restNS.length - natEnd)
                let avgTimeMatch = timeRegex.firstMatch(in: rest, range: after)
                let teamEnd = avgTimeMatch?.range.location ?? restNS.length
                team = restNS.substring(with: NSRange(location: natEnd, length: teamEnd - natEnd))
                    .trimmingCharacters(in: .whitespaces)
                // 末尾可能是 X.XXX gap_prev,剥掉
                if let last = team.split(separator: " ").last,
                   Double(last) != nil, last.contains(".") {
                    team = team.dropLast(last.count).trimmingCharacters(in: .whitespaces)
                }
                // 末尾的 "*" 标志(年轻车手或 wildcard)剥掉
                if team.hasSuffix("*") {
                    team = String(team.dropLast()).trimmingCharacters(in: .whitespaces)
                }
            }

            // gap_to_first: best_time 之后,nat 之前的第一个 X.XXX
            var gapText: String? = nil
            if let tm = bestTimeMatch, let natEnd = natMatchEnd {
                let between = NSRange(location: tm.range.location + tm.range.length,
                                      length: natEnd - (tm.range.location + tm.range.length))
                if let gm = gapRegex.firstMatch(in: rest, range: between) {
                    gapText = restNS.substring(with: gm.range)
                }
            }

            rows.append(WSSPRaceResult(
                position: position,
                number: number,
                riderName: name,
                nat: nat,
                team: team,
                bike: bike,
                timeText: timeText,
                gapText: gapText,
                laps: nil
            ))
        }
        return rows
    }

    /// Superpole / WUP / FP format (speed-first):
    ///   "1 274,6 274,6 274,6 5 J. 173,718 MASIA ESP 19 Orelac Racing Verdnatura Ducati Panigale V2 1'32.115"
    /// 字段:position speed×3 number initial. avg_speed lastname nat laps team bike best_time gap1 gap2
    private nonisolated static func parseSpeedFirstFormatLines(_ lines: [String]) -> [WSSPRaceResult] {
        // anchor: pos + 3 speed + number + initial + avg_speed + lastname + nat
        guard let anchorRegex = try? NSRegularExpression(pattern:
            #"\b(\d{1,2})\s+\d+,\d+\s+\d+,\d+\s+\d+,\d+\s+(\d{1,3})\s+([A-Z])\.\s+\d+,\d+\s+([A-Z][A-Z\s\-']{2,30}?)\s+([A-Z]{3})\b"#
        ) else { return [] }
        guard let timeRegex = try? NSRegularExpression(pattern: #"\d{1,2}'\d{2}\.\d{2,3}"#) else { return [] }
        guard let gapRegex = try? NSRegularExpression(pattern: #"\b\d+\.\d{3}\b"#) else { return [] }

        var rows: [WSSPRaceResult] = []
        for line in lines {
            let nsLine = line as NSString
            let m = anchorRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard let m, m.numberOfRanges == 6,
                  let position = Int(nsLine.substring(with: m.range(at: 1))),
                  let number = Int(nsLine.substring(with: m.range(at: 2)))
            else { continue }
            guard position >= 1, position <= 60 else { continue }

            let initial = nsLine.substring(with: m.range(at: 3))
            let lastname = nsLine.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
            let nat = nsLine.substring(with: m.range(at: 5))
            let name = "\(initial). \(lastname)"
            guard lastname.count >= 2 else { continue }

            // rest = anchor 之后(nat 之后)
            let restStart = m.range.location + m.range.length
            let rest = nsLine.substring(from: restStart).trimmingCharacters(in: .whitespaces)
            let restNS = rest as NSString
            let restAll = NSRange(location: 0, length: restNS.length)

            // best_time: rest 里第一个 X'XX.XXX
            let timeMatch = timeRegex.firstMatch(in: rest, range: restAll)
            let timeText: String? = timeMatch.map { restNS.substring(with: $0.range) }

            // team + bike: best_time 之前(再剥首位 laps 数字 + 末尾 bike)
            var team = ""
            if let tm = timeMatch {
                var beforeTime = restNS.substring(with: NSRange(location: 0, length: tm.range.location))
                    .trimmingCharacters(in: .whitespaces)
                // 首 token 是 laps 数,剥
                if let firstSpace = beforeTime.firstIndex(of: " "),
                   Int(beforeTime[..<firstSpace]) != nil {
                    beforeTime = beforeTime[beforeTime.index(after: firstSpace)...].trimmingCharacters(in: .whitespaces)
                }
                if beforeTime.hasSuffix("*") {
                    beforeTime = String(beforeTime.dropLast()).trimmingCharacters(in: .whitespaces)
                }
                // 用厂商关键字找 bike 起点(取最右出现的厂商,前面要有空格 boundary)。
                // beforeTime 例:"Orelac Racing Verdnatura Ducati Panigale V2"
                //                                       ↑ 这里切,左边 team / 右边 bike
                if let bikeStart = bikeKeywordStart(in: beforeTime) {
                    team = String(beforeTime[..<bikeStart]).trimmingCharacters(in: .whitespaces)
                } else {
                    team = beforeTime
                }
            } else {
                team = rest
            }

            // gap_to_first: best_time 之后第一个 X.XXX
            var gapText: String? = nil
            if let tm = timeMatch {
                let afterStart = tm.range.location + tm.range.length
                let afterRange = NSRange(location: afterStart, length: restNS.length - afterStart)
                if let gm = gapRegex.firstMatch(in: rest, range: afterRange) {
                    gapText = restNS.substring(with: gm.range)
                }
            }

            rows.append(WSSPRaceResult(
                position: position,
                number: number,
                riderName: name,
                nat: nat,
                team: team,
                bike: nil,
                timeText: timeText,
                gapText: gapText,
                laps: nil
            ))
        }
        return rows
    }

    /// 已知 WSSP 厂商列表——找 team+bike 拼接里 bike 的起点。
    /// 取**最右**(.backwards)出现的厂商,因为 team 名也可能含厂商词("Pata Yamaha Ten Kate Racing")。
    private nonisolated static func bikeKeywordStart(in text: String) -> String.Index? {
        let keywords = ["Aprilia", "Ducati", "Honda", "Kawasaki", "MV Agusta", "QJMOTOR", "Triumph", "Yamaha", "ZXMOTO"]
        var best: String.Index? = nil
        for kw in keywords {
            guard let range = text.range(of: kw, options: .backwards) else { continue }
            // 厂商关键字前必须是 space 或行首,确保是独立词
            let priorIsBoundary: Bool = {
                if range.lowerBound == text.startIndex { return true }
                let prior = text[text.index(before: range.lowerBound)]
                return prior == " "
            }()
            guard priorIsBoundary else { continue }
            if let cur = best {
                if range.lowerBound > cur { best = range.lowerBound }
            } else {
                best = range.lowerBound
            }
        }
        return best
    }

    private nonisolated static func sessionKind(forLabel label: String) -> Session.Kind {
        switch label {
        case "Race 1", "Race 2":   return .race
        case "Superpole Race":     return .superpoleRace
        case "Superpole":          return .qualifying
        default:                   return .practice  // FP1/FP2/FP3/WUP
        }
    }

    private nonisolated static func displayLabel(forRaw label: String) -> String {
        switch label {
        case "WUP": return "Warm Up"
        default:    return label
        }
    }

    private nonisolated static func stringRange(_ match: NSTextCheckingResult, _ idx: Int, in text: String) -> String? {
        let nsr = match.range(at: idx)
        guard nsr.location != NSNotFound, let range = Range(nsr, in: text) else { return nil }
        return String(text[range])
    }

    private nonisolated static func parseDateRange(_ text: String, year: Int) -> (Date, Date)? {
        // "20 - 22 Feb"  或跨月  "29 May - 1 Jun"
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        let leftRaw = parts[0]
        let rightRaw = parts[1]

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        guard let endDate = formatter.date(from: "\(rightRaw) \(year)") else { return nil }

        let leftWithMonth: String
        if leftRaw.contains(" ") {
            leftWithMonth = leftRaw
        } else {
            let rightMonth = rightRaw.split(separator: " ").last.map(String.init) ?? ""
            leftWithMonth = "\(leftRaw) \(rightMonth)"
        }
        guard let startDate = formatter.date(from: "\(leftWithMonth) \(year)") else { return nil }
        return (startDate, endDate)
    }
}
