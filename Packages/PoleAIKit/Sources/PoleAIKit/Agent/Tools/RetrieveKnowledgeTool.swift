import Foundation
import SwiftData
import PoleDomain

/// `retrieve_knowledge` —— RAG 工具,从本地知识库语义搜索相关 chunk 拼回 LLM。
///
/// **用途**:补足 LLM 训练数据没有的领域知识 — 规则细节、赛道介绍、车手百科、车队故事
/// 等**静态文本知识**。实时数据(积分/赛果)继续走 get_standings / get_session_results。
///
/// **跟其它 tool 的区别**:
/// - get_standings/find_round = 调动态 API 拉数字
/// - retrieve_knowledge = 在本地 SwiftData 向量库做语义检索,返 markdown 文本片段
///
/// **fetcher 闭包**:跟 ListFollowedTool 一样,modelContext 不能直接传(不 Sendable),
/// 由 caller 在 @MainActor 上下文绑定 retriever,通过 @Sendable closure 暴露 query 接口。
public struct RetrieveKnowledgeTool: AgentTool {
    /// 检索闭包 — 在 @MainActor 跑,内部用 KnowledgeRetriever.search,返 JSON 字符串。
    private let retriever: @MainActor @Sendable (
        _ query: String,
        _ topK: Int,
        _ series: String?
    ) async -> String

    public init(
        retriever: @escaping @MainActor @Sendable (
            _ query: String,
            _ topK: Int,
            _ series: String?
        ) async -> String
    ) {
        self.retriever = retriever
    }

    public let name = "retrieve_knowledge"
    public let description = """
    Retrieve domain knowledge from the local knowledge base via semantic search.
    Use this for STATIC knowledge questions:
    - Sport rules (DRS, sprint format, points, pit windows, regulations)
    - Circuit descriptions / characteristics / history
    - Driver/team biographies and narratives
    - Strategy concepts (tire, slipstream, pit stop tactics)

    DO NOT use for live data (current standings, race results, schedules) —
    use get_standings / find_round / get_session_results for those.

    Returns top-K text chunks with their source paths. Cite sources naturally
    in your reply if helpful, but rephrase the content in your own voice.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {
        "query": {"type": "string", "description": "Natural-language question or topic — what knowledge are you trying to retrieve?"},
        "series": {"type": "string", "enum": ["f1", "motogp", "wsbk", "fe"], "description": "Optional: filter to one series. Omit for cross-series knowledge."},
        "top_k": {"type": "integer", "description": "How many chunks to retrieve. Default 5, max 10.", "default": 5}
      },
      "required": ["query"],
      "additionalProperties": false
    }
    """

    /// `nonisolated` 让 Decodable conformance 在 nonisolated runningHint 里能 decode 不报警告。
    private nonisolated struct Args: Decodable {
        let query: String
        let series: String?
        let top_k: Int?
    }

    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            return L10n.t(zh: "查阅知识库…", en: "Searching knowledge base…")
        }
        let truncated = String(args.query.prefix(20))
        if let s = args.series {
            return L10n.t(
                zh: "查阅 \(s.uppercased()) 知识库:\(truncated)…",
                en: "Searching \(s.uppercased()) KB: \(truncated)…"
            )
        }
        return L10n.t(zh: "查阅知识库:\(truncated)…", en: "Searching KB: \(truncated)…")
    }

    public func execute(argumentsJSON: String) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8))
        let topK = min(max(args.top_k ?? 5, 1), 10)
        return await retriever(args.query, topK, args.series)
    }
}
