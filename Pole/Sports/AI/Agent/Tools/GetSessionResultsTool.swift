import Foundation
import PoleDomain

/// `get_session_results` —— 单 session(race/qualifying/sprint)的完整结果排行。
///
/// 车手 / 车队名通过 `MotorsportNames.driverFullName` / `teamName` 输出当前用户语言，
/// LLM 看到 zh 模式下的中文译名就直接用，避免输出英文。
///
/// 错误处理：所有 fetch 失败统一走 `AgentToolJSON.fetchFailed` 返回结构化错误，
/// LLM 能区分"网络/接口问题"和"真没结果"两种情况，不会把 fetch 失败当作"无数据"。
public struct GetSessionResultsTool: AgentTool {
    public init() {}

    public let name = "get_session_results"
    public let description = """
    Get complete results table for a specific session (race / qualifying / sprint).
    Use when user asks "who won the X race" / "qualifying results for round N".
    Driver and team names are pre-localized to the user's language; use them as-is.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {
        "series": {"type": "string", "enum": ["f1", "motogp", "wsbk"]},
        "round": {"type": "integer", "description": "1-based round number"},
        "session": {"type": "string", "enum": ["race", "sprint", "qualifying", "race_2"]}
      },
      "required": ["series", "round", "session"],
      "additionalProperties": false
    }
    """

    /// `nonisolated` 让 Decodable conformance 在 nonisolated runningHint 里能 decode 不报警告。
    private nonisolated struct Args: Decodable {
        let series: String
        let round: Int
        let session: String
    }

    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            return L10n.t(zh: "查询比赛结果…", en: "Loading results…")
        }
        let series = args.series.uppercased()
        return L10n.t(
            zh: "查询 \(series) 第 \(args.round) 站 \(args.session) 结果…",
            en: "Loading \(series) R\(args.round) \(args.session) results…"
        )
    }

    public func execute(argumentsJSON: String) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8))

        switch args.series {
        case "f1":
            return await f1Results(round: args.round, session: args.session)
        case "motogp":
            return await motogpResults(round: args.round, session: args.session)
        case "wsbk":
            return await wsbkResults(round: args.round, session: args.session)
        default:
            return #"{"error":"unknown series"}"#
        }
    }

    // MARK: F1

    private func f1Results(round: Int, session: String) async -> String {
        // jolpica 用 "current" 表示当年
        let season = "current"
        switch session {
        case "race":
            do {
                let rows = try await JolpicaClient.shared.fetchRaceResults(season: season, round: round)
                let payload = rows.prefix(20).map { r in
                    [
                        "position": r.position,
                        "name": MotorsportNames.driverFullName(rawFullName: r.driver.fullName, series: .f1),
                        "team": MotorsportNames.teamName(raw: r.constructor.name, series: .f1),
                        "time": r.timeText ?? r.status,
                        "points": r.points,
                        "status": r.status
                    ] as [String: Any]
                }
                return Self.wrap(payload)
            } catch {
                return AgentToolJSON.fetchFailed(series: "f1", error: error)
            }
        case "sprint":
            do {
                let rows = try await JolpicaClient.shared.fetchSprintResults(season: season, round: round)
                let payload = rows.prefix(20).map { r in
                    ["position": r.position,
                     "name": MotorsportNames.driverFullName(rawFullName: r.driver.fullName, series: .f1),
                     "team": MotorsportNames.teamName(raw: r.constructor.name, series: .f1),
                     "time": r.timeText ?? r.status, "points": r.points] as [String: Any]
                }
                return Self.wrap(payload)
            } catch {
                return AgentToolJSON.fetchFailed(series: "f1", error: error)
            }
        case "qualifying":
            do {
                let rows = try await JolpicaClient.shared.fetchQualifyingResults(season: season, round: round)
                let payload = rows.prefix(20).map { r in
                    ["position": r.position,
                     "name": MotorsportNames.driverFullName(rawFullName: r.driver.fullName, series: .f1),
                     "team": MotorsportNames.teamName(raw: r.constructor.name, series: .f1),
                     "best_time": r.q3 ?? r.q2 ?? r.q1 ?? ""] as [String: Any]
                }
                return Self.wrap(payload)
            } catch {
                return AgentToolJSON.fetchFailed(series: "f1", error: error)
            }
        default:
            return #"{"error":"unsupported f1 session"}"#
        }
    }

    // MARK: MotoGP

    private func motogpResults(round: Int, session: String) async -> String {
        // 先找 round 对应的 event
        let rounds: [MotoGPRound]
        do {
            rounds = try await MotoGPClient.shared.fetchSeasonRounds()
        } catch {
            return AgentToolJSON.fetchFailed(series: "motogp", error: error)
        }
        guard let r = rounds.first(where: { $0.round == round }) else {
            return #"{"error":"round not found"}"#
        }
        let refs: [MotoGPSessionRef]
        do {
            refs = try await MotoGPClient.shared.fetchSessions(eventId: r.id)
        } catch {
            return AgentToolJSON.fetchFailed(series: "motogp", error: error)
        }
        let want: Session.Kind
        switch session {
        case "race":       want = .race
        case "sprint":     want = .sprint
        case "qualifying": want = .qualifying
        default:           return #"{"error":"unsupported motogp session"}"#
        }
        let candidates = refs.filter { $0.session.kind == want }
            .sorted { $0.session.startTime < $1.session.startTime }
        guard let target = candidates.first else { return #"{"error":"session not in this round"}"# }
        let rows: [MotoGPRaceResult]
        do {
            rows = try await MotoGPClient.shared.fetchSessionResults(sessionId: target.rawId)
        } catch {
            return AgentToolJSON.fetchFailed(series: "motogp", error: error)
        }
        let payload = rows.prefix(20).map { row in
            [
                "position": row.position,
                "name": MotorsportNames.driverFullName(rawFullName: row.rider.fullName, series: .motogp),
                "team": MotorsportNames.teamName(raw: row.team.name, series: .motogp),
                "constructor": MotorsportNames.teamName(raw: row.constructor.name, series: .motogp),
                "time": row.timeText ?? row.gapToFirstText ?? row.status,
                "points": row.points
            ] as [String: Any]
        }
        return Self.wrap(payload)
    }

    // MARK: WSBK(WSSP class)

    private func wsbkResults(round: Int, session: String) async -> String {
        let rounds: [WSBKRound]
        do {
            rounds = try await WSBKClient.shared.fetchSeasonRounds()
        } catch {
            return AgentToolJSON.fetchFailed(series: "wsbk", error: error)
        }
        guard let r = rounds.first(where: { $0.round == round }) else {
            return #"{"error":"round not found"}"#
        }
        let items: [WSSPSessionWithResults]
        do {
            items = try await WSBKClient.shared.fetchEventSessions(
                countryCode: r.countryCode, year: r.season
            )
        } catch {
            return AgentToolJSON.fetchFailed(series: "wsbk", error: error)
        }
        // 想要哪个 race PDF? race=Race 1, race_2=Race 2, qualifying=Superpole
        let candidates: [WSSPSessionWithResults]
        switch session {
        case "race":
            candidates = items.filter { $0.session.label == "Race 1" }
        case "race_2":
            candidates = items.filter { $0.session.label == "Race 2" }
        case "qualifying":
            candidates = items.filter { $0.session.kind == .qualifying }
        default:
            return #"{"error":"unsupported wsbk session"}"#
        }
        guard let target = candidates.first, let pdfURL = target.resultsPdfURL else {
            return #"{"error":"session not available"}"#
        }
        let rows: [WSSPRaceResult]
        do {
            rows = try await WSBKClient.shared.fetchSSPSessionResults(pdfURL: pdfURL)
        } catch {
            return AgentToolJSON.fetchFailed(series: "wsbk", error: error)
        }
        let payload = rows.prefix(25).map { row in
            [
                "position": row.position,
                "name": MotorsportNames.driverFullName(rawFullName: row.riderName, series: .wssp),
                "team": MotorsportNames.teamName(raw: row.team, series: .wssp),
                "nat": row.nat,
                "time": row.timeText ?? row.gapText ?? ""
            ] as [String: Any]
        }
        return Self.wrap(payload)
    }

    private static func wrap(_ rows: [[String: Any]]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
