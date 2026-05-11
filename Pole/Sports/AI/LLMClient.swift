import Foundation
import os

private enum LLMLogger {
    nonisolated static let log = Logger(subsystem: "com.tiebowen.Pole", category: "LLMClient")
    nonisolated static func warning(_ msg: String) { log.warning("\(msg, privacy: .public)") }
}

public enum LLMError: Error, LocalizedError {
    case invalidResponse(Int)
    case network(Error)
    case decoding(Error)
    case empty
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return "LLM HTTP \(code)"
        case .network(let e):            return L10n.t(zh: "LLM 网络异常:\(e.localizedDescription)", en: "LLM network error: \(e.localizedDescription)")
        case .decoding(let e):           return L10n.t(zh: "LLM 解析失败:\(e.localizedDescription)", en: "LLM decode failed: \(e.localizedDescription)")
        case .empty:                     return L10n.t(zh: "LLM 返回空", en: "LLM returned empty")
        case .missingAPIKey:             return L10n.t(
            zh: "未配置 DeepSeek API Key(在 Xcode xcconfig 设 DS_API_KEY)",
            en: "DeepSeek API Key not configured (set DS_API_KEY in xcconfig)"
        )
        }
    }
}

/// LLM 客户端——用 DeepSeek `deepseek-v4-flash`(thinking: disabled,非推理模式)。
/// 标准 OpenAI 兼容协议。
///
/// API key 来源(优先级):
///   1. `Info.plist` `DSAPIKey` 字段(推荐,xcconfig 注入,不入仓库)
///   2. 环境变量 `DS_API_KEY`(本地 dev 走 Xcode scheme env vars,user-specific 不入库)
///
/// 缺失时 UI 自动弹 missingAPIKey 错误提示。具体配置方法见 docs/api-key-setup.md。
///
/// **警告**:**绝不要**在源码里硬编码 key——commit 进库 / binary reverse 都会泄露。
/// 上线前应:① 改走自有代理服务,key 在服务端 ② 客户端只持代理签名 token。
public actor LLMClient {
    public static let shared = LLMClient()

    private let apiKey: String = {
        if let v = Bundle.main.object(forInfoDictionaryKey: "DSAPIKey") as? String, !v.isEmpty {
            return v
        }
        if let v = ProcessInfo.processInfo.environment["DS_API_KEY"], !v.isEmpty {
            return v
        }
        // 不再硬编码 fallback — 防止仓库泄露 / binary reverse 拿到 key。
        // 本地开发请走以下两条路径之一:
        //   ① Mac 端 Xcode → Edit Scheme → Run → Environment Variables 添加 DS_API_KEY
        //      (user-specific scheme 不会 commit,见 docs/api-key-setup.md)
        //   ② 在 Info.plist 加 DSAPIKey 字段,通过 xcconfig 注入(.gitignore 已忽略 *.xcconfig.local)
        // key 缺失时 UI 自动弹 LLMError.missingAPIKey 提示配置。
        return ""
    }()

    private let endpoint = URL(string: "https://api.deepseek.com/v1/chat/completions")!
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    private func makeRequest(body: Data, accept: String) -> URLRequest {
        // 30s 超时:DeepSeek 偶发服务端 hang 时不让 isThinking 永远 true 卡住 UI;
        // 流式场景该值是单次连接保持上限,正常流式答复不会触发(每秒至少有 chunk)。
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    /// 通用 chat completion——给 system prompt + user prompt,返回 assistant content。
    public func chat(system: String?, user: String, model: String = "deepseek-v4-flash", temperature: Double = 0.3) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        var messages: [Message] = []
        // 全局 persona 前缀:让所有 LLM 输出都站在"赛车助手"角度,不要自称 DeepSeek/AI/语言模型。
        // 跟 caller 给的 system 拼接(persona 在前,任务规则在后)。
        let personaSystem = Self.racingPersonaPrefix + (system.map { "\n\n" + $0 } ?? "")
        messages.append(Message(role: "system", content: personaSystem))
        messages.append(Message(role: "user", content: user))

        let body = ChatRequest(model: model, messages: messages, temperature: temperature,
                               thinking: .init(type: "disabled"))
        let request = makeRequest(body: try JSONEncoder().encode(body), accept: "application/json")

        // 1 次 5xx / network 重试 + 30s 总超时,DeepSeek 偶发故障不直接给用户失败提示。
        return try await Self.withRetry {
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await self.session.data(for: request)
            } catch {
                throw LLMError.network(error)
            }
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse(-1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LLMError.invalidResponse(http.statusCode)
            }
            do {
                let decoded = try self.decoder.decode(ChatResponse.self, from: data)
                let msg = decoded.choices.first?.message
                let content = msg?.content ?? msg?.reasoning_content
                guard let text = content, !text.isEmpty else {
                    throw LLMError.empty
                }
                return text
            } catch let err as LLMError {
                throw err
            } catch {
                throw LLMError.decoding(error)
            }
        }
    }

    // MARK: - 全局 persona

    /// 让所有 LLM 输出永远站在 "Pole" 角色 — 不要自称 DeepSeek / AI / 大模型 / 通用助手。
    /// 拼到所有 chat() 调用的 system 段最前面。
    private static var racingPersonaPrefix: String {
        L10n.t(
            zh: """
            你是 Pole —— 一个专注 F1 / MotoGP / WorldSBK / Formula E 的赛车专家。
            硬性规则:
            - 永远以"赛车助手"身份回答,不要自称 "AI" / "语言模型" / "DeepSeek" / "通用助手"
            - 不需要时不要自我介绍,直接回答用户问题
            - 不知道就说"我也不确定",绝不编造车手名 / 圈速 / 历史数据
            """,
            en: """
            You are Pole — a racing assistant focused on F1 / MotoGP / WorldSBK / Formula E.
            Hard rules:
            - Always answer as a racing assistant. Do NOT identify yourself as "AI" / "LLM" / "DeepSeek" / "general assistant"
            - No self-introduction unless asked. Just answer the question
            - Say "I'm not sure" when uncertain. Never fabricate names / lap times / historical data
            """
        )
    }

    // MARK: - 重试 helper

    /// 1 次 5xx / network 重试 + 1.5s 退避;decoding / empty 不重试(数据问题重试也无救)。
    /// 总超时由调用方包外层 withTimeout 控制(此处用 Task.sleep 退避不阻塞 actor)。
    private static func withRetry<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let err as LLMError {
            // Swift switch case 联合 pattern 必须共享绑定变量,这里用 if-else 替代
            let shouldRetry: Bool = {
                switch err {
                case .invalidResponse(let code): return code >= 500 && code < 600
                case .network:                   return true
                default:                          return false
                }
            }()
            if shouldRetry {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                return try await work()    // 第二次失败直接抛
            }
            throw err
        }
    }

    // MARK: - Tools-aware chat (agent loop 用)

    /// 多轮 tool calling 的 chat completion。messages 含完整对话+tool 结果回灌,tools 给 LLM 看的 schema。
    public func chatWithTools(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        model: String = "deepseek-v4-flash",
        temperature: Double = 0.3
    ) async throws -> AgentMessage {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        let body = Self.buildToolsBody(messages: messages, tools: tools, model: model, temperature: temperature, stream: false)
        let request = makeRequest(body: body, accept: "application/json")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse(http.statusCode)
        }
        do {
            let decoded = try decoder.decode(ToolsResponse.self, from: data)
            guard let choice = decoded.choices.first else { throw LLMError.empty }
            let toolCalls = (choice.message.tool_calls ?? []).map { dto in
                AgentToolCall(id: dto.id, name: dto.function.name, arguments: dto.function.arguments)
            }
            return .assistant(content: choice.message.content, toolCalls: toolCalls)
        } catch {
            throw LLMError.decoding(error)
        }
    }

    // MARK: - body 构造(用 JSONSerialization 直接拼,字段是 dynamic 的不便用 Codable)

    private nonisolated static func buildToolsBody(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        model: String,
        temperature: Double,
        stream: Bool = false
    ) -> Data {
        var msgs: [[String: Any]] = []
        for m in messages {
            switch m {
            case .system(let s):
                msgs.append(["role": "system", "content": s])
            case .user(let s):
                msgs.append(["role": "user", "content": s])
            case .assistant(let content, let toolCalls):
                var msg: [String: Any] = ["role": "assistant"]
                msg["content"] = content ?? NSNull()
                if !toolCalls.isEmpty {
                    msg["tool_calls"] = toolCalls.map { tc in
                        [
                            "id": tc.id,
                            "type": "function",
                            "function": [
                                "name": tc.name,
                                "arguments": tc.arguments
                            ]
                        ] as [String: Any]
                    }
                }
                msgs.append(msg)
            case .tool(let id, let name, let content):
                msgs.append([
                    "role": "tool",
                    "tool_call_id": id,
                    "name": name,
                    "content": content
                ])
            }
        }

        let toolsArr: [[String: Any]] = tools.map { tool in
            let params: Any = (try? JSONSerialization.jsonObject(
                with: tool.parametersJSON.data(using: .utf8) ?? Data(),
                options: []
            )) ?? ["type": "object", "properties": [:]]
            return [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": params
                ]
            ] as [String: Any]
        }

        var body: [String: Any] = [
            "model": model,
            "messages": msgs,
            "temperature": temperature,
            "thinking": ["type": "disabled"]
        ]
        if !toolsArr.isEmpty {
            body["tools"] = toolsArr
            body["tool_choice"] = "auto"
        }
        if stream {
            body["stream"] = true
        }
        return (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
    }

    // MARK: - SSE Streaming

    /// 流式 chat —— 同 chatWithTools 但实时返 chunk(增量 content + 增量 tool_calls)。
    /// 流式时 tool_calls 也是分片来的(delta.tool_calls[i].function.arguments 增量),caller 累加。
    public func chatStream(
        messages: [AgentMessage],
        tools: [ToolDefinition],
        model: String = "deepseek-v4-flash",
        temperature: Double = 0.3
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let key = apiKey
        guard !key.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: LLMError.missingAPIKey) }
        }
        let body = Self.buildToolsBody(
            messages: messages, tools: tools, model: model,
            temperature: temperature, stream: true
        )
        let request = makeRequest(body: body, accept: "text/event-stream")
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.invalidResponse(-1))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: LLMError.invalidResponse(http.statusCode))
                        return
                    }

                    var consecutiveDecodeFailures = 0
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        // 老逻辑 `try? decode` 静默吞错让 DeepSeek 改 schema 时对话只是"卡住"无法定位。
                        // 现在 do/catch:单 chunk 失败 log + 跳过(避免心跳 chunk 也整流挂);
                        // 连续 5 个 chunk 都失败说明 schema 实质变更,抛错让 UI 显示。
                        let chunk: StreamResponseDTO
                        do {
                            chunk = try JSONDecoder().decode(StreamResponseDTO.self, from: data)
                            consecutiveDecodeFailures = 0
                        } catch {
                            consecutiveDecodeFailures += 1
                            LLMLogger.warning("SSE chunk decode failed (\(consecutiveDecodeFailures)/5): \(error.localizedDescription)")
                            if consecutiveDecodeFailures >= 5 {
                                continuation.finish(throwing: LLMError.decoding(error))
                                return
                            }
                            continue
                        }
                        if let delta = chunk.choices.first?.delta {
                            let parsed = StreamChunk(
                                contentDelta: delta.content,
                                reasoningContentDelta: delta.reasoning_content,
                                toolCallsDelta: delta.tool_calls?.map { dto in
                                    StreamChunk.ToolCallDelta(
                                        index: dto.index,
                                        id: dto.id,
                                        nameDelta: dto.function?.name,
                                        argumentsDelta: dto.function?.arguments
                                    )
                                } ?? [],
                                finishReason: chunk.choices.first?.finish_reason
                            )
                            continuation.yield(parsed)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Stream chunk types

    public struct StreamChunk: Sendable {
        public let contentDelta: String?
        public let reasoningContentDelta: String?
        public let toolCallsDelta: [ToolCallDelta]
        public let finishReason: String?

        public struct ToolCallDelta: Sendable {
            public let index: Int
            public let id: String?
            public let nameDelta: String?
            public let argumentsDelta: String?
        }
    }

    private struct StreamResponseDTO: Sendable, nonisolated Decodable {
        struct Choice: Sendable, nonisolated Decodable {
            let delta: Delta
            let finish_reason: String?
        }
        struct Delta: Sendable, nonisolated Decodable {
            let content: String?
            let reasoning_content: String?
            let tool_calls: [DeltaToolCallDTO]?
        }
        struct DeltaToolCallDTO: Sendable, nonisolated Decodable {
            let index: Int
            let id: String?
            let function: DeltaFn?
        }
        struct DeltaFn: Sendable, nonisolated Decodable {
            let name: String?
            let arguments: String?
        }
        let choices: [Choice]
    }

    // MARK: - tools-aware response DTO

    private struct ToolsResponse: Sendable, nonisolated Decodable {
        struct Choice: Sendable, nonisolated Decodable {
            let message: Message
            let finish_reason: String?
        }
        struct Message: Sendable, nonisolated Decodable {
            let role: String
            let content: String?
            let reasoning_content: String?
            let tool_calls: [ToolCallDTO]?
        }
        struct ToolCallDTO: Sendable, nonisolated Decodable {
            let id: String
            let function: FunctionDTO
        }
        struct FunctionDTO: Sendable, nonisolated Decodable {
            let name: String
            let arguments: String
        }
        let choices: [Choice]
    }

    // MARK: - 高阶 helper:追问建议(基于上一轮对话生成 3 条接续问题)

    /// 基于上一轮 user/assistant 对话,生成 3 条用户可能想接着问的简短追问。
    /// LLM 输出 JSON 数组,失败返空。
    public func suggestFollowUps(lastUser: String, lastAssistant: String) async throws -> [String] {
        let system = L10n.t(
            zh: """
            你是赛车赛事助手的"追问建议"生成器。
            根据上一轮 user 提问和 assistant 回答,生成 3 条用户可能想接着问的简短追问。

            要求:
            - 每条追问 ≤ 12 个汉字,口语化
            - 必须基于对话主题自然延伸,不要跳话题
            - 不重复用户已经问过的内容
            - 中英文混排时**不要在中英之间留空格**(写"Verstappen还能赢吗",不写"Verstappen 还能赢吗")
            - 车手 / 车队名优先用中文译名(维斯塔潘、汉密尔顿、法拉利等)
            - 严格只输出 JSON 数组(不要 markdown、不要解释、不要前后缀文字)
            - 形如:["问题1","问题2","问题3"]
            """,
            en: """
            You are a "follow-up suggestion" generator for a racing assistant.
            Given the last user/assistant exchange, produce 3 short follow-up questions.

            Rules:
            - Each ≤ 8 words, conversational tone
            - Must extend the topic naturally; don't switch topics
            - Don't repeat what the user already asked
            - Output ONLY a JSON array (no markdown, no explanation, no extra text)
            - Format: ["q1","q2","q3"]
            """
        )
        let user = L10n.t(
            zh: """
            上一轮对话:
            用户:\(lastUser)
            助手:\(lastAssistant)

            请生成 JSON 数组(3 条):
            """,
            en: """
            Last exchange:
            User: \(lastUser)
            Assistant: \(lastAssistant)

            Output JSON array (3 items):
            """
        )
        let raw = try await chat(system: system, user: user, temperature: 0.7)
        // LLM 偶尔会用 ```json ... ``` 包裹,先剥掉
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return Array(arr.prefix(3))
    }

    // MARK: - 高阶 helper:首屏推荐问题(可基于"关注车手"等上下文)

    /// 生成 4 条首屏推荐问题。`followedNames` 给 LLM 当上下文,出更"贴脸"的问题。
    /// `exclude` 让 LLM 避开当前已展示的几条,实现"换一换"的多样性。
    public func suggestStarterPrompts(followedNames: [String], exclude: [String]) async throws -> [String] {
        let system = L10n.t(
            zh: """
            你是赛车赛事 app 的"首页推荐问题"生成器。
            生成 4 条用户可能想点击的简短问题,作为首屏建议。

            要求:
            - 每条 ≤14 个汉字,口语化、自然,带轻微好奇感
            - 覆盖 F1 / MotoGP / WSBK 三个系列(混搭,不要全一个)
            - 围绕赛程、积分榜、车手成绩、加日历、最近一场结果这些主题
            - 中英文混排时**不要在中英之间留空格**(写"Verstappen还能卫冕吗",不写"Verstappen 还能卫冕吗")
            - 车手 / 车队名优先用中文译名(维斯塔潘、汉密尔顿、法拉利、红牛等);
              没把握的中文译名用英文原名,但不与中文之间留空格
            - 严格只输出 JSON 数组,形如:["问题1","问题2","问题3","问题4"]
            - 不要 markdown、不要解释、不要前后缀文字
            """,
            en: """
            You generate "home screen prompt suggestions" for a racing app.
            Produce 4 short questions a user might want to tap.

            Rules:
            - Each ≤ 10 words, conversational, slightly curious tone
            - Cover F1 / MotoGP / WorldSBK (mix series, don't cluster on one)
            - Around: schedules, standings, driver form, add-to-calendar, latest results
            - Output ONLY a JSON array, format: ["q1","q2","q3","q4"]
            - No markdown, no explanation, no extra text
            """
        )
        var contextLines: [String] = []
        if !followedNames.isEmpty {
            let preview = followedNames.prefix(5).joined(separator: L10n.t(zh: "、", en: ", "))
            contextLines.append(L10n.t(
                zh: "用户关注的车手/车队:\(preview)。可以围绕他们出 1-2 条。",
                en: "User follows: \(preview). Include 1-2 questions about them."
            ))
        }
        if !exclude.isEmpty {
            let list = exclude.map { "- \($0)" }.joined(separator: "\n")
            contextLines.append(L10n.t(
                zh: "请避开以下已展示过的问题:\n\(list)",
                en: "Avoid these already-shown questions:\n\(list)"
            ))
        }
        let prompt = L10n.t(zh: "请生成 JSON 数组(4 条):", en: "Output JSON array (4 items):")
        let user = (contextLines.isEmpty ? "" : contextLines.joined(separator: "\n\n") + "\n\n") + prompt
        let raw = try await chat(system: system, user: user, temperature: 0.8)
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = cleaned.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return []
        }
        return Array(arr.prefix(4))
    }

    // MARK: - 高阶 helper:每日赛车冷知识(首屏卡片用)

    /// 生成 1 条赛车冷知识,50-80 字。失败抛错,UI 自然降级不显示。
    public func generateDailyTrivia() async throws -> String {
        let system = L10n.t(
            zh: """
            你是赛车冷知识生成器。
            给出 1 条简短有趣的赛车历史/规则/八卦冷知识,涉及 F1 / MotoGP / WSBK 任一系列。

            要求:
            - 50-80 字,口语化、带轻微好奇感
            - 必须真实(知名史实/著名规则/有据可查的轶事)
            - 不要"今天告诉你""你知道吗"等开场客套
            - 不要 markdown,直接给一段话
            - 优先选不太广为人知的(避开"舒马赫 7 冠""Senna 三冠"这种烂大街的)
            """,
            en: """
            You generate motorsport trivia.
            Give 1 short, interesting fact about racing history/rules/anecdotes from F1, MotoGP, or WorldSBK.

            Rules:
            - 35-60 words, conversational, slightly curious tone
            - Must be real (well-known history/rules/documented anecdote)
            - No "Did you know..." or filler intros
            - No markdown, plain paragraph
            - Prefer lesser-known facts (avoid clichés like "Schumacher's 7 titles" or "Senna's 3 titles")
            """
        )
        let user = L10n.t(zh: "请生成一条赛车冷知识:", en: "Generate one piece of racing trivia:")
        let raw = try await chat(system: system, user: user, temperature: 0.9)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 高阶 helper:赛事概览

    /// 输入:比赛标题 + 已经拼好的 JSON 数据上下文(results / standings 等);
    /// 输出:markdown 复盘文字,3-5 个看点 + 简短分析。
    public func generateRaceRecap(title: String, dataContextJSON: String) async throws -> String {
        let system = L10n.t(
            zh: """
            你是赛车比赛"赛事概览"作者。给一份比赛数据,输出极简精炼复盘,中文。

            要求(严格):
            - **总长 50-90 字**,最多 2 个看点(凝练优先)
            - 用 markdown 段落,每个看点用 "**看点 X:**" 起头,**只一句解释**
            - 关键数据(姓名/积分差/单圈时间)用 `**xxx**` 加粗
            - 段落间空行隔开
            - 加粗格式严格:只用 `**xxx**`,xxx 两侧不留空格;禁止 `***` / `__` / 嵌套加粗
            - 禁止 markdown 表格 / `#` 标题 / emoji / HTML
            - 只讲转折点和反差,不平铺直叙
            - 数据中没明确出现的内容(轮胎策略/天气等)**不要编**
            - 不要客套语 / "以下是…",直接进正文
            - 写够 3 个看点就停,不要凑字数
            """,
            en: """
            You write motorsport recaps in English. Given race data, output an extremely concise recap.

            Rules (strict):
            - **40-65 words total**; max 2 talking points (concise > complete)
            - Markdown paragraphs; each point starts with "**Point X:**" then **only one sentence**
            - Bold key data (names / point gaps / lap times) with `**xxx**`
            - Blank lines between paragraphs
            - Bold format strict: only `**xxx**` (no spaces around xxx); no `***` / `__` / nested bold
            - No markdown tables, no `#` headings, no emoji, no HTML
            - Only turning points and contrasts, no plain narration
            - Do NOT invent content not in the data
            - No filler phrases / "Here is...", go straight to content
            - Stop when 3 points are done; never pad
            """
        )
        let user = L10n.t(
            zh: """
            比赛:\(title)

            数据(JSON):
            \(dataContextJSON)

            请写赛事概览:
            """,
            en: """
            Race: \(title)

            Data (JSON):
            \(dataContextJSON)

            Write the recap:
            """
        )
        let raw = try await chat(system: system, user: user, temperature: 0.7)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 高阶 helper:车手简介

    /// 给定车手名字 + series,生成中文简介。
    public func fetchRiderBio(name: String, series: MotorsportSeries) async throws -> String {
        let seriesText: String = {
            switch series {
            case .f1:     return "F1"
            case .motogp: return "MotoGP"
            case .wssp:   return "WorldSBK / WorldSSP"
            case .fe:     return "Formula E"
            }
        }()
        let system = L10n.t(
            zh: """
            你是赛车运动百科助手。回答只用中文,不要客套语,不要使用 markdown。
            在事实不确定时直接说"不确定",不要编造。
            """,
            en: """
            You are a motorsport encyclopedia assistant. Reply in English only; no filler phrases, no markdown.
            If a fact is uncertain, say "uncertain" rather than inventing.
            """
        )
        let prompt = L10n.t(
            zh: """
            请用 100-120 字凝练介绍 \(seriesText) 车手 \(name),涵盖:
            - 国籍、出生年/年龄
            - 车队、车号
            - 主要荣誉(冠军、知名战绩)
            - 个人特点

            如果是中国车手或亚洲车手,优先用中文姓名。直接给段落,不要标题。
            """,
            en: """
            Write a concise 70-90 word bio of \(seriesText) rider/driver \(name), covering:
            - Nationality, birth year/age
            - Team and car number
            - Major honours (championships, notable results)
            - Personal style

            Output a single paragraph, no headings.
            """
        )
        return try await chat(system: system, user: prompt)
    }

    // MARK: - 高阶 helper:车手赛季表现总结

    /// 给定车手名 + series + 赛季积分数据 JSON,生成 50-90 字凝练表现总结。
    /// 输入 contextJSON 各 series 含义:
    /// - F1 / WSSP: 含 round-by-round 积分(rounds 数组)+ 当前 standings
    /// - MotoGP / FE: 仅 standings 汇总(无 round-by-round 数据源)
    public func generateDriverSeasonReview(
        driverName: String,
        series: MotorsportSeries,
        dataContextJSON: String
    ) async throws -> String {
        let seriesText: String = {
            switch series {
            case .f1:     return "F1"
            case .motogp: return "MotoGP"
            case .wssp:   return "WorldSSP"
            case .fe:     return "Formula E"
            }
        }()
        let system = L10n.t(
            zh: """
            你是赛车赛季观察员。给一个车手的赛季积分数据,输出极简凝练的表现总结,中文。
            要求(严格):
            - 总长 50-90 字,2-3 句话
            - 1 句概括(领跑 / 第几位 / 阶段表现) + 1 句具体看点(高潮 / 低谷 / 对比)
            - 关键数据(站次 / 总分 / 涨幅)用 `**xxx**` 加粗
            - 中英文混排时**不要在中英之间留空格**
            - 加粗格式严格:只用 `**xxx**`,xxx 两侧不留空格;禁止 `***` / `__` / 嵌套加粗
            - 禁止 markdown 表格 / `#` 标题 / emoji / HTML
            - 不要客套语 / "以下是…"等开场白
            - 数据中没明确出现的内容**不要编**
            """,
            en: """
            You are a season observer. Given a driver's season point data, output a
            concise season review in English.
            Rules (strict):
            - 30-55 words, 2-3 sentences
            - 1 summary line + 1 specific highlight or low point
            - Bold key data (round / total / gap) with `**xxx**` (no spaces around xxx)
            - No `***` / `__` / nested bold; no tables, no `#` headings, no emoji, no HTML
            - No filler / preamble
            - Do NOT invent content not in the data
            """
        )
        let prompt = L10n.t(
            zh: """
            车手:\(driverName)(\(seriesText))
            赛季积分数据(JSON):
            \(dataContextJSON)

            请写赛季表现总结:
            """,
            en: """
            Driver: \(driverName) (\(seriesText))
            Season points data (JSON):
            \(dataContextJSON)

            Write the season review:
            """
        )
        return try await chat(system: system, user: prompt, temperature: 0.6)
    }

    // MARK: - 高阶 helper:赛道亮点

    /// 给定赛道名 + 国家 + 系列,生成"赛道亮点"段落。150 字内,不同系列侧重点不同
    /// (F1 看高速 / MotoGP 看刹车点 / WSBK 看 hairpin / FE 看街道布局)。
    public func generateCircuitHighlight(
        circuitName: String,
        country: String,
        series: MotorsportSeries
    ) async throws -> String {
        let seriesText: String = {
            switch series {
            case .f1:     return "F1"
            case .motogp: return "MotoGP"
            case .wssp:   return "WorldSBK"
            case .fe:     return "Formula E"
            }
        }()
        let system = L10n.t(
            zh: """
            你是赛车赛道百科助手。回答只用中文,不要客套语。
            侧重该系列在这条赛道的特点(F1 重高速段 / MotoGP 重刹车点 / WSBK 重 hairpin 节奏 / FE 重街道弹性)。
            在事实不确定时直接说"不确定",不要编造圈纪录或具体数字。
            格式严格:可用 inline `**xxx**` 加粗(xxx 两侧不留空格);禁止表格 / `#` 标题 / `***` / `__` / HTML / emoji。
            """,
            en: """
            You are a motorsport circuit encyclopedia. Reply in English only, no filler.
            Focus on what makes this circuit notable for THIS series (F1 high-speed sectors / MotoGP braking zones / WSBK hairpin rhythm / FE street circuit traits).
            If a specific record or stat is uncertain, say "uncertain" instead of inventing.
            Format strict: inline `**xxx**` bold OK (no spaces around xxx); no tables, no `#` headings, no `***` / `__` / HTML / emoji.
            """
        )
        let prompt = L10n.t(
            zh: """
            请用 60-90 字介绍 \(seriesText) \(country) 站 \(circuitName) 赛道的亮点:
            - 1 个标志性弯角或赛段(名字 + 特点)
            - 该系列在这条赛道的 1 个看点(超车点 / 刹车点 / 圈速参考)

            直接给一段,不要分点。不要"以下是…"等开场白。凝练优先,不凑字数。
            """,
            en: """
            Write a 50-80 word highlight of \(circuitName) (\(country)) for \(seriesText):
            - 1 signature corner or sector (name + characteristic)
            - 1 angle that matters for THIS series (overtaking spot / braking zone / lap reference)

            Output a single paragraph, no bullet points, no "Here is..." preamble. Concise > complete.
            """
        )
        return try await chat(system: system, user: prompt)
    }

    // MARK: - DTOs

    private struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable, Sendable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let thinking: ThinkingConfig

        struct ThinkingConfig: Codable, Sendable {
            let type: String
        }
    }

    private struct ChatResponse: Sendable, nonisolated Decodable {
        struct Choice: Sendable, nonisolated Decodable {
            let message: Message
        }
        struct Message: Sendable, nonisolated Decodable {
            let role: String
            let content: String?
            let reasoning_content: String?
        }
        let choices: [Choice]
    }
}
