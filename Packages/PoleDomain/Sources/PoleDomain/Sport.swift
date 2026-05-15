import Foundation

// MARK: - Sport

/// 顶层运动大类，决定 UI tab、图标、配色。
/// 具体系列（F1/MotoGP/NBA/英超）由 League.series 表达，不在此 enum 里。
/// 加新大类只在此处加 case。
public nonisolated enum Sport: String, Codable, CaseIterable, Identifiable, Sendable {
    case motorsport
    case basketball
    case football

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .motorsport: return L10n.t(zh: "赛车", en: "Motorsport")
        case .basketball: return L10n.t(zh: "篮球", en: "Basketball")
        case .football:   return L10n.t(zh: "足球", en: "Football")
        }
    }

    public var systemImageName: String {
        switch self {
        case .motorsport: return "flag.checkered"
        case .basketball: return "basketball.fill"
        case .football:   return "soccerball"
        }
    }
}

// MARK: - League

/// 联赛 / 系列赛的某个赛季。F1 2025 整年作为一个 League（"f1-2025"），MotoGP/WSBK/NBA/英超同理。
/// `series` 是稳定字符串 slug（"f1" / "motogp" / "wsbk" / "nba" / "premier-league"），
/// 跨 sport 不重复；赛车类的 series 与 `MotorsportSeries.rawValue` 对齐。
public nonisolated struct League: Hashable, Identifiable, Sendable, Codable {
    public let id: String           // 稳定 slug："f1-2025" / "motogp-2025" / "wsbk-2025"
    public let sport: Sport
    public let series: String       // "f1" / "motogp" / "wsbk" / …
    public let name: String         // "Formula 1 2025 World Championship"
    public let shortName: String    // "F1 2025"
    public let season: String?      // "2025"

    public init(id: String, sport: Sport, series: String, name: String, shortName: String, season: String? = nil) {
        self.id = id
        self.sport = sport
        self.series = series
        self.name = name
        self.shortName = shortName
        self.season = season
    }
}

// MARK: - SportEvent

/// 通用赛事状态。
public nonisolated enum EventStatus: String, Codable, Sendable {
    case upcoming
    case live
    case finished
    case postponed
}

/// 顶层赛事抽象。F1 的 Race、NBA/英超的 Match、UFC 的 FightCard 都实现此协议，
/// 让 Today / Schedule 等通用页面无需关心具体领域。
///
/// 注意：此协议不继承 Identifiable，避免与 Sendable 在 Swift 6 严格并发下冲突
/// （SwiftUI 让 Identifiable conformance 默认 @MainActor 隔离）。
/// 具体类型（F1Round 等）只要拥有 `id` 属性即自动满足 Identifiable，可独立给 SwiftUI 使用。
public nonisolated protocol SportEvent: Sendable {
    nonisolated var id: String { get }
    nonisolated var sport: Sport { get }
    nonisolated var leagueId: String { get }
    nonisolated var startTime: Date { get }
    nonisolated var status: EventStatus { get }
    /// 卡片主标题，例如 "Bahrain Grand Prix"
    nonisolated var headline: String { get }
    /// 卡片副标题，例如 "Round 1 · Sakhir, Bahrain"
    nonisolated var subheadline: String { get }
}

// MARK: - FollowTarget

/// 关注对象——三种粒度。`series` 是 League.series 同源字符串
/// （"f1" / "motogp" / "wsbk" / "nba" / …），让"取消关注 max_verstappen"和
/// "取消关注 LeBron"互不干扰。SwiftData 的 FollowedItem 表序列化此结构。
public nonisolated enum FollowTarget: Hashable, Codable, Sendable {
    case athlete(id: String, sport: Sport, series: String)
    case team(id: String, sport: Sport, series: String)
    case league(id: String, sport: Sport, series: String)

    public var sport: Sport {
        switch self {
        case .athlete(_, let s, _), .team(_, let s, _), .league(_, let s, _):
            return s
        }
    }

    public var series: String {
        switch self {
        case .athlete(_, _, let s), .team(_, _, let s), .league(_, _, let s):
            return s
        }
    }

    public var rawId: String {
        switch self {
        case .athlete(let id, _, _), .team(let id, _, _), .league(let id, _, _):
            return id
        }
    }

    public var kindLabel: String {
        switch self {
        case .athlete: return "athlete"
        case .team:    return "team"
        case .league:  return "league"
        }
    }
}
