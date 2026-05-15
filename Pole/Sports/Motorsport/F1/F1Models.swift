import Foundation
import PoleDomain
import PoleDesignSystem

// MARK: - 赛车手

public nonisolated struct F1Driver: Identifiable, Hashable, Sendable, Codable {
    public let id: String              // jolpica driverId，"max_verstappen"
    public let code: String?           // 三字母缩写 "VER"
    public let permanentNumber: Int?
    public let givenName: String
    public let familyName: String
    public let nationality: String
    public let dateOfBirth: Date?

    public var fullName: String { "\(givenName) \(familyName)" }

    /// List 行用 — 短名(中文姓 / 英文 fullName)。
    public var displayName: String {
        MotorsportNames.driverShortName(rawFullName: fullName, series: .f1)
    }

    /// Detail 标题用 — 全名(中文模式给完整音译;英文模式同 fullName)。
    public var displayFullName: String {
        MotorsportNames.driverFullName(rawFullName: fullName, series: .f1)
    }
}

// MARK: - 车队

public nonisolated struct F1Constructor: Identifiable, Hashable, Sendable, Codable {
    public let id: String              // "red_bull"
    public let name: String            // "Red Bull"
    public let nationality: String

    /// 中英自动切换 — 用 id 做 mapping key(更稳)。
    public var displayName: String {
        MotorsportNames.teamName(raw: id, series: .f1)
    }
}

// MARK: - 大奖赛

public nonisolated struct F1Race: MotorsportEvent, Identifiable, Hashable, Sendable, Codable {
    public let id: String              // "2025-1"（季+轮）
    public let leagueId: String        // "f1-2025"
    public let season: String          // "2025"
    public let round: Int              // 1 起
    public let raceName: String        // "Bahrain Grand Prix"
    public let circuit: Circuit
    public let sessions: [Session]
    public let status: EventStatus

    public var sport: Sport { .motorsport }
    public var series: MotorsportSeries { .f1 }

    /// SportEvent.startTime 取主赛 session 起始时间；无 race session 时回退到第一个 session。
    public var startTime: Date {
        mainRace?.startTime ?? sessions.first?.startTime ?? .distantPast
    }

    public var weekendStart: Date {
        sessions.first?.startTime ?? startTime
    }

    public var weekendEnd: Date {
        // race session 之后 3h 给 grace，然后切到 finished
        let last = sessions.last?.startTime ?? startTime
        return last.addingTimeInterval(3 * 3600)
    }

    public var headline: String { Localization.f1RaceName(raceName) }
    public var subheadline: String {
        let prefix = L10n.effective == .en ? "Round" : "第"
        let suffix = L10n.effective == .en ? "" : "轮"
        return "\(prefix) \(round)\(suffix) · \(circuit.locality), \(circuit.country)"
    }

    /// 赛道布局 SVG —— julesr0y community repo,本地优先 + jsdelivr CDN fallback。
    public var trackMapURL: URL? {
        guard let slug = CircuitMap.slugForF1(raceName: raceName) else { return nil }
        return CircuitMap.url(slug: slug)
    }

    /// 赛道图——formula1.com 官方 Cloudinary CDN,2018 redesign assets 路径。
    /// URL 模板:
    ///   https://media.formula1.com/image/upload/f_auto/q_auto/v1677244985/content/dam/fom-website/2018-redesign-assets/Circuit%20maps%2016x9/{NAME}_Circuit.png
    /// 24/24 GP 全 200。raceName 关键字 → {NAME} slug 映射,4 个不规则特例硬编码。
    public var bannerImageURL: URL? {
        guard let name = Self.f1OfficialCircuitName(raceName: raceName) else { return nil }
        let path = "Circuit maps 16x9/\(name)_Circuit.png"
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://media.formula1.com/image/upload/f_auto/q_auto/v1677244985/content/dam/fom-website/2018-redesign-assets/\(encoded)")
    }

    /// raceName 关键字匹配成 formula1.com 资源里的 {NAME} 段。
    /// 4 个不规则特例:Emilia_Romagna / Baku / USA / Abu_Dhabi;其它直接 TitleCase + 下划线。
    private static func f1OfficialCircuitName(raceName: String) -> String? {
        let n = raceName.lowercased()
        // 长前缀优先,避免短关键字被吞
        if n.contains("saudi")           { return "Saudi_Arabia" }
        if n.contains("abu dhabi")       { return "Abu_Dhabi" }
        if n.contains("united states")   { return "USA" }
        if n.contains("las vegas")       { return "Las_Vegas" }
        if n.contains("emilia") || n.contains("imola") { return "Emilia_Romagna" }
        if n.contains("azerbaijan")      { return "Baku" }
        if n.contains("são paulo") || n.contains("sao paulo") || n.contains("brazilian") { return "Brazil" }
        if n.contains("british")         { return "Great_Britain" }
        if n.contains("bahrain")         { return "Bahrain" }
        if n.contains("australian")      { return "Australia" }
        if n.contains("japanese")        { return "Japan" }
        if n.contains("chinese")         { return "China" }
        if n.contains("miami")           { return "Miami" }
        if n.contains("monaco")          { return "Monaco" }
        if n.contains("spanish")         { return "Spain" }
        if n.contains("canadian")        { return "Canada" }
        if n.contains("austrian")        { return "Austria" }
        if n.contains("hungarian")       { return "Hungary" }
        if n.contains("belgian")         { return "Belgium" }
        if n.contains("dutch")           { return "Netherlands" }
        if n.contains("italian")         { return "Italy" }
        if n.contains("singapore")       { return "Singapore" }
        if n.contains("mexican") || n.contains("mexico city") { return "Mexico" }
        if n.contains("qatar")           { return "Qatar" }
        return nil
    }
}

// MARK: - 积分榜

public nonisolated struct F1DriverStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { driver.id }
    public let position: Int
    public let points: Double
    public let wins: Int
    public let driver: F1Driver
    public let constructorIds: [String]
}

public nonisolated struct F1ConstructorStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { constructor.id }
    public let position: Int
    public let points: Double
    public let wins: Int
    public let constructor: F1Constructor
}

// MARK: - 比赛结果

/// 正赛 / Sprint 结果共用——Sprint 没有 fastestLap、status 大致相同。
public nonisolated struct F1RaceResult: Identifiable, Hashable, Sendable, Codable {
    public var id: String { driver.id }
    public let position: Int           // 实际排名；DNF 时为 grid 后顺延，position 仍可读
    public let positionText: String    // "1" / "R"(Retired) / "D"(Disqualified) / "W"(Withdrawn)
    public let points: Double
    public let grid: Int               // 起跑位
    public let laps: Int
    public let status: String          // "Finished" / "+1 Lap" / "Engine" / "Accident" …
    public let timeText: String?       // "1:31:44.742" 或 "+5.123" 或 nil（DNF）
    public let driver: F1Driver
    public let constructor: F1Constructor
    public let fastestLap: F1FastestLap?
}

public nonisolated struct F1FastestLap: Hashable, Sendable, Codable {
    public let rank: Int               // 1 = 全场最快
    public let lap: Int                // 第几圈
    public let timeText: String        // "1:32.608"
}

// MARK: - 排位赛结果

public nonisolated struct F1QualifyingResult: Identifiable, Hashable, Sendable, Codable {
    public var id: String { driver.id }
    public let position: Int
    public let driver: F1Driver
    public let constructor: F1Constructor
    public let q1: String?             // "1:30.123" 或 nil（未进 Q1）
    public let q2: String?
    public let q3: String?
}

// MARK: - 单场结果导航值

/// 详情页 race/quali/sprint 行 NavigationLink 用的值——同时携带 race 和 session,
/// 让 results view 知道拉哪个 endpoint。
public nonisolated struct F1SessionResultsRef: Hashable, Sendable {
    public let race: F1Race
    public let session: Session
}

// MARK: - 车手赛季每场积分(趋势图用)

public nonisolated struct F1DriverRoundPoints: Hashable, Sendable, Codable {
    public let round: Int
    public let raceName: String
    public let points: Double
}

