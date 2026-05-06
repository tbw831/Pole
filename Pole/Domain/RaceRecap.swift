import Foundation
import SwiftData

/// AI 生成的赛事概览缓存——`eventKey` 是 unique,同一场只生成一次。
/// eventKey 约定:`<series>-<season>-<round>-<sessionKind>`,例如 "f1-2025-1-race"。
@Model
final class RaceRecap {
    @Attribute(.unique) var eventKey: String
    var series: String
    var title: String           // "Bahrain Grand Prix · Race"
    var content: String         // markdown 复盘正文
    var generatedAt: Date

    init(eventKey: String, series: String, title: String, content: String, generatedAt: Date = .now) {
        self.eventKey = eventKey
        self.series = series
        self.title = title
        self.content = content
        self.generatedAt = generatedAt
    }
}
