import Foundation
import SwiftData

/// 一条聊天消息——对应 ChatViewModel.Bubble 的三种 case。
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String         // "user" / "assistant" / "tool_step"
    var text: String
    var toolName: String?
    var toolStatusRaw: String?  // "running" / "done" / "failed"(仅 tool_step)
    var toolPreview: String?
    /// 进度文案 — running 时 LLM 看不到,纯 UI 展示("正在查找 F1 西班牙站...")
    var toolRunningHint: String?
    /// tool 开始时间(仅 tool_step)— 用于显示耗时
    var toolStartedAt: Date?
    /// tool 结束时间(仅 tool_step)— done/failed 后用于显示 finishedAt - startedAt
    var toolFinishedAt: Date?
    var createdAt: Date

    var session: ChatSession?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        toolName: String? = nil,
        toolStatus: ToolStatus? = nil,
        toolPreview: String? = nil,
        toolRunningHint: String? = nil,
        toolStartedAt: Date? = nil,
        toolFinishedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.roleRaw = role.rawValue
        self.text = text
        self.toolName = toolName
        self.toolStatusRaw = toolStatus?.rawValue
        self.toolPreview = toolPreview
        self.toolRunningHint = toolRunningHint
        self.toolStartedAt = toolStartedAt
        self.toolFinishedAt = toolFinishedAt
        self.createdAt = createdAt
    }

    enum Role: String { case user, assistant, tool_step }
    enum ToolStatus: String { case running, done, failed }

    var role: Role { Role(rawValue: roleRaw) ?? .assistant }
    var toolStatus: ToolStatus? { toolStatusRaw.flatMap(ToolStatus.init) }

    /// done/failed 时返回耗时秒数(用于 UI 显示),否则 nil。
    var toolDuration: TimeInterval? {
        guard let s = toolStartedAt, let e = toolFinishedAt else { return nil }
        return max(0, e.timeIntervalSince(s))
    }
}
