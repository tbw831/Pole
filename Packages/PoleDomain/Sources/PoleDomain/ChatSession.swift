import Foundation
import SwiftData

/// 一次 AI 对话会话。`messages` 是 cascade 关系——删 session 自动删消息。
@Model
public final class ChatSession {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var lastUpdatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    public var messages: [ChatMessage] = []

    public init(id: UUID = UUID(), title: String = L10n.t(zh: "新对话", en: "New Chat"), createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastUpdatedAt = createdAt
    }
}
