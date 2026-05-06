import Foundation
import SwiftData

/// SwiftData 持久化"已添加到苹果日历"的 session 记录——用 `sessionKey` 作为去重键。
/// 防止用户重复添加;移除时也要先 delete EKEvent 再 delete 这条记录。
@Model
final class AddedCalendarEvent {
    @Attribute(.unique) var sessionKey: String
    var ekIdentifier: String
    var addedAt: Date

    init(sessionKey: String, ekIdentifier: String, addedAt: Date = .now) {
        self.sessionKey = sessionKey
        self.ekIdentifier = ekIdentifier
        self.addedAt = addedAt
    }
}
