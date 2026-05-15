import Foundation
import SwiftData
import PoleDomain
import PoleAIKit   // AgentMessage —— history 重建跨 user/assistant 用

/// `ChatViewModel` 的 SwiftData 持久化层适配器。
///
/// **职责**:
/// - 持有 `ChatStore`(底层 ModelContext 包装) + `messageById` 字典
/// - 把 ViewModel 想做的"持久化操作"翻译成 `ChatStore` + `ChatMessage` 调用
/// - 提供 `ChatMessage` ↔ `ChatViewModel.Bubble` 的双向映射(`toBubble` 静态方法)
///
/// **为什么独立**:
/// 原来 ChatViewModel 里散落了 N 处 `messageById[id] = m` / `m.toolPreview = ...` /
/// `store.context.delete(...)` 这种"边改 in-memory 字典 边改 SwiftData 实体"的双写代码。
/// 抽到这一层后:
/// 1. ViewModel 只调"语义化"方法(`persistUser`、`updateToolFinished`、`deleteAfter`)
/// 2. 双写一致性由这里负责,ViewModel 不会忘记同步两边
/// 3. messageById 字典对 view 没意义,不暴露,封装更彻底
///
/// 仍是 `@MainActor`(`ModelContext` / `ChatMessage` 都不 Sendable)。
@MainActor
public final class ChatPersistence {

    /// 持久化底层 — 维持现有 ChatStore API 不变(deinit / recoverInterruptedToolSteps 都还能直接调用)。
    let store: ChatStore

    /// id → 实体的快速查表;regenerate 删 bubble 时要顺带 context.delete 对应实体。
    /// 不暴露(view 看不到),所有读写经语义化方法。
    private var messageById: [UUID: ChatMessage] = [:]

    public init(context: ModelContext) {
        self.store = ChatStore(context: context)
    }

    // MARK: - 启动恢复(转发到 store)

    /// crash/强杀后把停在 running 的 tool step 改 failed,避免历史对话里永远卡"工具调用中"。
    /// 在 ChatViewModel.init 里调一次。
    func recoverInterruptedToolSteps() {
        store.recoverInterruptedToolSteps()
    }

    // MARK: - 会话管理

    func loadSession(_ session: ChatSession) -> (bubbles: [ChatViewModel.Bubble], history: [AgentMessage]) {
        let msgs = store.messages(in: session)
        let bubbles = msgs.map(Self.toBubble)
        messageById = Dictionary(uniqueKeysWithValues: msgs.map { ($0.id, $0) })
        // 用 user/assistant 文本重建 history(忽略 tool step,避免 token 浪费)
        let history: [AgentMessage] = msgs.compactMap { m -> AgentMessage? in
            switch m.role {
            case .user:      return .user(m.text)
            case .assistant: return .assistant(content: m.text, toolCalls: [])
            case .tool_step: return nil
            }
        }
        return (bubbles, history)
    }

    func resetForNewSession() {
        messageById = [:]
    }

    func allSessions() -> [ChatSession] { store.allSessions() }

    func newSession(title: String) -> ChatSession { store.newSession(title: title) }

    func delete(session: ChatSession) { store.delete(session: session) }

    func touch(session: ChatSession) { store.touch(session: session) }

    func save() { store.save() }

    // MARK: - 消息追加

    /// 持久化一条 user / assistant text 消息。
    func appendText(id: UUID, role: ChatMessage.Role, text: String, to session: ChatSession) {
        let m = ChatMessage(id: id, role: role, text: text)
        store.append(message: m, to: session)
        messageById[id] = m
    }

    /// 创建 tool step 起步消息(running 状态)。
    func appendToolStart(id: UUID, name: String, hint: String?, startedAt: Date, to session: ChatSession) {
        let m = ChatMessage(
            id: id,
            role: .tool_step,
            text: "",
            toolName: name,
            toolStatus: .running,
            toolRunningHint: hint,
            toolStartedAt: startedAt
        )
        store.append(message: m, to: session)
        messageById[id] = m
    }

    /// 创建 streaming assistant 的占位 message(后续 chunk 通过 `updateStreamingText` 增量改)。
    func appendStreamingAssistant(id: UUID, to session: ChatSession) {
        let m = ChatMessage(id: id, role: .assistant, text: "")
        store.append(message: m, to: session)
        messageById[id] = m
    }

    // MARK: - tool step 状态更新

    /// tool 完成后更新对应 ChatMessage(persistence)字段。
    func updateToolFinished(id: UUID, isError: Bool, preview: String, finishedAt: Date) {
        guard let m = messageById[id] else { return }
        m.toolStatusRaw = (isError ? ChatMessage.ToolStatus.failed : ChatMessage.ToolStatus.done).rawValue
        m.toolPreview = preview
        m.text = preview
        m.toolFinishedAt = finishedAt
    }

    /// 用户点"停止"时把残留 running tool step 强制翻 failed。
    /// 返回 true 表示找到了实体并改写了。
    @discardableResult
    func cancelToolStep(id: UUID, at now: Date, cancelLabel: String) -> Bool {
        guard let m = messageById[id] else { return false }
        m.toolStatusRaw = ChatMessage.ToolStatus.failed.rawValue
        m.toolFinishedAt = now
        if (m.toolPreview ?? "").isEmpty {
            m.toolPreview = cancelLabel
            m.text = cancelLabel
        }
        return true
    }

    // MARK: - 流式 text 更新

    /// streaming 期间每个 chunk 到达后增量写入对应 message.text。
    func updateStreamingText(id: UUID, text: String) {
        messageById[id]?.text = text
    }

    // MARK: - 批量删除(regenerate / retry 重发前清理)

    /// 删除 ids 列表对应的所有 ChatMessage(真删 context,避免孤儿实体堆积)。
    func deleteMessages(ids: [UUID]) {
        for id in ids {
            if let m = messageById[id] {
                store.context.delete(m)
                messageById.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Bubble ↔ ChatMessage 转换

    /// 持久化的 ChatMessage 反序列化成 UI 用的 Bubble。
    /// 用于 loadSession 时一次批量 map。
    static func toBubble(_ m: ChatMessage) -> ChatViewModel.Bubble {
        switch m.role {
        case .user:
            return .user(id: m.id, text: m.text)
        case .assistant:
            return .assistant(id: m.id, text: m.text)
        case .tool_step:
            let status: ChatViewModel.Bubble.ToolStatus
            switch m.toolStatus {
            case .running: status = .running
            case .done:    status = .done
            case .failed:  status = .failed
            case .none:    status = .done
            }
            // 历史消息无 startedAt 时退回 createdAt(SwiftData 必有 createdAt),保证 toolDuration 不返负数。
            return .toolStep(
                id: m.id,
                name: m.toolName ?? "tool",
                status: status,
                resultPreview: m.toolPreview,
                runningHint: m.toolRunningHint,
                startedAt: m.toolStartedAt ?? m.createdAt,
                finishedAt: m.toolFinishedAt
            )
        }
    }
}
