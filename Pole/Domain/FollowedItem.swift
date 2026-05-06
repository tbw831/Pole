import Foundation
import SwiftData

/// SwiftData 持久化的"关注"行。一行 = 一个 FollowTarget。
/// `key` 强约束唯一，避免重复 follow。
@Model
final class FollowedItem {
    @Attribute(.unique) var key: String
    var sportRaw: String
    var seriesRaw: String
    var kindRaw: String         // "athlete" / "team" / "league"
    var refId: String
    var displayName: String     // 关注时一并存好,离线也能展示("Max Verstappen" / "Red Bull")
    var addedAt: Date

    init(target: FollowTarget, displayName: String, addedAt: Date = .now) {
        self.key = Self.makeKey(target)
        self.sportRaw = target.sport.rawValue
        self.seriesRaw = target.series
        self.kindRaw = target.kindLabel
        self.refId = target.rawId
        self.displayName = displayName
        self.addedAt = addedAt
    }

    static func makeKey(_ target: FollowTarget) -> String {
        "\(target.series):\(target.kindLabel):\(target.rawId)"
    }

    var target: FollowTarget? {
        guard let sport = Sport(rawValue: sportRaw) else { return nil }
        switch kindRaw {
        case "athlete": return .athlete(id: refId, sport: sport, series: seriesRaw)
        case "team":    return .team(id: refId, sport: sport, series: seriesRaw)
        case "league":  return .league(id: refId, sport: sport, series: seriesRaw)
        default:        return nil
        }
    }
}

extension FollowedItem {
    /// 当前语言下的显示名 — `displayName` 是关注当时存的 raw 名（英文 fullName / 厂商原名），
    /// 这里按 `kindRaw` + `seriesRaw` 过 `MotorsportNames` 转中文（zh 模式）。
    /// 给 ChatViewModel ListFollowedTool fetcher / starter prompts followedNames /
    /// followedPrompts 用，让 LLM 上下文也是用户当前语言。
    var localizedDisplayName: String {
        guard let series = MotorsportSeries(rawValue: seriesRaw) else { return displayName }
        switch kindRaw {
        case "athlete":
            return MotorsportNames.driverShortName(rawFullName: displayName, series: series)
        case "team":
            return MotorsportNames.teamName(raw: displayName, series: series)
        default:
            return displayName
        }
    }
}
