import Foundation
import SwiftData
import PoleDomain

/// SwiftData 操作 ChatSession / ChatMessage 的 helper。所有方法 MainActor。
@MainActor
public final class ChatStore {
    let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    // MARK: - sessions

    func allSessions() -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.lastUpdatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func session(id: UUID) -> ChatSession? {
        let descriptor = FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    func newSession(title: String = L10n.t(zh: "新对话", en: "New Chat")) -> ChatSession {
        let session = ChatSession(title: title)
        context.insert(session)
        save()
        return session
    }

    func delete(session: ChatSession) {
        context.delete(session)
        save()
    }

    func touch(session: ChatSession) {
        session.lastUpdatedAt = .now
    }

    // MARK: - messages

    func append(message: ChatMessage, to session: ChatSession) {
        message.session = session
        context.insert(message)
        session.lastUpdatedAt = .now
    }

    func messages(in session: ChatSession) -> [ChatMessage] {
        session.messages.sorted(by: { $0.createdAt < $1.createdAt })
    }

    // MARK: - save

    func save() {
        do { try context.save() } catch {
            // 写入失败不阻塞 UI——下一次 save 会重试
            print("[ChatStore] save failed: \(error)")
        }
    }

    // MARK: - 启动恢复

    /// app 启动时调一次 — 把上次崩溃 / 强杀时停在 "running" 状态的 tool_step 改成 "failed",
    /// 否则下次打开历史对话会看到永远"工具调用中"的卡死视觉。
    func recoverInterruptedToolSteps() {
        let runningRaw = ChatMessage.ToolStatus.running.rawValue
        let failedRaw = ChatMessage.ToolStatus.failed.rawValue
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.toolStatusRaw == runningRaw }
        )
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for msg in stuck {
            msg.toolStatusRaw = failedRaw
            // 设 finishedAt 让 toolDuration 计算"中断耗时" — 不设的话 view 永远显示"running",
            // 即便 status 已经是 failed。
            if msg.toolFinishedAt == nil {
                msg.toolFinishedAt = .now
            }
            if msg.toolPreview?.isEmpty ?? true {
                let interruptedLabel = L10n.t(zh: "中断", en: "Interrupted")
                msg.toolPreview = interruptedLabel
                msg.text = interruptedLabel
            }
        }
        save()
    }
}
