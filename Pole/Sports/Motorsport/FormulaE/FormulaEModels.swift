import Foundation

// MARK: - Round

/// Formula E 一站 E-Prix(单日赛事,不像 F1/MotoGP 三天周末)。
/// `date` 是赛日,我们把 weekendStart/End 都映射到同一天的早晚。
public nonisolated struct FERound: MotorsportEvent, Identifiable, Hashable, Sendable, Codable {
    public let id: String           // race UUID(Pulselive)
    public let leagueId: String     // "fe-2025-2026"
    public let season: String       // "2025-2026"(赛季横跨两年)
    public let round: Int           // sequence
    public let name: String         // "2025 Google Cloud São Paulo E-Prix"
    public let circuit: Circuit
    public let raceDate: Date       // 赛日(单日)
    public let status: EventStatus
    /// 路径片段,跳到官网用("/calendar/2025-26/r1-sao-paulo")
    public let racePath: String?

    public var sport: Sport { .motorsport }
    public var series: MotorsportSeries { .fe }

    public var startTime: Date { raceDate }

    public var sessions: [Session] { [] }   // FE 单日,详情页另外接

    public var weekendStart: Date {
        // 单日早 8 点(北京时区粗略对齐)
        Self.bjCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: raceDate) ?? raceDate
    }

    public var weekendEnd: Date {
        // 单日晚 23:59
        Self.bjCalendar.date(bySettingHour: 23, minute: 59, second: 0, of: raceDate) ?? raceDate
    }

    /// nonisolated Calendar 实例,避免在 nonisolated context 触发 main-actor 隔离 warning。
    private static let bjCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }()

    public var headline: String {
        Localization.feRaceName(name)
    }

    public var subheadline: String {
        let countryDisplay = ChineseCountry.fromISO2(circuit.country) ?? circuit.country
        let prefix = L10n.effective == .en ? "Round" : "第"
        let suffix = L10n.effective == .en ? "" : "轮"
        return "\(prefix) \(round)\(suffix) · \(circuit.locality), \(countryDisplay)"
    }
}

// MARK: - Standings

public nonisolated struct FEDriver: Identifiable, Hashable, Sendable, Codable {
    public let id: String           // driverId UUID
    public let firstName: String
    public let lastName: String
    public let tla: String?         // 三字母缩写"WEH"/"EVA"
    public let countryISO2: String? // "DE"/"NZ"——已经是 ISO2

    public var fullName: String { "\(firstName) \(lastName)" }

    public var displayName: String {
        MotorsportNames.driverShortName(rawFullName: fullName, series: .fe)
    }

    public var displayFullName: String {
        MotorsportNames.driverFullName(rawFullName: fullName, series: .fe)
    }
}

public nonisolated struct FETeam: Identifiable, Hashable, Sendable, Codable {
    public let id: String           // teamId UUID
    public let name: String         // "PORSCHE FORMULA E TEAM"

    public var displayName: String {
        MotorsportNames.teamName(raw: name, series: .fe)
    }
}

public nonisolated struct FEDriverStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { driver.id }
    public let position: Int
    public let points: Double
    public let driver: FEDriver
    public let teamName: String
}

public nonisolated struct FEConstructorStanding: Identifiable, Hashable, Sendable, Codable {
    public var id: String { team.id }
    public let position: Int
    public let points: Double
    public let team: FETeam
}

// MARK: - Session(单 race 内部的 FP/Quali/Race/汇总表)

public nonisolated struct FESession: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let sessionName: String        // "Free Practice 2" / "Qual Group A" / "Race" / "Starting grid" / "Combined qualifying" / "Fastest lap"
    public let startTime: String          // "07:10" / "0"(汇总型 session 无时间)
    public let hasResults: Bool
    public let liveStatusRaw: String?     // "NOT_STARTED" / "FINISHED" / nil

    /// 没真实赛场时间的"派生汇总 session"(Combined qualifying / Starting grid / Fastest lap / Qualifying grid)。
    public var isSummary: Bool { startTime == "0" }

    /// 类别 - 用于 UI 分类显示。
    public enum Kind: String, Sendable {
        case practice    // FP1/FP2/FP3/Rookie
        case qualifying  // Qual Group A/B / Quarter-Final / Semi-Final / Qual Final
        case race        // Race
        case summary     // Combined qualifying / Starting grid / Fastest lap / Qualifying grid
    }

    public var kind: Kind {
        let n = sessionName.lowercased()
        if isSummary { return .summary }
        if n.contains("race") { return .race }
        if n.contains("free practice") || n.contains("rookie") { return .practice }
        if n.contains("qual") { return .qualifying }
        return .summary
    }

    /// session 名 —— 中英自动切换(英文 pass-through 直接用 sessionName)。
    public var localizedDisplayName: String {
        if L10n.effective == .en { return sessionName }
        switch sessionName {
        case "Free Practice 1":      return "练习 1"
        case "Free Practice 2":      return "练习 2"
        case "Rookie Free Practice": return "新秀练习"
        case "Qual Group A":         return "排位 A 组"
        case "Qual Group B":         return "排位 B 组"
        case "Qual Quarter-Final 1": return "排位 1/4 决 1"
        case "Qual Quarter-Final 2": return "排位 1/4 决 2"
        case "Qual Quarter-Final 3": return "排位 1/4 决 3"
        case "Qual Quarter-Final 4": return "排位 1/4 决 4"
        case "Qual Semi-Final 1":    return "排位半决 1"
        case "Qual Semi-Final 2":    return "排位半决 2"
        case "Qual Final":           return "排位决赛"
        case "Race":                 return "正赛"
        case "Combined qualifying":  return "排位综合"
        case "Starting grid":        return "发车顺序"
        case "Qualifying grid":      return "排位榜单"
        case "Fastest lap":          return "最快圈速"
        default:                     return sessionName
        }
    }
}

/// 路由值——把 round + session 一起带到 results 页。
public nonisolated struct FESessionRef: Hashable, Sendable, Identifiable {
    public let round: FERound
    public let session: FESession
    public var id: String { "\(round.id)-\(session.id)" }
}

// MARK: - 单 driver 整季 round-by-round 积分(给积分趋势图用)

/// 一站 E-Prix 中一名车手的得分 + bonus 标记。
/// `points` 来自 FE API,已含 pole/FL bonus(API 直接给好的最终得分)。
public nonisolated struct FEDriverRoundPoints: Identifiable, Hashable, Sendable, Codable {
    public let round: Int
    public let roundName: String      // round.name 全名,如 "2025 Google Cloud São Paulo E-Prix"
    public let points: Double         // 含 pole +3 / FL +1 等 bonus
    public let polePosition: Bool     // 显示用,points 已含此奖励
    public let fastestLap: Bool       // 显示用,points 已含此奖励

    public var id: Int { round }
}

// MARK: - Session results

public nonisolated struct FESessionResult: Identifiable, Hashable, Sendable, Codable {
    public var id: String { driverId }
    public let driverPosition: Int?
    public let driverId: String
    /// 淘汰赛(Qual Quarter-Final 等)的 result 不返 firstName/lastName,只有 TLA + number。
    public let driverFirstName: String?
    public let driverLastName: String?
    public let driverNumber: String?       // "27" - FE 给字符串
    public let driverTLA: String?
    public let driverCountryISO2: String?
    public let teamName: String?
    public let sessionTimeText: String?    // "0:59:23:013"
    public let bestTimeText: String?       // "0:1:12:960"
    public let delayText: String?          // "-" / "+0.123"
    public let points: Double
    public let startingPosition: Int?
    public let polePosition: Bool
    public let fastestLap: Bool
    public let dnf: Bool
    public let dnq: Bool
    public let dns: Bool
    public let dsq: Bool
    public let exc: Bool

    /// 显示名 —— 优先 firstName+lastName,缺则用 TLA,都缺退到 "#number" / "—"。
    public var fullName: String {
        if let f = driverFirstName, let l = driverLastName, !(f.isEmpty && l.isEmpty) {
            return "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        }
        if let tla = driverTLA, !tla.isEmpty { return tla }
        if let n = driverNumber { return "#\(n)" }
        return "—"
    }

    /// 中英自动切换的短名(给 results 行用)。TLA / "#number" / "—" 不走 mapping。
    public var displayName: String {
        if let f = driverFirstName, let l = driverLastName, !(f.isEmpty && l.isEmpty) {
            let raw = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
            return MotorsportNames.driverShortName(rawFullName: raw, series: .fe)
        }
        return fullName
    }

    /// 车队名(中英自动切换)。无 teamName 时返"—"。
    public var displayTeamName: String {
        guard let tn = teamName, !tn.isEmpty else { return "—" }
        return MotorsportNames.teamName(raw: tn, series: .fe)
    }

    /// "P" / "FL" / "DNF" / "DSQ" 等标记串。
    public var statusFlags: String {
        var flags: [String] = []
        if polePosition { flags.append("P") }
        if fastestLap   { flags.append("FL") }
        if dnf          { flags.append("DNF") }
        if dnq          { flags.append("DNQ") }
        if dns          { flags.append("DNS") }
        if dsq          { flags.append("DSQ") }
        if exc          { flags.append("EXC") }
        return flags.joined(separator: " ")
    }
}
