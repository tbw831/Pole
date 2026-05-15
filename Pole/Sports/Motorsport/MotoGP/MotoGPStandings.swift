import Foundation
import PoleDomain

// MARK: - Rider

public nonisolated struct MotoGPRider: Identifiable, Hashable, Sendable, Codable {
    public let id: String              // Pulselive rider UUID
    public let fullName: String
    public let number: Int?            // 永久号码
    public let countryISO: String?     // "IT" / "ES"

    public var displayName: String {
        MotorsportNames.driverShortName(rawFullName: fullName, series: .motogp)
    }

    public var displayFullName: String {
        MotorsportNames.driverFullName(rawFullName: fullName, series: .motogp)
    }
}

public nonisolated struct MotoGPTeam: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String

    public var displayName: String {
        MotorsportNames.teamName(raw: name, series: .motogp)
    }
}

public nonisolated struct MotoGPConstructor: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String

    public var displayName: String {
        MotorsportNames.teamName(raw: name, series: .motogp)
    }
}

// MARK: - Standings

public nonisolated struct MotoGPRiderStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { rider.id }
    public let position: Int
    public let points: Double
    public let raceWins: Int
    public let podiums: Int
    public let rider: MotoGPRider
    public let team: MotoGPTeam
    public let constructor: MotoGPConstructor
}

/// 客户端聚合得到——同 team 的 rider points 求和。
public nonisolated struct MotoGPTeamStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { team.id }
    public let position: Int
    public let points: Double
    public let team: MotoGPTeam
    public let riderNames: [String]   // 该队的车手列表(按个人 points 排序)
}

/// 客户端聚合——同 constructor 的 rider points 求和。
public nonisolated struct MotoGPConstructorStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { constructor.id }
    public let position: Int
    public let points: Double
    public let constructor: MotoGPConstructor
}

// MARK: - 单 rider 整季 round-by-round 积分(给积分趋势图用)

/// 一场大奖赛(round)中一名车手的 race + sprint 得分。
/// MotoGP 的 race 和 sprint 都进 championship,趋势图按 round 累加 totalPoints。
public nonisolated struct MotoGPRiderRoundPoints: Identifiable, Hashable, Sendable, Codable {
    public let round: Int           // 在赛季中的位次(1 起)
    public let roundName: String    // "FRA" / "SPA" 等(round.shortName)
    public let racePoints: Double   // 周日正赛得分(0..25)
    public let sprintPoints: Double // 周六 sprint 得分(0..12)

    public var totalPoints: Double { racePoints + sprintPoints }
    public var id: Int { round }
}

// MARK: - 单场 session 结果

/// 单 session 的 classification 一行——race / sprint / qualifying 共用。
public nonisolated struct MotoGPRaceResult: Identifiable, Hashable, Sendable, Codable {
    public var id: String { rider.id }
    public let position: Int
    public let rider: MotoGPRider
    public let team: MotoGPTeam
    public let constructor: MotoGPConstructor
    public let totalLaps: Int?
    public let timeText: String?      // "39:36.270" 完赛者
    public let gapToFirstText: String? // "+0.123" 非领先者(领先者 first="0.000")
    public let points: Double         // race 0/1/4/...25;quali 通常 0
    public let averageSpeed: Double?  // km/h,race 才有
    public let status: String         // "INSTND"(完赛) / "NOSUM"(未起步) / "NDC"(未列分)等
}

/// MotoGP session 引用——保留 Pulselive 原始 UUID 用于后续拉 classification。
/// 通用 `Session` 的 id 是已经 prefix 过的 ("eventId-rawId"),无法直接用作 API 参数。
public nonisolated struct MotoGPSessionRef: Hashable, Sendable, Identifiable {
    public let rawId: String          // Pulselive session UUID
    public let session: Session
    public var id: String { session.id }
}
