import Foundation

/// LLM 后端抽象 — 用于 DeepSeek / Apple Intelligence 双实现。
/// 本期只为 `LLMClient` 单 stream 入口提供 fallback,完整 agent tool calling 仍走 DeepSeek。
public protocol LLMProvider: Actor {
    var isAvailable: Bool { get async }

    /// 单 stream 接口 — 不带 tools。用于简单文本生成场景(Wikipedia 摘要、TriviaCard 等)。
    func generateText(systemPrompt: String, userMessage: String) async throws -> String
}
