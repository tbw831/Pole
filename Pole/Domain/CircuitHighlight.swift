import Foundation
import SwiftData
import PoleDomain

/// AI 生成的赛道亮点缓存。一条对应一个"赛道 + 系列"组合。
///
/// 设计:
/// - `key` = "<series>-<circuitSlug>" 唯一,例 "f1-bahrain" / "motogp-jerez"
///   不同系列在同一赛道(F1 / MotoGP 都跑 Mugello)亮点不同(F1 看高速,MotoGP 看刹车点),
///   所以 key 含 series。
/// - `content` 是 LLM 输出的纯文本(无 markdown,200 字以内)。
/// - 一旦生成长期有效,赛道特点不会变。
@Model
final class CircuitHighlight {
    @Attribute(.unique) var key: String
    var series: String
    var circuitName: String
    var content: String
    var createdAt: Date

    init(key: String, series: String, circuitName: String, content: String, createdAt: Date = .now) {
        self.key = key
        self.series = series
        self.circuitName = circuitName
        self.content = content
        self.createdAt = createdAt
    }

    /// 标准化 key 生成。circuit name slug + series。
    static func makeKey(series: MotorsportSeries, circuitName: String) -> String {
        let slug = circuitName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "ó", with: "o")
            .replacingOccurrences(of: "ã", with: "a")
        return "\(series.rawValue)-\(slug)"
    }
}
