import Foundation
import PoleDomain

// MARK: - Rider

public nonisolated struct WSSPRider: Identifiable, Hashable, Sendable, Codable {
    /// worldsbk.com 不暴露 rider 内部 id,用 name 作 stable id(slug 化)。
    public var id: String { fullName.lowercased().replacingOccurrences(of: " ", with: "-") }
    public let fullName: String
    public let countryISO: String?  // "esp" / "ita" / "gbr"——HTML 用小写 3 字

    public var displayName: String {
        MotorsportNames.driverShortName(rawFullName: fullName, series: .wssp)
    }

    public var displayFullName: String {
        MotorsportNames.driverFullName(rawFullName: fullName, series: .wssp)
    }
}

// MARK: - Standing

/// WSSP 车手榜。worldsbk.com 没在 HTML 标记车队信息(rider-team 是空 span),
/// WSSP 没有"车队榜",但有"厂商榜"(见 WSSPBuilder)。
/// `wins` 是客户端聚合得到——遍历所有已结束 round 的 race PDF,首位累加。
public nonisolated struct WSSPRiderStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { rider.id }
    public let position: Int
    public let points: Double
    public let wins: Int
    public let rider: WSSPRider

    public init(position: Int, points: Double, wins: Int = 0, rider: WSSPRider) {
        self.position = position
        self.points = points
        self.wins = wins
        self.rider = rider
    }
}

// MARK: - Builder (厂商)

public nonisolated struct WSSPBuilder: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name.lowercased() }
    public let name: String         // "DUCATI" / "YAMAHA" / "ZXMOTO"
    public let countryISO: String?  // "ita" / "jpn" / "chn"

    public var displayName: String {
        MotorsportNames.teamName(raw: name, series: .wssp)
    }
}

public nonisolated struct WSSPBuilderStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { builder.id }
    public let position: Int
    public let points: Double
    public let builder: WSSPBuilder
}

// MARK: - Session 带 PDF results

/// WSSP session 引用——保留官方 Results.pdf URL,iOS 端 PDFKit 解析后 inline 显示。
public nonisolated struct WSSPSessionWithResults: Hashable, Sendable, Identifiable {
    public let session: Session
    public let resultsPdfURL: URL?
    public var id: String { session.id }
}

/// WSSP 单场 timing 结果——PDF 字符级 bounds API 按坐标重组行后解析。
public nonisolated struct WSSPRaceResult: Identifiable, Hashable, Sendable, Codable {
    public var id: String { "\(position)-\(number)" }
    public let position: Int
    public let number: Int          // 永久号码
    public let riderName: String    // "J. MASIA"
    public let nat: String          // "ESP"
    public let team: String
    public let bike: String?
    public let timeText: String?    // "1'42.965"
    public let gapText: String?     // "0.056"
    public let laps: Int?

    /// 姓(用最后一个 word)——PDF 名字"J. MASIA"跟 standings 大写"JAUME MASIA"匹配 key,
    /// 跨数据源对齐 rider 用。
    public var lastName: String {
        let parts = riderName.split(separator: " ")
        return parts.last.map(String.init) ?? riderName
    }

    /// 中英自动切换 — riderName 是"J. MASIA"格式,lowercase 后含"masia"关键字命中 mapping。
    public var displayRiderName: String {
        MotorsportNames.driverShortName(rawFullName: riderName, series: .wssp)
    }

    /// 车队 / 厂商。
    public var displayTeam: String {
        MotorsportNames.teamName(raw: team, series: .wssp)
    }
}

// MARK: - 车手赛季 round-by-round 积分(趋势图用)

public nonisolated struct WSSPRiderRoundPoints: Hashable, Sendable, Codable, Identifiable {
    public let round: Int
    public let roundName: String
    public let race1Points: Double      // Race 1 该 rider 积分
    public let race2Points: Double      // Race 2 积分(没第二场为 0)
    public var id: Int { round }
    public var totalPoints: Double { race1Points + race2Points }
}
