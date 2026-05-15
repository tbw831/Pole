import Foundation
import SwiftData

/// 一条聊天消息——对应 ChatViewModel.Bubble 的三种 case。
@Model
public final class ChatMessage {
    @Attribute(.unique) public var id: UUID
    public var roleRaw: String         // "user" / "assistant" / "tool_step"
    public var text: String
    public var toolName: String?
    public var toolStatusRaw: String?  // "running" / "done" / "failed"(仅 tool_step)
    public var toolPreview: String?
    /// 进度文案 — running 时 LLM 看不到,纯 UI 展示("正在查找 F1 西班牙站...")
    public var toolRunningHint: String?
    /// tool 开始时间(仅 tool_step)— 用于显示耗时
    public var toolStartedAt: Date?
    /// tool 结束时间(仅 tool_step)— done/failed 后用于显示 finishedAt - startedAt
    public var toolFinishedAt: Date?
    public var createdAt: Date

    public var session: ChatSession?

    public init(
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

    public enum Role: String { case user, assistant, tool_step }
    public enum ToolStatus: String { case running, done, failed }

    public var role: Role { Role(rawValue: roleRaw) ?? .assistant }
    public var toolStatus: ToolStatus? { toolStatusRaw.flatMap(ToolStatus.init) }

    /// done/failed 时返回耗时秒数(用于 UI 显示),否则 nil。
    public var toolDuration: TimeInterval? {
        guard let s = toolStartedAt, let e = toolFinishedAt else { return nil }
        return max(0, e.timeIntervalSince(s))
    }
}
