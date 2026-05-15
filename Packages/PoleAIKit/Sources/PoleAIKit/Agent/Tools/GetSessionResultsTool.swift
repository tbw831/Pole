import Foundation
import PoleDomain
import PoleMotorsportKit

/// `get_session_results` —— 单 session(race/qualifying/sprint)的完整结果排行。
///
/// 通过 `MotorsportRegistry` 单点 dispatch:每个 series client 自己实现 `anySessionResultsJSON`,
/// 本 tool 不再写 3 套分支。车手 / 车队名在 client 内部已经按 `MotorsportNames` 输出当前语言。
///
/// 错误处理:client 内部所有 fetch 失败统一返 `{"error":"fetch_failed", ...}`,
/// LLM 能区分"网络/接口问题"和"真没结果"两种情况,不会把 fetch 失败当作"无数据"。
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
        guard let service = MotorsportRegistry.service(forId: args.series) else {
            return AgentToolJSON.error("unsupported_series", message: args.series)
        }
        return await service.anySessionResultsJSON(round: args.round, sessionKind: args.session)
    }
}
