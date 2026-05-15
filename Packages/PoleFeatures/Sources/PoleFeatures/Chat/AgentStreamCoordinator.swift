import Foundation
import SwiftData
import NaturalLanguage   // NLLanguage,RetrieveKnowledgeTool 闭包内传给 KnowledgeRetriever
import PoleDomain
import PoleAIKit

/// 把 `AgentRuntime` + 7 个 tool 的搭建 / 运行 / 结果摘要逻辑从 `ChatViewModel` 抽出来。
///
/// **职责边界**:
/// - 构造 tool 列表(`FindRound` 等 7 个)
/// - 持有 `AgentRuntime` 实例
/// - 暴露一个 `run(...)` thin wrapper 转发到 `runtime.run`
/// - 提供"tool 返回 JSON → 人类可读 preview"的解析(`humanPreview` / `isErrorResult`)
///
/// **不处理**:bubbles / streamingText / SwiftData 写入 —— 那些状态属于 ChatViewModel。
/// 事件回调依然由 ViewModel.handleEvent 接收(因为要写 bubble 数组,跨这两个对象边界传字典太啰嗦)。
///
/// 不是 `@Observable` — 不暴露任何状态给 view。`@MainActor` 保证创建 tool 闭包时
/// 能直接捕获 modelContext(`ModelContext` 不 Sendable,放 MainActor 最自然)。
@MainActor
public final class AgentStreamCoordinator {

    /// ISO8601DateFormatter 在 iOS 7+ 是 thread-safe,共享实例避免 list_followed 工具
    /// 每条 follow item 重新构造 formatter(关注 N 人 = N 次 alloc)。
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private let runtime: AgentRuntime

    public init(modelContext: ModelContext) {
        // 7 个 tool —— ListFollowedTool / RetrieveKnowledgeTool 的 fetcher 是 @MainActor 闭包,
        // 可直接捕获 modelContext;返 JSON String 跨 actor 边界(避免传 SwiftData @Model 引用)。
        let listFollowed = ListFollowedTool(fetcher: { @MainActor in
            let items = FollowStore(context: modelContext).all()
            let rows: [[String: Any]] = items.map { item in
                [
                    "kind": item.kindRaw,
                    "series": item.seriesRaw,
                    "name": item.localizedDisplayName,
                    "ref_id": item.refId,
                    "added_at": AgentStreamCoordinator.iso8601.string(from: item.addedAt)
                ]
            }
            let payload: [String: Any] = ["count": rows.count, "items": rows]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "{}"
        })
        let retrieveKnowledge = RetrieveKnowledgeTool(retriever: { @MainActor query, topK, series in
            let retriever = KnowledgeRetriever(context: modelContext)
            // query 语言跟 L10n 走;主语言中文走 zh 模型,主语言英文走 en 模型
            let lang: NLLanguage = (L10n.effective == .en) ? .english : .simplifiedChinese
            let hits = await retriever.search(query: query, topK: topK, series: series, language: lang)
            let rows: [[String: Any]] = hits.map { hit in
                [
                    "text": hit.text,
                    "source": hit.source,
                    "series": hit.series ?? "",
                    "topic": hit.topic ?? "",
                    "score": Double(hit.score)   // Float 不可直接 JSON, 转 Double
                ]
            }
            let payload: [String: Any] = [
                "query": query,
                "count": rows.count,
                "hits": rows
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "{}"
        })
        let tools: [any AgentTool] = [
            FindRoundTool(),
            GetSessionResultsTool(),
            GetStandingsTool(),
            GetDriverHistoryTool(),
            AddToCalendarTool(),
            listFollowed,
            retrieveKnowledge
        ]
        self.runtime = AgentRuntime(tools: tools)
    }

    /// thin wrapper —— 转发到 runtime.run,签名与 ChatViewModel 原来的 inline 调用完全一致。
    /// `onEvent` 由 ChatViewModel 提供,事件里要改 bubbles 数组(那个状态属于 ViewModel)。
    func run(
        userMessage: String,
        history: [AgentMessage],
        systemPrompt: String,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async throws {
        try await runtime.run(
            userMessage: userMessage,
            history: history,
            systemPrompt: systemPrompt,
            onEvent: onEvent
        )
    }

    // MARK: - tool 结果摘要(从 JSON 提取关键字段做"人类可读" preview)

    /// 检查 tool 返回 JSON 是否含 "error" 字段 — 用于决定 final status 是 done 还是 failed。
    static func isErrorResult(result: String) -> Bool {
        guard let data = result.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["error"] != nil
    }

    /// JSON tool 结果 → 一行展示文案(豆包 / Cursor / Claude 同款 preview)。
    /// 失败时返"失败:错误信息";其它每个 tool 按字段挑最重要的概览。
    static func humanPreview(name: String, result: String) -> String {
        // 错误优先:tool 包了 error 字段直接显示
        guard let data = result.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let err = obj["error"] as? String {
            return L10n.t(zh: "失败:\(err)", en: "Failed: \(err)")
        }
        switch name {
        case "find_round":
            if let events = obj["events"] as? [[String: Any]] {
                if let first = events.first, let title = first["headline"] as? String ?? first["name"] as? String {
                    if events.count == 1 { return title }
                    return L10n.t(zh: "\(title) 等 \(events.count) 场",
                                  en: "\(title) and \(events.count - 1) more")
                }
                return L10n.t(zh: "\(events.count) 场赛事", en: "\(events.count) events")
            }
        case "get_session_results":
            if let rows = obj["rows"] as? [[String: Any]] {
                return L10n.t(zh: "\(rows.count) 名结果", en: "\(rows.count) results")
            }
        case "get_standings":
            if let rows = obj["rows"] as? [[String: Any]] {
                let series = (obj["series"] as? String)?.uppercased() ?? ""
                let entries = L10n.t(zh: "\(rows.count) 名", en: "\(rows.count) entries")
                return series.isEmpty ? entries : "\(series) · \(entries)"
            }
        case "get_driver_history":
            if let history = obj["history"] as? [[String: Any]] {
                return L10n.t(zh: "\(history.count) 场历史", en: "\(history.count) past races")
            }
        case "add_to_calendar":
            if let ok = obj["ok"] as? Bool {
                return ok
                    ? L10n.t(zh: "已添加到日历", en: "Added to calendar")
                    : L10n.t(zh: "添加失败", en: "Add failed")
            }
        case "list_followed":
            if let count = obj["count"] as? Int {
                return count == 0
                    ? L10n.t(zh: "暂无关注", en: "Nothing followed")
                    : L10n.t(zh: "\(count) 项关注", en: "\(count) followed")
            }
        default: break
        }
        return ""
    }
}
