import Foundation
import PoleDomain
import PoleMotorsportKit

/// `get_driver_history` —— 单车手赛季 round-by-round 表现。
///
/// 模糊匹配支持中文 / 英文 / 姓 / 含重音字符（Pérez / Sainz / Hülkenberg 等）。
/// 输出的 name 走 Localization 中文化（zh 模式）。
public struct GetDriverHistoryTool: AgentTool {
    public init() {}

    public let name = "get_driver_history"
    public let description = """
    Get a driver's season performance round-by-round. Use when user asks how a specific driver
    has been doing recently, points trend, or comparison. Driver name is fuzzy matched
    (中文 / English / surname / 含重音字符).
    Output name is pre-localized to the user's language; use it as-is.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {
        "series": {"type": "string", "enum": ["f1", "motogp", "wsbk"]},
        "driver_name": {"type": "string", "description": "Driver/rider name in any form: 'Verstappen', '维斯塔潘', 'VER', 'Bagnaia', '佩雷兹'"}
      },
      "required": ["series", "driver_name"],
      "additionalProperties": false
    }
    """

    /// `nonisolated` 让 Decodable conformance 在 nonisolated runningHint 里能 decode 不报警告。
    private nonisolated struct Args: Decodable {
        let series: String
        let driver_name: String
    }

    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            return L10n.t(zh: "查询车手生涯…", en: "Loading driver history…")
        }
        let series = args.series.uppercased()
        return L10n.t(
            zh: "查询 \(args.driver_name) 在 \(series) 的赛季历史…",
            en: "Loading \(args.driver_name)'s \(series) history…"
        )
    }

    public func execute(argumentsJSON: String) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8))
        let query = args.driver_name

        switch args.series {
        case "f1":
            let standings = (try? await JolpicaClient.shared.fetchDriverStandings()) ?? []
            guard let match = Self.fuzzyMatchF1(driver: query, in: standings) else {
                return Self.notFound(
                    query: query,
                    candidates: standings.map {
                        MotorsportNames.driverFullName(rawFullName: $0.driver.fullName, series: .f1)
                    }
                )
            }
            let rounds = (try? await JolpicaClient.shared.fetchDriverSeasonResults(
                season: "current", driverId: match.driver.id
            )) ?? []
            let payload: [String: Any] = [
                "name": MotorsportNames.driverFullName(rawFullName: match.driver.fullName, series: .f1),
                "current_position": match.position,
                "current_points": match.points,
                "wins": match.wins,
                "rounds": rounds.map { r in
                    ["round": r.round, "race": r.raceName, "points": r.points] as [String: Any]
                }
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return String(data: data, encoding: .utf8) ?? "{}"

        case "motogp":
            let standings = (try? await MotoGPClient.shared.fetchRiderStandings()) ?? []
            guard let match = Self.fuzzyMatchMotoGP(driver: query, in: standings) else {
                return Self.notFound(
                    query: query,
                    candidates: standings.map {
                        MotorsportNames.driverFullName(rawFullName: $0.rider.fullName, series: .motogp)
                    }
                )
            }
            let payload: [String: Any] = [
                "name": MotorsportNames.driverFullName(rawFullName: match.rider.fullName, series: .motogp),
                "current_position": match.position,
                "current_points": match.points,
                "wins": match.raceWins,
                "podiums": match.podiums,
                "team": MotorsportNames.teamName(raw: match.team.name, series: .motogp),
                "constructor": MotorsportNames.teamName(raw: match.constructor.name, series: .motogp),
                "note": "MotoGP API 不提供单 rider 逐站积分,仅当前赛季汇总"
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return String(data: data, encoding: .utf8) ?? "{}"

        case "wsbk":
            let standings = (try? await WSBKClient.shared.fetchSSPRiderStandings()) ?? []
            guard let match = Self.fuzzyMatchWSBK(driver: query, in: standings) else {
                return Self.notFound(
                    query: query,
                    candidates: standings.map {
                        MotorsportNames.driverFullName(rawFullName: $0.rider.fullName, series: .wssp)
                    }
                )
            }
            let lastName = match.rider.fullName.split(separator: " ").last.map(String.init) ?? match.rider.fullName
            let rounds = await WSBKClient.shared.fetchSSPRiderRoundPoints(riderLastName: lastName)
            let payload: [String: Any] = [
                "name": MotorsportNames.driverFullName(rawFullName: match.rider.fullName, series: .wssp),
                "current_position": match.position,
                "current_points": match.points,
                "wins": match.wins,
                "rounds": rounds.map { r in
                    [
                        "round": r.round,
                        "race": r.roundName,
                        "race1_points": r.race1Points,
                        "race2_points": r.race2Points,
                        "total": r.totalPoints
                    ] as [String: Any]
                }
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return String(data: data, encoding: .utf8) ?? "{}"

        default:
            return #"{"error":"unknown series"}"#
        }
    }

    // MARK: 模糊匹配（normalize-aware + 中文反向匹配）

    /// 把 raw 字符串规整为 ASCII lowercase（去重音 + 转小写），跟 `MotorsportNames.normalize` 一致。
    private static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    /// 检查 query 是否命中一个 candidate（英文 fullName）：
    /// - 直接 normalized 字面匹配（含 Pérez / Hülkenberg 等重音字符 → "perez" / "hulkenberg"）；
    /// - 中文 query：用 driverFullName / driverShortName 翻成中文再做 contains 匹配。
    private static func matches(query: String, candidate: String, series: MotorsportSeries) -> Bool {
        let q = normalize(query)
        let c = normalize(candidate)
        if c == q || c.contains(q) || q.contains(c) { return true }
        // 中文 query 反向：把 candidate 翻成中文再查
        let zhFull = MotorsportNames.driverFullName(rawFullName: candidate, series: series)
        let zhShort = MotorsportNames.driverShortName(rawFullName: candidate, series: series)
        if zhFull != candidate, zhFull.contains(query) { return true }
        if zhShort != candidate, zhShort.contains(query) { return true }
        return false
    }

    private static func fuzzyMatchF1(driver query: String, in standings: [F1DriverStanding]) -> F1DriverStanding? {
        // 优先级: 精确(normalize) → code → 部分(normalize / 中文) → 姓(normalize)
        let q = normalize(query)
        if let exact = standings.first(where: { normalize($0.driver.fullName) == q }) { return exact }
        if let code = standings.first(where: { normalize($0.driver.code ?? "") == q }) { return code }
        if let part = standings.first(where: { Self.matches(query: query, candidate: $0.driver.fullName, series: .f1) }) { return part }
        if let last = standings.first(where: { normalize($0.driver.familyName) == q }) { return last }
        return nil
    }

    private static func fuzzyMatchMotoGP(driver query: String, in standings: [MotoGPRiderStanding]) -> MotoGPRiderStanding? {
        let q = normalize(query)
        if let exact = standings.first(where: { normalize($0.rider.fullName) == q }) { return exact }
        if let part = standings.first(where: { Self.matches(query: query, candidate: $0.rider.fullName, series: .motogp) }) { return part }
        return nil
    }

    private static func fuzzyMatchWSBK(driver query: String, in standings: [WSSPRiderStanding]) -> WSSPRiderStanding? {
        let q = normalize(query)
        if let exact = standings.first(where: { normalize($0.rider.fullName) == q }) { return exact }
        if let part = standings.first(where: { Self.matches(query: query, candidate: $0.rider.fullName, series: .wssp) }) { return part }
        return nil
    }

    private static func notFound(query: String, candidates: [String]) -> String {
        let payload: [String: Any] = [
            "error": "no driver match",
            "query": query,
            "candidates": Array(candidates.prefix(15))
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
