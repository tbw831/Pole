import Foundation

/// `list_followed` —— 列出当前关注的车手/车队。
/// fetcher 强制 `@MainActor`:SwiftData ModelContext 必须在 MainActor 访问;
/// 闭包内部可以直接捕获 MainActor-isolated 的 ModelContext 而无需 MainActor.run 包裹。
/// 返回 JSON String 跨 actor 边界(避免传 SwiftData @Model 引用)。
public struct ListFollowedTool: AgentTool {
    private let fetcher: @MainActor @Sendable () async -> String

    public init(fetcher: @MainActor @Sendable @escaping () async -> String) {
        self.fetcher = fetcher
    }

    public let name = "list_followed"
    public let description = """
    List items the user is currently following (drivers, teams). Use to know what the user cares about
    before recommending or filtering content.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {},
      "additionalProperties": false
    }
    """

    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        L10n.t(zh: "读取关注列表…", en: "Reading your follows…")
    }

    public func execute(argumentsJSON: String) async throws -> String {
        await fetcher()
    }
}
