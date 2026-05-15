import Foundation
import SwiftUI
import SwiftData
import PoleDesignSystem
import PoleDomain
import PoleAIKit

/// 聊天 UI 用的"消息"——包含纯文本 + 工具调用步进卡片。
/// 每条 bubble 都对应一条持久化的 ChatMessage(id 一致)。
///
/// **拆分后**:此文件只保留"view 直接绑定的 UI 状态" + "publicly-callable 方法"
/// 三大块逻辑分别由 helper 承担:
/// - `AgentStreamCoordinator` — LLM runtime + tool 列表 + tool 结果摘要
/// - `ChatPersistence`       — ChatMessage SwiftData 双写 + Bubble 反序列化
/// - `ChatGreetingProvider`  — system prompt / 头部问候 / 静态文案
///
/// 这里只持有 `@Observable` 字段(bubbles / input / streamingText / followUps / isThinking),
/// 以及对三个 helper 的 strong reference。
@MainActor
@Observable
public final class ChatViewModel {

    /// 一条聊天消息(用户 / 助手 / 工具步进)。
    enum Bubble: Identifiable, Hashable {
        case user(id: UUID, text: String)
        case assistant(id: UUID, text: String)
        /// `runningHint` — UI 在 spinner 旁展示的进度文案,LLM 不可见;
        /// `startedAt` — 工具开始时间,显示耗时用;
        /// `finishedAt` — done/failed 后的完成时间(running 时为 nil)。
        case toolStep(
            id: UUID,
            name: String,
            status: ToolStatus,
            resultPreview: String?,
            runningHint: String?,
            startedAt: Date,
            finishedAt: Date?
        )

        var id: UUID {
            switch self {
            case .user(let id, _),
                 .assistant(let id, _),
                 .toolStep(let id, _, _, _, _, _, _):
                return id
            }
        }

        enum ToolStatus: Hashable { case running, done, failed }
    }

    // MARK: - Observable 状态(view 直接读)

    private(set) var bubbles: [Bubble] = []
    var input: String = ""
    private(set) var isThinking: Bool = false

    /// 输入是否可以发送 — view body 读取这里,把"trim + 非空 + 非思考中"的判定从 view 上提到 vm,
    /// 避免 view 里散落业务规则(N4 反模式)。
    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    /// 当前 session id —— UI 显示用,切换会话时变。
    private(set) var currentSessionID: UUID?

    /// 追问建议——回答完后由 LLM 基于上下文生成 3 条;用户发新消息时清空。
    private(set) var followUps: [String] = []

    /// 是否正在流式输出(有活跃的 streamingText)。
    /// 供 ChatView 的 Timer 节拍器判断是否需要持续滚动。
    var isStreaming: Bool { !streamingText.isEmpty }

    /// 流式中的 assistant 文本 — 流式期间只改这个属性,不污染 bubbles 数组。
    /// Stream 结束(runtime.run 返回)时合并进 bubbles。
    /// 性能关键:LazyVStack 看到 bubbles 没变就不重 diff,避免每个 chunk 都全 list 重算 ForEach。
    private(set) var streamingText: String = ""
    private(set) var streamingId: UUID?

    /// 把 bubbles 折叠成 RenderItem 列表 — 连续的 toolStep 合并成一个 toolGroup。
    /// 提到 ViewModel 作 derived 属性(view 不再每次 body 重算时调 view 内的 renderItems);
    /// SwiftUI @Observable 不自动 cache 但访问点单一,语义清晰。
    var renderedItems: [ChatView.RenderItem] {
        var items: [ChatView.RenderItem] = []
        var currentSteps: [ChatView.RenderItem.ToolStep] = []

        func flush() {
            guard !currentSteps.isEmpty else { return }
            items.append(.toolGroup(id: currentSteps.first!.id, steps: currentSteps))
            currentSteps = []
        }

        for bubble in bubbles {
            switch bubble {
            case .toolStep(let id, let name, let status, let preview, let hint, let startedAt, let finishedAt):
                currentSteps.append(.init(
                    id: id,
                    name: name,
                    status: status,
                    preview: preview,
                    runningHint: hint,
                    startedAt: startedAt,
                    finishedAt: finishedAt
                ))
            case .user, .assistant:
                flush()
                items.append(.message(bubble))
            }
        }
        flush()
        return items
    }

    // MARK: - 静态文案转发(view 仍按老 API 读)

    /// 系统 prompt — 根据 L10n.effective 切中英,LLM 用对应语种回复。
    /// 实际内容定义在 ChatGreetingProvider,这里只是转发避免 view 改源。
    var systemPrompt: String { ChatGreetingProvider.systemPrompt }

    var greetingHeaderTitle: String { ChatGreetingProvider.headerTitle }

    var greetingHeaderSubtitle: String { ChatGreetingProvider.headerSubtitle }

    // MARK: - 私有依赖

    private let coordinator: AgentStreamCoordinator
    private let persistence: ChatPersistence
    private var session: ChatSession?

    /// 用于多轮 LLM 上下文回灌——每次 send 后追加 user + 最终 assistant text。
    private var history: [AgentMessage] = []

    /// `@ObservationIgnored` 让 `@Observable` macro 不给它生成 ObservationTracked accessor
    /// (内部 task 句柄不需要触发 view 更新);
    /// `nonisolated(unsafe)` 让 `deinit`(默认 nonisolated)能直接 cancel。
    /// 实际所有 read/write 都在 @MainActor 方法内 + deinit 时(self 已无其它 ref),不会真并发。
    @ObservationIgnored
    nonisolated(unsafe) private var followUpTask: Task<Void, Never>?

    /// 当前正在跑的 send/regenerate task — 用来串行化避免 await suspension 期间
    /// 多个入口(send / regenerate / 语音 transcript 自动 send)同时改 history/bubbles 状态。
    /// `isThinking` 只是 UI 标志,不能当锁用。
    /// 同上:`@ObservationIgnored` + `nonisolated(unsafe)` 让 deinit 能 cancel,且不进 view observation。
    @ObservationIgnored
    nonisolated(unsafe) private var currentRunTask: Task<Void, Never>?

    public init(modelContext: ModelContext) {
        self.coordinator = AgentStreamCoordinator(modelContext: modelContext)
        self.persistence = ChatPersistence(context: modelContext)

        // crash/强杀后把停在 running 的 tool step 改 failed,避免历史对话里永远卡"工具调用中"
        self.persistence.recoverInterruptedToolSteps()

        // 启动恢复:有最近 session 就加载,没有就空着,首条消息时再建。
        if let last = persistence.allSessions().first {
            loadSession(last)
        }
    }

    /// ChatView 销毁时(切到别的 tab + 长期不回 / pop / app exit)取消挂起的 LLM stream / follow-up 任务,
    /// 避免后台继续吃 token、写 SwiftData、捕获 self 导致 EXC_BAD_ACCESS。
    /// `Task.cancel()` 本身是 thread-safe 的,普通 deinit(可能 nonisolated)调用也安全。
    deinit {
        currentRunTask?.cancel()
        followUpTask?.cancel()
    }

    // MARK: - 会话管理

    func loadSession(_ session: ChatSession) {
        followUpTask?.cancel()
        followUps = []
        self.session = session
        self.currentSessionID = session.id
        let loaded = persistence.loadSession(session)
        self.bubbles = loaded.bubbles
        self.history = loaded.history
    }

    func startNewSession() {
        followUpTask?.cancel()
        followUps = []
        bubbles = []
        history = []
        persistence.resetForNewSession()
        session = nil
        currentSessionID = nil
    }

    func deleteSession(_ s: ChatSession) {
        let isCurrent = (s.id == session?.id)
        persistence.delete(session: s)
        if isCurrent { startNewSession() }
    }

    // MARK: - 复制 / 再生成(消息底部操作行用)

    /// 把指定 assistant bubble 的文本拷到剪贴板。
    func copy(bubbleId: UUID) {
        guard let bubble = bubbles.first(where: { $0.id == bubbleId }),
              case .assistant(_, let text) = bubble else { return }
        UIPasteboard.general.string = text
    }

    /// 重新生成指定 assistant bubble:删掉它(及其后所有 tool step / assistant 续答),
    /// 找到上一条 user message 重发。
    func regenerate(bubbleId: UUID) async {
        await runSerially { await self._regenerateImpl(bubbleId: bubbleId) }
    }

    private func _regenerateImpl(bubbleId: UUID) async {
        guard !isThinking, let session else { return }
        guard let assistantIdx = bubbles.firstIndex(where: { $0.id == bubbleId }) else { return }
        // 向前找最近一条 user message
        let prefix = bubbles.prefix(assistantIdx)
        guard let lastUserIdx = prefix.lastIndex(where: {
            if case .user = $0 { return true } else { return false }
        }) else { return }
        guard case .user(_, let userText) = bubbles[lastUserIdx] else { return }

        // 删掉 user 之后所有 bubble + 对应的持久化 message
        // 必须 context.delete 真删,否则 msg.session=nil 只是断关系,
        // ChatMessage 实体仍在 store 里 — 多次 regenerate 后 db 会膨胀堆积孤儿对象。
        let toRemove = Array(bubbles[(lastUserIdx + 1)...])
        persistence.deleteMessages(ids: toRemove.map(\.id))
        bubbles.removeSubrange((lastUserIdx + 1)...)
        persistence.save()

        // 重建 history:从 bubbles 里捞出"重发的 user 之前"的 user/assistant 对(忽略 tool step)
        let priorBubbles = bubbles.prefix(lastUserIdx)   // 不含本次重发的 user
        let rebuiltHistory: [AgentMessage] = priorBubbles.compactMap { b -> AgentMessage? in
            switch b {
            case .user(_, let t):      return .user(t)
            case .assistant(_, let t): return .assistant(content: t, toolCalls: [])
            case .toolStep:            return nil
            }
        }
        history = rebuiltHistory   // 同步内存 history,避免下一次 send 累积错乱

        isThinking = true
        do {
            try await coordinator.run(
                userMessage: userText,
                history: rebuiltHistory,
                systemPrompt: systemPrompt,
                onEvent: { [weak self] event in
                    self?.handleEvent(event)
                }
            )
            flushStreamingToBubbles()
            persistence.save()
            persistence.touch(session: session)
        } catch is CancellationError {
            flushStreamingToBubbles()
            persistence.save()
        } catch {
            flushStreamingToBubbles()
            let errId = UUID()
            let errText = L10n.t(zh: "出错了:\(error.localizedDescription)",
                                  en: "Error: \(error.localizedDescription)")
            bubbles.append(.assistant(id: errId, text: errText))
            persistence.appendText(id: errId, role: .assistant, text: errText, to: session)
            persistence.save()
        }
        isThinking = false
        scheduleFollowUps()
    }

    // MARK: - 发送

    /// 公开 entry point — 串行包裹防止并发 send/regenerate 撞 history/bubbles 状态。
    func send() async {
        await runSerially { await self._sendImpl() }
    }

    /// 用户点"停止" — 取消当前 LLM stream / tool 调用 + 把残留 running tool step 标 failed。
    /// AgentRuntime 的 Task.checkCancellation 会让 stream 抛 CancellationError,
    /// 上层 catch 走 flush 分支(已存在的逻辑)。
    func stop() {
        currentRunTask?.cancel()
        followUpTask?.cancel()
        // 把 bubbles 里挂着 running 的 tool step 立即翻成 failed,UI 不要等 cancel 传过去
        let now = Date()
        let cancelLabel = L10n.t(zh: "已取消", en: "Cancelled")
        for (idx, b) in bubbles.enumerated() {
            if case .toolStep(let id, let name, .running, let preview, let hint, let startedAt, _) = b {
                bubbles[idx] = .toolStep(
                    id: id,
                    name: name,
                    status: .failed,
                    resultPreview: preview ?? cancelLabel,
                    runningHint: hint,
                    startedAt: startedAt,
                    finishedAt: now
                )
                persistence.cancelToolStep(id: id, at: now, cancelLabel: cancelLabel)
            }
        }
        persistence.save()
        HapticFeedback.warning()
    }

    /// 重试某个失败的 tool step — 把"该 step 之后所有 bubble" 删掉,
    /// 然后从对应的 user message 重新发起一轮 agent 跑。
    /// 实现复用 regenerate 路径:找到该 step 之前最近的 user → regenerate 后续 assistant。
    func retryToolStep(bubbleId: UUID) async {
        guard let stepIdx = bubbles.firstIndex(where: { $0.id == bubbleId }) else { return }
        // 向前找最近一条 user
        let prefix = bubbles.prefix(stepIdx)
        guard let lastUserIdx = prefix.lastIndex(where: {
            if case .user = $0 { return true } else { return false }
        }) else { return }
        // 找 user 后第一条 assistant 当 regenerate 锚点;没找到则 fake 一个 — 直接删 step 之后从 user 重发
        let afterUser = bubbles.suffix(from: lastUserIdx + 1)
        if let firstAssistantId = afterUser.compactMap({ b -> UUID? in
            if case .assistant(let id, _) = b { return id } else { return nil }
        }).first {
            await regenerate(bubbleId: firstAssistantId)
        } else {
            // 没有 assistant — 兜底:复用 regenerate 但把锚点指向 step 自身
            // _regenerateImpl 找 user 的逻辑跟 step 同样适用,只是它要求 case .assistant — 退化路径手工模拟
            await runSerially { [weak self] in
                guard let self else { return }
                guard let session = self.session else { return }
                guard case .user(_, let userText) = self.bubbles[lastUserIdx] else { return }
                let toRemove = Array(self.bubbles[(lastUserIdx + 1)...])
                self.persistence.deleteMessages(ids: toRemove.map(\.id))
                self.bubbles.removeSubrange((lastUserIdx + 1)...)
                self.persistence.save()
                let priorBubbles = self.bubbles.prefix(lastUserIdx)
                let rebuiltHistory: [AgentMessage] = priorBubbles.compactMap { b in
                    switch b {
                    case .user(_, let t):      return .user(t)
                    case .assistant(_, let t): return .assistant(content: t, toolCalls: [])
                    case .toolStep:            return nil
                    }
                }
                self.history = rebuiltHistory
                self.isThinking = true
                do {
                    try await self.coordinator.run(
                        userMessage: userText,
                        history: rebuiltHistory,
                        systemPrompt: self.systemPrompt,
                        onEvent: { [weak self] event in self?.handleEvent(event) }
                    )
                    self.flushStreamingToBubbles()
                    self.persistence.save()
                    self.persistence.touch(session: session)
                } catch {
                    self.flushStreamingToBubbles()
                }
                self.isThinking = false
            }
        }
    }

    /// 等当前 task 跑完再开新的;Task 隔离避免在 await suspension 期间状态被另一个 entry 改坏。
    private func runSerially(_ work: @escaping @MainActor () async -> Void) async {
        let prev = currentRunTask
        let task = Task { @MainActor in
            await prev?.value
            await work()
        }
        currentRunTask = task
        await task.value
    }

    /// 把流式累积的 text 合并成一条 .assistant bubble。Stream 结束 / 出错 / cancel 都要调,
    /// 否则 streamingText 残留下次 stream 时拼接错。
    ///
    /// 关键: 用 `Transaction(disablesAnimations: true)` 包裹 mutation,避免和
    /// ChatView `.onChange(of: vm.bubbles.count)` 触发的 `withAnimation { scrollTo }`
    /// 同帧叠加产生"流式 bubble 与合并后 bubble 双滚动"jitter。
    private func flushStreamingToBubbles() {
        guard let id = streamingId else { return }
        let text = streamingText
        // 先清状态再 append, 避免 SwiftUI 在同步 frame 里同时观察两个变化
        streamingText = ""
        streamingId = nil
        guard !text.isEmpty else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            bubbles.append(.assistant(id: id, text: text))
        }
    }

    private func _sendImpl() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }

        // 用户开始新提问 → 清掉旧的追问建议
        followUpTask?.cancel()
        followUps = []

        // 第一次发消息时建 session,title 用首条 user 文本截断
        if session == nil {
            let s = persistence.newSession(title: String(text.prefix(20)))
            session = s
            currentSessionID = s.id
        }
        guard let session else { return }

        let userId = UUID()
        bubbles.append(.user(id: userId, text: text))
        persistence.appendText(id: userId, role: .user, text: text, to: session)
        persistence.save()

        input = ""
        isThinking = true

        do {
            try await coordinator.run(
                userMessage: text,
                history: history,
                systemPrompt: systemPrompt,
                onEvent: { [weak self] event in
                    self?.handleEvent(event)
                }
            )
            // 流式结束 — 把 streaming 文本一次性合并进 bubbles 让 ChatHistoryView 等永久 list 看到
            flushStreamingToBubbles()
            persistence.save()

            // 记忆这一轮对话
            history.append(.user(text))
            if let lastAssistantText = bubbles.compactMap({ b -> String? in
                if case .assistant(_, let t) = b { return t } else { return nil }
            }).last {
                history.append(.assistant(content: lastAssistantText, toolCalls: []))
            }
        } catch is CancellationError {
            // 用户主动取消 — flush streaming 但不 append error bubble(stop() 已经把
            // running tool step 标 failed/取消了,UI 已有视觉反馈,不需要再多一条 error 文本)
            flushStreamingToBubbles()
            persistence.save()
        } catch {
            // 出错也要 flush — 否则 streamingText 残留,下次 send 拼接错
            flushStreamingToBubbles()
            let errId = UUID()
            let errText = L10n.t(zh: "出错了:\(error.localizedDescription)",
                                  en: "Error: \(error.localizedDescription)")
            bubbles.append(.assistant(id: errId, text: errText))
            persistence.appendText(id: errId, role: .assistant, text: errText, to: session)
            persistence.save()
        }

        // 首个 chunk 到达时 handleEvent 已设 isThinking=false;错误路径(无 chunk)兜底再设一次。
        isThinking = false

        // 异步生成追问建议——不阻塞主流程,失败/慢都没关系
        scheduleFollowUps()
    }

    func usePrompt(_ p: String) {
        input = p
    }

    private func scheduleFollowUps() {
        let lastUser = bubbles.compactMap { b -> String? in
            if case .user(_, let t) = b { return t } else { return nil }
        }.last
        let lastAssistant = bubbles.compactMap { b -> String? in
            if case .assistant(_, let t) = b { return t } else { return nil }
        }.last
        guard let lu = lastUser, let la = lastAssistant else { return }
        followUpTask?.cancel()
        followUpTask = Task { @MainActor [weak self] in
            let result = (try? await LLMClient.shared.suggestFollowUps(lastUser: lu, lastAssistant: la)) ?? []
            guard !Task.isCancelled else { return }
            self?.followUps = result
        }
    }

    // MARK: - event handling
    //
    // AgentRuntime 发的事件回到这里,因为要直接改 bubbles 数组 + streamingText
    // 这些都属于 ViewModel 自有 @Observable 状态。
    // 摘要 / 错误判定的细节走 AgentStreamCoordinator 的 static helper(humanPreview / isErrorResult)。

    private func handleEvent(_ event: AgentEvent) {
        guard let session else { return }
        switch event {
        case .toolStarted(let name, _, let hint):
            let id = UUID()
            let now = Date()
            bubbles.append(.toolStep(
                id: id,
                name: name,
                status: .running,
                resultPreview: nil,
                runningHint: hint,
                startedAt: now,
                finishedAt: nil
            ))
            persistence.appendToolStart(id: id, name: name, hint: hint, startedAt: now, to: session)
            // 触觉反馈:开始一步 — soft impact 给用户"工具开跑"信号
            HapticFeedback.softImpact()

        case .toolFinished(let name, let result):
            if let idx = bubbles.lastIndex(where: { b in
                if case .toolStep(_, let n, let s, _, _, _, _) = b { return n == name && s == .running }
                return false
            }), case .toolStep(let id, _, _, _, let hint, let startedAt, _) = bubbles[idx] {
                let preview = AgentStreamCoordinator.humanPreview(name: name, result: result)
                let isError = AgentStreamCoordinator.isErrorResult(result: result)
                let finalStatus: Bubble.ToolStatus = isError ? .failed : .done
                let now = Date()
                bubbles[idx] = .toolStep(
                    id: id,
                    name: name,
                    status: finalStatus,
                    resultPreview: preview,
                    runningHint: hint,
                    startedAt: startedAt,
                    finishedAt: now
                )
                persistence.updateToolFinished(id: id, isError: isError, preview: preview, finishedAt: now)
                // 触觉反馈:完成 — success / 失败 → warning
                if isError {
                    HapticFeedback.warning()
                } else {
                    HapticFeedback.lightImpact()
                }
            }

        case .assistantTextChunk(let delta):
            // 流式期间只改 streamingText,不动 bubbles 数组(避免 LazyVStack 全 list diff)。
            // 首个 chunk 来时创建 ChatMessage 持久化入 store,后续 chunk 只更新 text 字段。
            if streamingId == nil {
                isThinking = false
                let id = UUID()
                streamingId = id
                persistence.appendStreamingAssistant(id: id, to: session)
            }
            streamingText += delta
            if let id = streamingId {
                persistence.updateStreamingText(id: id, text: streamingText)
            }

        case .error(let msg):
            let id = UUID()
            let display = "⚠️ \(msg)"
            bubbles.append(.assistant(id: id, text: display))
            persistence.appendText(id: id, role: .assistant, text: display, to: session)
        }
    }
}
