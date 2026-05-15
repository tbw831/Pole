import Foundation
import PoleDomain
import PoleMotorsportKit

/// `get_standings` —— 当前赛季积分榜(车手/车队/厂商)。
///
/// 车手 / 车队名通过 `MotorsportNames.driverFullName` / `teamName` 输出当前用户语言。
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

        var rows: [[String: Any]] = []
        switch (args.series, args.kind) {
        case ("f1", "driver"):
            let s = (try? await JolpicaClient.shared.fetchDriverStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.driver.fullName, series: .f1),
                 "points": st.points, "wins": st.wins,
                 "team_id": st.constructorIds.first ?? ""]
            }
        case ("f1", "team"), ("f1", "constructor"):
            let s = (try? await JolpicaClient.shared.fetchConstructorStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.constructor.name, series: .f1),
                 "points": st.points, "wins": st.wins]
            }
        case ("motogp", "driver"):
            let s = (try? await MotoGPClient.shared.fetchRiderStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.rider.fullName, series: .motogp),
                 "points": st.points,
                 "wins": st.raceWins,
                 "team": MotorsportNames.teamName(raw: st.team.name, series: .motogp),
                 "constructor": MotorsportNames.teamName(raw: st.constructor.name, series: .motogp)]
            }
        case ("motogp", "team"):
            let s = (try? await MotoGPClient.shared.fetchTeamStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.team.name, series: .motogp),
                 "points": st.points,
                 "riders": st.riderNames.map { MotorsportNames.driverFullName(rawFullName: $0, series: .motogp) }]
            }
        case ("motogp", "constructor"):
            let s = (try? await MotoGPClient.shared.fetchConstructorStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.constructor.name, series: .motogp),
                 "points": st.points]
            }
        case ("wsbk", "driver"):
            let s = (try? await WSBKClient.shared.fetchSSPRiderStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.rider.fullName, series: .wssp),
                 "points": st.points,
                 "country": st.rider.countryISO ?? ""]
            }
        case ("wsbk", "team"), ("wsbk", "constructor"):
            let s = (try? await WSBKClient.shared.fetchSSPBuilderStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.builder.name, series: .wssp),
                 "points": st.points,
                 "country": st.builder.countryISO ?? ""]
            }
        case ("fe", "driver"):
            let s = (try? await FormulaEClient.shared.fetchDriverStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.driver.fullName, series: .fe),
                 "points": st.points,
                 "team": MotorsportNames.teamName(raw: st.teamName, series: .fe),
                 "country": st.driver.countryISO2 ?? ""]
            }
        case ("fe", "team"), ("fe", "constructor"):
            let s = (try? await FormulaEClient.shared.fetchConstructorStandings()) ?? []
            rows = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.team.name, series: .fe),
                 "points": st.points]
            }
        default:
            return #"{"error":"unsupported series/kind combo"}"#
        }

        let payload: [String: Any] = ["series": args.series, "kind": args.kind, "rows": rows]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
