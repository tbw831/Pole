import Foundation
import PoleDomain
import PoleMotorsportKit

/// `get_driver_history` —— 单车手赛季 round-by-round 表现。
///
/// 通过 `MotorsportRegistry` 单点 dispatch:fuzzy 匹配 + 历史拉取已在各 series 的
/// `anyDriverHistoryJSON` 里完成,本 tool 不再 switch 三个 client。
/// 模糊匹配支持中文 / 英文 / 姓 / 含重音字符(Pérez / Sainz / Hülkenberg 等),
/// 输出 name 走 Localization 中文化(zh 模式)。
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
        guard let service = MotorsportRegistry.service(forId: args.series) else {
            return AgentToolJSON.error("unsupported_series", message: args.series)
        }
        return await service.anyDriverHistoryJSON(driverQuery: args.driver_name)
    }
}
