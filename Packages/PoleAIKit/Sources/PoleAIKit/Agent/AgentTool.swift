import Foundation
import PoleDomain

/// 给 LLM 暴露的"工具"——每条对应 app 内一个数据/能力入口。
/// 所有访问点都 `nonisolated`,因为 module-default MainActor 会让 protocol property 隐式 isolated,
/// 在 actor loop 里调用就成了 cross-actor。
public protocol AgentTool: Sendable {
    nonisolated var name: String { get }
    nonisolated var description: String { get }
    nonisolated var parametersJSON: String { get }
    func execute(argumentsJSON: String) async throws -> String
    /// 进度文案 — UI 在 running 状态展示("正在查找 F1 西班牙站..."),
    /// LLM 看不到这个字符串,只是给用户的 visual progress hint。
    /// 默认 nil,具体 tool 可以根据 args 给针对性的文案。
    nonisolated func runningHint(argumentsJSON: String) -> String?
}

public extension AgentTool {
    /// 默认实现:不给 hint(UI 退回到通用"调用中…")。
    nonisolated func runningHint(argumentsJSON: String) -> String? { nil }
}

/// 给 LLMClient 序列化用——只透 metadata 不透 execute。
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parametersJSON: String

    public nonisolated init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public extension AgentTool {
    nonisolated var definition: ToolDefinition {
        ToolDefinition(name: name, description: description, parametersJSON: parametersJSON)
    }
}

// MARK: - Tool 错误回灌 helper
//
// 工具内部网络/解析失败时必须告诉 LLM "拿不到数据" 而不是返空数组让它幻觉。
// 返回 `{"error":"...","series":"...","message":"..."}` 让 LLM 知道应该告知用户而不是猜。

public enum AgentToolJSON {
    /// fetch 失败 → 通知 LLM 数据没拿到。
    public static func fetchFailed(series: String? = nil, error: Error) -> String {
        var payload: [String: Any] = [
            "error": "fetch_failed",
            "message": error.localizedDescription
        ]
        if let s = series { payload["series"] = s }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? #"{"error":"fetch_failed"}"#
    }

    /// 通用 error JSON。
    public static func error(_ code: String, message: String? = nil) -> String {
        var payload: [String: Any] = ["error": code]
        if let m = message { payload["message"] = m }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? #"{"error":"\#(code)"}"#
    }
}

// MARK: - Messages

/// agent loop 内部的消息——封装 OpenAI 兼容的 4 种 role。
public enum AgentMessage: Sendable, Hashable {
    case system(String)
    case user(String)
    /// LLM 返回的 assistant 消息。
    case assistant(content: String?, toolCalls: [AgentToolCall])
    /// tool 执行结果——回灌给 LLM 让它继续推理。
    case tool(toolCallId: String, name: String, content: String)
}

public struct AgentToolCall: Sendable, Hashable {
    public let id: String
    public let name: String
    /// JSON 字符串(LLM 返回的 args 就是字符串形式,需二次 parse)
    public let arguments: String

    public nonisolated init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Events(给 UI 显示进度用)

public enum AgentEvent: Sendable {
    /// `runningHint` — 进度文案,UI 用来在 spinner 旁边显示动态描述,可以为 nil。
    case toolStarted(name: String, arguments: String, runningHint: String?)
    case toolFinished(name: String, result: String)
    /// 流式 chunk —— UI 应追加到当前 assistant bubble。每 chunk 1-N 字。
    case assistantTextChunk(String)
    case error(String)
}

// MARK: - Errors

public enum AgentError: Error, LocalizedError {
    case maxStepsExceeded
    case llmFailed(Error)
    case noResponse

    public var errorDescription: String? {
        switch self {
        case .maxStepsExceeded:  return L10n.t(zh: "agent 多次调用工具仍未给出答案", en: "Agent exceeded max tool steps without an answer")
        case .llmFailed(let e):  return L10n.t(zh: "LLM 调用失败:\(e.localizedDescription)", en: "LLM call failed: \(e.localizedDescription)")
        case .noResponse:        return L10n.t(zh: "LLM 返回空", en: "LLM returned empty")
        }
    }
}
