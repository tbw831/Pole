import Foundation
import PoleDomain
import PoleMotorsportKit

/// `find_round` tool —— 查找下一场/某轮/某国家的赛事周末。
public struct FindRoundTool: AgentTool {
    public init() {}

    /// 共享 ISO8601 formatter,避免每次 find_round 序列化 weekend / sessions 时
    /// 重复创建实例(原来一次调用可能创建 ~20 个 formatter)。线程安全。
    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    public let name = "find_round"
    public let description = """
    Find race weekends in a motorsport series.
    - when="next" / "previous": one specific round
    - when="by_round" / "by_country": targeted lookup
    - when="season_overview": full season summary (total rounds, finished count, remaining count, all rounds)
      Use this when user asks "how many rounds left" / "season schedule" / "总共多少站" — DO NOT enumerate by_round!
    Returns round number, circuit, sessions list.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {
        "series": {"type": "string", "enum": ["f1", "motogp", "wsbk", "fe"]},
        "when": {"type": "string", "enum": ["next", "previous", "by_round", "by_country", "season_overview"]},
        "round": {"type": "integer", "description": "1-based round number, required if when=by_round"},
        "country": {"type": "string", "description": "Country name in English, required if when=by_country"}
      },
      "required": ["series", "when"],
      "additionalProperties": false
    }
    """

    /// `nonisolated` 让 Decodable conformance 在 nonisolated runningHint 里能 decode 不报警告。
    private nonisolated struct Args: Decodable {
        let series: String
        let when: String
        let round: Int?
        let country: String?
    }

    /// 进度文案 — 解析 series + when 给针对性提示。
    /// 解析失败也不爆,直接返通用文案,确保 UI 不会因为一个 hint 错误吃报错。
    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            return L10n.t(zh: "正在查找赛事…", en: "Finding race…")
        }
        let series = args.series.uppercased()
        switch args.when {
        case "next":     return L10n.t(zh: "查找 \(series) 下一站…", en: "Finding next \(series) round…")
        case "previous": return L10n.t(zh: "查找 \(series) 最近一站…", en: "Finding latest \(series) round…")
        case "season_overview":
            return L10n.t(zh: "拉取 \(series) 整季赛历…", en: "Loading full \(series) season…")
        case "by_round":
            if let r = args.round {
                return L10n.t(zh: "查找 \(series) 第 \(r) 站…", en: "Finding \(series) round \(r)…")
            }
            return L10n.t(zh: "查找 \(series) 赛事…", en: "Finding \(series) round…")
        case "by_country":
            if let c = args.country {
                return L10n.t(zh: "查找 \(series) \(c) 站…", en: "Finding \(series) \(c) round…")
            }
            return L10n.t(zh: "查找 \(series) 赛事…", en: "Finding \(series) round…")
        default:
            return L10n.t(zh: "查找 \(series) 赛事…", en: "Finding \(series) round…")
        }
    }

    public func execute(argumentsJSON: String) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8))
        // 通过 registry 单点 dispatch 到 series-specific service,不再 switch 4 个 client。
        // 序列化阶段还要根据 `AnyMotorsportRound` 各 case 取字段,逻辑保留在本 tool 里。
        guard let service = MotorsportRegistry.service(forId: args.series) else {
            return AgentToolJSON.error("unknown_series", message: args.series)
        }
        // 网络/解析失败必须告诉 LLM "拿不到数据" 而不是返空数组让它幻觉。
        do {
            let rounds = try await service.anyRounds()
            return try Self.serialize(rounds: rounds, args: args)
        } catch {
            return AgentToolJSON.fetchFailed(series: args.series, error: error)
        }
    }

    private static func serialize(rounds: [AnyMotorsportRound], args: Args) throws -> String {
        let now = Date()
        let filtered: [AnyMotorsportRound]
        switch args.when {
        case "next":
            filtered = rounds
                .filter { $0.weekendEnd >= now }
                .sorted { $0.weekendStart < $1.weekendStart }
                .prefix(1)
                .map { $0 }
        case "previous":
            filtered = rounds
                .filter { $0.weekendEnd < now }
                .sorted { $0.weekendEnd > $1.weekendEnd }
                .prefix(1)
                .map { $0 }
        case "by_round":
            guard let r = args.round else { return #"{"error":"round required"}"# }
            filtered = rounds.filter {
                switch $0 {
                case .f1(let race):          return race.round == r
                case .motogp(let r2):        return r2.round == r
                case .wssp(let r3):          return r3.round == r
                case .fe(let r4):            return r4.round == r
                case .feWeekend(let w):      return w.rounds.contains { $0.round == r }
                }
            }
        case "by_country":
            guard let c = args.country?.lowercased() else { return #"{"error":"country required"}"# }
            filtered = rounds.filter {
                $0.subheadline.lowercased().contains(c) || $0.headline.lowercased().contains(c)
            }
        case "season_overview":
            // 整季总览 — 一次性返赛季所有 round + 已完成/未完成数量,LLM 不再 by_round 死循环。
            // payload schema 跟其它模式不同(包 summary block + 全部 rounds 不只是 1 条)。
            return try serializeSeasonOverview(rounds: rounds, args: args, now: now)
        default:
            return #"{"error":"unknown when"}"#
        }

        let payload = filtered.map { round -> [String: Any] in
            var dict: [String: Any] = [
                "id": round.id,
                "series": round.series.rawValue,
                "headline": round.headline,
                "subheadline": round.subheadline,
                "weekend_start_utc": Self.iso8601.string(from: round.weekendStart),
                "weekend_end_utc": Self.iso8601.string(from: round.weekendEnd),
                "status": round.currentStatus.rawValue
            ]
            if case .f1(let race) = round {
                dict["round"] = race.round
                dict["season"] = race.season
                dict["circuit"] = race.circuit.name
                dict["country"] = race.circuit.country
                dict["sessions"] = race.sessions.map { sess in
                    [
                        "label": sess.label,
                        "kind": sess.kind.rawValue,
                        "start_utc": Self.iso8601.string(from: sess.startTime)
                    ]
                }
            }
            if case .motogp(let r) = round {
                dict["round"] = r.round
                dict["season"] = r.season
                dict["circuit"] = r.circuit.name
                dict["country"] = r.circuit.country
            }
            if case .wssp(let r) = round {
                dict["round"] = r.round
                dict["season"] = r.season
                dict["circuit"] = r.circuit.name
                dict["country_code"] = r.countryCode
            }
            if case .fe(let r) = round {
                dict["round"] = r.round
                dict["season"] = r.season
                dict["circuit"] = r.circuit.name
                dict["country"] = r.circuit.country
            }
            if case .feWeekend(let w) = round, let r = w.rounds.first {
                dict["round"] = r.round
                dict["season"] = r.season
                dict["circuit"] = r.circuit.name
                dict["country"] = r.circuit.country
            }
            return dict
        }
        let json = try JSONSerialization.data(withJSONObject: ["rounds": payload])
        return String(data: json, encoding: .utf8) ?? "{}"
    }

    /// 整季总览 payload — 给 LLM 一次拿到"赛季多少站、跑了几站、还剩几站"。
    /// payload 比常规 modes 大但比 LLM 自己 enumerate by_round 高效百倍。
    private static func serializeSeasonOverview(
        rounds: [AnyMotorsportRound],
        args: Args,
        now: Date
    ) throws -> String {
        let sorted = rounds.sorted { ($0.season, $0.round_) < ($1.season, $1.round_) }
        let finished = sorted.filter { $0.weekendEnd < now }
        let upcoming = sorted.filter { $0.weekendEnd >= now }
        let live = sorted.first { $0.currentStatus == .live }
        let next = upcoming.first { $0.currentStatus != .live }

        // 简化每条 round 的 dict — overview 模式只关心 round number / name / 状态 / 日期,
        // 不返冗长的 sessions 列表(节省 token)。
        let roundDicts: [[String: Any]] = sorted.map { r in
            [
                "round": r.round_,
                "headline": r.headline,
                "country": r.subheadline,
                "weekend_start_utc": Self.iso8601.string(from: r.weekendStart),
                "weekend_end_utc": Self.iso8601.string(from: r.weekendEnd),
                "status": r.currentStatus.rawValue
            ]
        }

        var summary: [String: Any] = [
            "series": args.series,
            "total_rounds": sorted.count,
            "finished_count": finished.count,
            "remaining_count": upcoming.count
        ]
        if let live = live {
            summary["live_round"] = live.round_
        }
        if let next = next {
            summary["next_round"] = next.round_
            summary["next_round_headline"] = next.headline
        }

        let payload: [String: Any] = [
            "summary": summary,
            "rounds": roundDicts
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        return String(data: json, encoding: .utf8) ?? "{}"
    }
}

// MARK: - 辅助 — AnyMotorsportRound 抽象访问 round/season(各 case 字段名一致但类型 enum 不暴露通用 accessor)

private extension AnyMotorsportRound {
    /// round number — 4 个 case 都有,但是分开 accessor 麻烦,这里统一暴露。
    var round_: Int {
        switch self {
        case .f1(let race):        return race.round
        case .motogp(let r):       return r.round
        case .wssp(let r):         return r.round
        case .fe(let r):           return r.round
        case .feWeekend(let w):    return w.rounds.first!.round
        }
    }

    /// 赛季 — 4 个 case 都有 String season。
    var season: String {
        switch self {
        case .f1(let race):        return race.season
        case .motogp(let r):       return r.season
        case .wssp(let r):         return r.season
        case .fe(let r):           return r.season
        case .feWeekend(let w):    return w.rounds.first!.season
        }
    }
}
