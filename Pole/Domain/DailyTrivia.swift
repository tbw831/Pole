import Foundation
import SwiftData

/// 每日 AI 生成的赛车冷知识缓存——dayKey 是 "yyyy-MM-dd"(北京时区),
/// `@Attribute(.unique)` 防止同一天重复生成。
@Model
final class DailyTrivia {
    @Attribute(.unique) var dayKey: String
    var content: String
    var generatedAt: Date

    init(dayKey: String, content: String, generatedAt: Date = .now) {
        self.dayKey = dayKey
        self.content = content
        self.generatedAt = generatedAt
    }

    /// 返回当前北京时间的 dayKey,如 "2026-05-03"。
    static func todayKey(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: now)
    }
}
