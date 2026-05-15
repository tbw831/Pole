import Foundation

/// Widget 显示所需的最小数据集。主 app 序列化为 JSON 写到 App Group container,
/// Widget extension 反序列化读。WidgetSnapshot 不依赖任何 main app domain 类型,
/// 这样 widget extension 不需要 link 整个 Sports/Domain/Features 代码。
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public var generatedAt: Date
    public var nextRace: NextRace?
    public var followedDrivers: [FollowedDriver]

    public init(generatedAt: Date, nextRace: NextRace?, followedDrivers: [FollowedDriver]) {
        self.generatedAt = generatedAt
        self.nextRace = nextRace
        self.followedDrivers = followedDrivers
    }

    /// 跨四个系列(F1 / MotoGP / WSSP / FE)中最早未结束的那场比赛。
    /// 没有(全赛季结束)时为 nil,widget 显示"赛季结束"占位。
    public struct NextRace: Codable, Sendable, Hashable {
        public var seriesRaw: String   // "f1" / "motogp" / "wssp" / "fe"
        public var roundName: String
        public var circuitName: String
        public var countryCode: String?
        public var weekendStart: Date
        public var weekendEnd: Date
        /// 主 race session 开始时间(用于 systemSmall 倒计时)
        public var raceStart: Date
        /// 完整 session 列表(给 systemLarge widget 显示周末赛程)
        public var sessions: [SessionInfo]
        public var statusRaw: String   // "upcoming" / "live" / "finished" / "postponed"

        public init(
            seriesRaw: String,
            roundName: String,
            circuitName: String,
            countryCode: String?,
            weekendStart: Date,
            weekendEnd: Date,
            raceStart: Date,
            sessions: [SessionInfo],
            statusRaw: String
        ) {
            self.seriesRaw = seriesRaw
            self.roundName = roundName
            self.circuitName = circuitName
            self.countryCode = countryCode
            self.weekendStart = weekendStart
            self.weekendEnd = weekendEnd
            self.raceStart = raceStart
            self.sessions = sessions
            self.statusRaw = statusRaw
        }
    }

    public struct SessionInfo: Codable, Sendable, Hashable, Identifiable {
        public var label: String      // "FP1" / "排位赛" / "正赛"
        public var kindRaw: String    // "practice" / "qualifying" / "race" / "sprint" / ...
        public var start: Date

        /// 稳定 id — widget ForEach 用,避免 timeline 刷新时按 array offset 误重建 row。
        public var id: String { "\(kindRaw):\(label):\(start.timeIntervalSince1970)" }

        public init(label: String, kindRaw: String, start: Date) {
            self.label = label
            self.kindRaw = kindRaw
            self.start = start
        }
    }

    public struct FollowedDriver: Codable, Sendable, Hashable, Identifiable {
        public var seriesRaw: String
        public var name: String
        public var rank: Int?
        public var points: Double?
        public var teamName: String?

        /// 稳定 id — series + name 唯一,rank 升降不导致 row 重建。
        public var id: String { "\(seriesRaw):\(name)" }

        public init(seriesRaw: String, name: String, rank: Int?, points: Double?, teamName: String?) {
            self.seriesRaw = seriesRaw
            self.name = name
            self.rank = rank
            self.points = points
            self.teamName = teamName
        }
    }
}
