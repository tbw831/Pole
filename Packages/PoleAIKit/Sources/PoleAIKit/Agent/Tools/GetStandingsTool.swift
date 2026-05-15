import Foundation
import PoleDomain
import PoleMotorsportKit

/// `get_standings` —— 当前赛季积分榜(车手/车队/厂商)。
///
/// 通过 `MotorsportRegistry` 单点 dispatch 到 series-specific service,本 tool 不再 switch 4 个 client。
/// 车手 / 车队名在各 series 的 `anyDriverStandingsJSON` 内部已经按 `MotorsportNames` 输出当前语言。
public struct GetStandingsTool: AgentTool {
    public init() {}

    public let name = "get_standings"
    public let description = """
    Get current season standings (drivers, teams, or manufacturers/constructors).
    Use when user asks about championship leaders, points, or rankings.
    Driver and team names are pre-localized to the user's language; use them as-is.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {
        "series": {"type": "string", "enum": ["f1", "motogp", "wsbk", "fe"]},
        "kind": {"type": "string", "enum": ["driver", "team", "constructor"]},
        "top": {"type": "integer", "description": "Limit to top N, default 10", "default": 10}
      },
      "required": ["series", "kind"],
      "additionalProperties": false
    }
    """

    /// `nonisolated` 让该 struct 脱离模块默认 @MainActor,Decodable conformance 能在
    /// nonisolated runningHint 里 decode 不报警告(Swift 6 module-default isolation 的常见坑)。
    private nonisolated struct Args: Decodable {
        let series: String
        let kind: String
        let top: Int?
    }

    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            return L10n.t(zh: "查询积分榜…", en: "Loading standings…")
        }
        let series = args.series.uppercased()
        let kindLabel: String
        switch args.kind {
        case "driver", "rider": kindLabel = L10n.t(zh: "车手榜", en: "drivers")
        case "team":            kindLabel = L10n.t(zh: "车队榜", en: "teams")
        case "constructor":     kindLabel = L10n.t(zh: "厂商榜", en: "constructors")
        default:                kindLabel = args.kind
        }
        return L10n.t(zh: "查询 \(series) \(kindLabel)…", en: "Loading \(series) \(kindLabel) standings…")
    }

    public func execute(argumentsJSON: String) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8))
        let top = args.top ?? 10

        guard let service = MotorsportRegistry.service(forId: args.series) else {
            return AgentToolJSON.error("unsupported_series", message: args.series)
        }

        // 各 series client 已经在 anyDriverStandingsJSON 里输出 `{"rows":[...]}`,
        // 这里把 series / kind 元信息合并进去给 LLM。
        let rowsJSON = await service.anyDriverStandingsJSON(kind: args.kind, top: top)
        guard
            let rowsData = rowsJSON.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: rowsData) as? [String: Any]
        else {
            return rowsJSON
        }
        // 把内层 rows 提出来(或转发 error)再补 series/kind。
        if let errCode = parsed["error"] as? String {
            var payload: [String: Any] = ["error": errCode, "series": args.series, "kind": args.kind]
            for (k, v) in parsed where k != "error" { payload[k] = v }
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            return String(data: data, encoding: .utf8) ?? rowsJSON
        }
        var payload: [String: Any] = ["series": args.series, "kind": args.kind]
        if let rows = parsed["rows"] { payload["rows"] = rows }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8) ?? rowsJSON
    }
}
