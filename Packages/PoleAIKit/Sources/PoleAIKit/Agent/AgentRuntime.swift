import Foundation

/// agent loop 主控:LLM 流式推理 → 工具调用 → 结果回灌 → 循环到给出最终文本。
public actor AgentRuntime {
    private let llm: LLMClient
    private let tools: [String: any AgentTool]
    private let model: String
    private let maxSteps: Int

    public init(
        llm: LLMClient = .shared,
        tools: [any AgentTool],
        model: String = "deepseek-v4-flash",
        maxSteps: Int = 10  // RAG-like 流程: standings + find_round + get_session_results × 2-3 = 4-5 步,
                            // 加 LLM 思考轮次至少留 10 步余量,避免 maxStepsExceeded
    ) {
        self.llm = llm
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        self.model = model
        self.maxSteps = maxSteps
    }

    /// 执行一次对话——流式返事件给 UI,边接收边显示。
    public func run(
        userMessage: String,
        history: [AgentMessage] = [],
        systemPrompt: String,
        onEvent: @MainActor @Sendable (AgentEvent) -> Void
    ) async throws {
        var messages: [AgentMessage] = [.system(systemPrompt)] + history + [.user(userMessage)]
        let toolDefs = tools.values.map { $0.definition }

        for _ in 0..<maxSteps {
            // 用户取消(ChatViewModel.stop 调 currentRunTask?.cancel)→ 立即抛 CancellationError,
            // 上层 catch 会 flush streaming + 复位 isThinking。
            try Task.checkCancellation()

            // 流式拉一轮 LLM 响应,边收边累加
            var contentBuffer = ""
            var toolBuffers: [Int: (id: String?, name: String, args: String)] = [:]
            var finishReason: String?

            let stream = await llm.chatStream(messages: messages, tools: toolDefs, model: model)
            do {
                for try await chunk in stream {
                    try Task.checkCancellation()
                    let textDelta = chunk.contentDelta ?? chunk.reasoningContentDelta
                    if let c = textDelta, !c.isEmpty {
                        contentBuffer += c
                        await onEvent(.assistantTextChunk(c))
                    }
                    for delta in chunk.toolCallsDelta {
                        var entry = toolBuffers[delta.index] ?? (id: nil, name: "", args: "")
                        if let id = delta.id { entry.id = id }
                        if let n = delta.nameDelta { entry.name += n }
                        if let a = delta.argumentsDelta { entry.args += a }
                        toolBuffers[delta.index] = entry
                    }
                    if let r = chunk.finishReason { finishReason = r }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw AgentError.llmFailed(error)
            }
            _ = finishReason

            // 拼装完整 assistant message
            let toolCalls: [AgentToolCall] = toolBuffers
                .sorted(by: { $0.key < $1.key })
                .compactMap { (_, v) in
                    guard let id = v.id, !v.name.isEmpty else { return nil }
                    return AgentToolCall(id: id, name: v.name, arguments: v.args)
                }
            let assistantMsg = AgentMessage.assistant(
                content: contentBuffer.isEmpty ? nil : contentBuffer,
                toolCalls: toolCalls
            )
            messages.append(assistantMsg)

            // 没 tool_calls = 终态
            if toolCalls.isEmpty {
                if contentBuffer.isEmpty {
                    await onEvent(.error("LLM 没返回内容"))
                }
                return
            }

            // 通知 UI tool 开始(带 runningHint 供 UI 展示进度文案)
            for call in toolCalls {
                let hint = tools[call.name]?.runningHint(argumentsJSON: call.arguments)
                await onEvent(.toolStarted(name: call.name, arguments: call.arguments, runningHint: hint))
            }

            // 并行执行
            let results = await withTaskGroup(of: (AgentToolCall, String).self, returning: [(AgentToolCall, String)].self) { group in
                for call in toolCalls {
                    group.addTask { [tools] in
                        let result: String
                        if let tool = tools[call.name] {
                            do {
                                result = try await tool.execute(argumentsJSON: call.arguments)
                            } catch {
                                let errPayload: [String: Any] = [
                                    "error": "tool_execution_failed",
                                    "tool": call.name,
                                    "message": error.localizedDescription
                                ]
                                let data = (try? JSONSerialization.data(withJSONObject: errPayload)) ?? Data()
                                result = String(data: data, encoding: .utf8) ?? "{}"
                            }
                        } else {
                            let available = Array(tools.keys)
                            let errPayload: [String: Any] = ["error": "unknown_tool", "available": available]
                            let data = (try? JSONSerialization.data(withJSONObject: errPayload)) ?? Data()
                            result = String(data: data, encoding: .utf8) ?? "{}"
                        }
                        return (call, result)
                    }
                }
                var collected: [(AgentToolCall, String)] = []
                for await pair in group { collected.append(pair) }
                return collected
            }

            // 回灌 tool 结果 + 通知 UI
            for (call, result) in results {
                messages.append(.tool(toolCallId: call.id, name: call.name, content: result))
                await onEvent(.toolFinished(name: call.name, result: result))
            }
        }

        throw AgentError.maxStepsExceeded
    }
}
