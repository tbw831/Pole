import Foundation
import os
import PoleDomain

nonisolated fileprivate let jolpicaLog = Logger(subsystem: "com.tiebowen.Pole", category: "JolpicaClient")

// MARK: - Errors

public enum JolpicaError: Error, LocalizedError {
    case invalidResponse(Int)
    case decoding(Error)
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return L10n.t(zh: "服务器返回 HTTP \(code)", en: "Server HTTP \(code)")
        case .decoding(let err):         return L10n.t(zh: "解析失败:\(err.localizedDescription)", en: "Decode failed: \(err.localizedDescription)")
        case .network(let err):          return L10n.t(zh: "网络异常:\(err.localizedDescription)", en: "Network error: \(err.localizedDescription)")
        }
    }
}

// MARK: - Client

/// Jolpica F1 API 客户端（Ergast 兼容，社区维护，免费无需注册）。
/// 文档：https://github.com/jolpica/jolpica-f1
public actor JolpicaClient {
    public static let shared = JolpicaClient()

    private let baseURL = URL(string: "https://api.jolpi.ca/ergast/f1")!
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Cache 层(避免 Timeline + RaceList + AI agent 各拉一份重复数据)

    private let racesCache    = SeasonCache<[F1Race]>(ttl: 3600)              // 赛历 1h
    private let standingsCache = SeasonCache<[F1DriverStanding]>(ttl: 300)     // 积分榜 5min
    private let constructorsCache = SeasonCache<[F1ConstructorStanding]>(ttl: 300)

    /// 当年（或指定赛季）所有大奖赛。season 传 "current" 表示当年。
    public func fetchSeasonRaces(season: String = "current") async throws -> [F1Race] {
        try await racesCache.fetchOr(key: season) {
            let url = self.baseURL.appendingPathComponent("\(season).json")
            let response: RaceListResponse = try await self.fetch(url: url)
            let table = response.MRData.RaceTable
            let leagueId = "f1-\(table.season)"
            // 跟踪 toDomain 失败 count — Ergast 偶尔 round/date 字段空时整场被 compactMap 丢出列表,
            // 老逻辑下 UI 显示赛历不全无错误信号,现在 > 0 时 log 让用户能在 Console.app 定位。
            let total = table.Races.count
            let domains = table.Races.compactMap { $0.toDomain(leagueId: leagueId) }
            let dropped = total - domains.count
            if dropped > 0 {
                jolpicaLog.warning("fetchSeasonRaces season=\(season, privacy: .public) dropped=\(dropped)/\(total)")
            }
            return domains
        }
    }

    public func fetchDriverStandings(season: String = "current") async throws -> [F1DriverStanding] {
        try await standingsCache.fetchOr(key: season) {
            let url = self.baseURL.appendingPathComponent("\(season)/driverstandings.json")
            let response: DriverStandingsResponse = try await self.fetch(url: url)
            return response.MRData.StandingsTable.StandingsLists.first?.DriverStandings.compactMap { $0.toDomain() } ?? []
        }
    }

    public func fetchConstructorStandings(season: String = "current") async throws -> [F1ConstructorStanding] {
        try await constructorsCache.fetchOr(key: season) {
            let url = self.baseURL.appendingPathComponent("\(season)/constructorstandings.json")
            let response: ConstructorStandingsResponse = try await self.fetch(url: url)
            return response.MRData.StandingsTable.StandingsLists.first?.ConstructorStandings.compactMap { $0.toDomain() } ?? []
        }
    }

    /// 单场正赛结果。Round 用整数（1 起）。
    public func fetchRaceResults(season: String, round: Int) async throws -> [F1RaceResult] {
        let url = baseURL.appendingPathComponent("\(season)/\(round)/results.json")
        let response: RaceResultsResponse = try await fetch(url: url)
        return response.MRData.RaceTable.Races.first?.Results?.compactMap { $0.toDomain() } ?? []
    }

    /// 单场冲刺赛结果（仅 sprint 周才有，否则返回空数组）。
    public func fetchSprintResults(season: String, round: Int) async throws -> [F1RaceResult] {
        let url = baseURL.appendingPathComponent("\(season)/\(round)/sprint.json")
        let response: SprintResultsResponse = try await fetch(url: url)
        return response.MRData.RaceTable.Races.first?.SprintResults?.compactMap { $0.toDomain() } ?? []
    }

    /// 单场排位赛结果。
    public func fetchQualifyingResults(season: String, round: Int) async throws -> [F1QualifyingResult] {
        let url = baseURL.appendingPathComponent("\(season)/\(round)/qualifying.json")
        let response: QualifyingResultsResponse = try await fetch(url: url)
        return response.MRData.RaceTable.Races.first?.QualifyingResults?.compactMap { $0.toDomain() } ?? []
    }

    /// 单 driver 整季 race-by-race 积分(给积分趋势图用)。
    /// jolpica 的 `/{season}/drivers/{driverId}/results.json` 返回该 driver 当季所有 race,
    /// 每场只 1 条 result(就是他自己),含 points。
    public func fetchDriverSeasonResults(season: String, driverId: String) async throws -> [F1DriverRoundPoints] {
        let url = baseURL.appendingPathComponent("\(season)/drivers/\(driverId)/results.json")
        let response: DriverResultsResponse = try await fetch(url: url)
        return response.MRData.RaceTable.Races.compactMap { race -> F1DriverRoundPoints? in
            guard let round = Int(race.round),
                  let pts = race.Results.first.flatMap({ Double($0.points) }) else { return nil }
            return F1DriverRoundPoints(round: round, raceName: race.raceName, points: pts)
        }
    }

    /// 赛季全部车手（用于 Follow 选择器）。
    public func fetchDrivers(season: String = "current") async throws -> [F1Driver] {
        let url = baseURL.appendingPathComponent("\(season)/drivers.json")
        let response: DriversResponse = try await fetch(url: url)
        return response.MRData.DriverTable.Drivers.map { $0.toDomain() }
    }

    /// 赛季全部车队。
    public func fetchConstructors(season: String = "current") async throws -> [F1Constructor] {
        let url = baseURL.appendingPathComponent("\(season)/constructors.json")
        let response: ConstructorsResponse = try await fetch(url: url)
        return response.MRData.ConstructorTable.Constructors.map { $0.toDomain() }
    }

    private func fetch<T: Decodable & Sendable>(url: URL) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw JolpicaError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw JolpicaError.invalidResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw JolpicaError.invalidResponse(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw JolpicaError.decoding(error)
        }
    }
}

// MARK: - DTO（Ergast 风格：所有数字都是字符串）
// 这部分是 jolpica/Ergast 的 wire format，与 Domain 类型隔离，不外泄。

private struct RaceListResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable {
        let RaceTable: RaceTable
    }
    struct RaceTable: Sendable, nonisolated Decodable {
        let season: String
        let Races: [RaceDTO]
    }
    let MRData: Inner
}

private struct DriverStandingsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable {
        let StandingsTable: StandingsTable
    }
    struct StandingsTable: Sendable, nonisolated Decodable {
        let season: String
        let StandingsLists: [StandingsList]
    }
    struct StandingsList: Sendable, nonisolated Decodable {
        let season: String
        let round: String
        let DriverStandings: [DriverStandingDTO]
    }
    let MRData: Inner
}

private struct ConstructorStandingsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable {
        let StandingsTable: StandingsTable
    }
    struct StandingsTable: Sendable, nonisolated Decodable {
        let season: String
        let StandingsLists: [StandingsList]
    }
    struct StandingsList: Sendable, nonisolated Decodable {
        let season: String
        let round: String
        let ConstructorStandings: [ConstructorStandingDTO]
    }
    let MRData: Inner
}

private struct RaceDTO: Sendable, nonisolated Decodable {
    let season: String
    let round: String
    let raceName: String
    let Circuit: CircuitDTO
    let date: String                          // "2025-03-02"
    let time: String?                         // "15:00:00Z"
    // 周末其他 session（仅在赛历中提供，结果接口不一定返回）：
    let FirstPractice: SessionDTO?
    let SecondPractice: SessionDTO?
    let ThirdPractice: SessionDTO?
    let Qualifying: SessionDTO?
    let Sprint: SessionDTO?
    let SprintQualifying: SessionDTO?         // 2024+ sprint 周替代 SprintShootout

    nonisolated func toDomain(leagueId: String) -> F1Race? {
        guard let roundInt = Int(round) else { return nil }
        guard let raceStart = Self.parseDate(date: date, time: time) else { return nil }
        let circuit = Circuit.toDomain()
        let raceId = "\(season)-\(round)"
        let sessions = buildSessions(raceId: raceId, raceStart: raceStart)
        let status: EventStatus = raceStart > Date() ? .upcoming : .finished
        return F1Race(
            id: raceId,
            leagueId: leagueId,
            season: season,
            round: roundInt,
            raceName: raceName,
            circuit: circuit,
            sessions: sessions,
            status: status
        )
    }

    private nonisolated func buildSessions(raceId: String, raceStart: Date) -> [Session] {
        var out: [Session] = []
        func add(_ dto: SessionDTO?, kind: Session.Kind, label: String, slug: String) {
            guard let dto, let start = Self.parseDate(date: dto.date, time: dto.time) else { return }
            out.append(Session(id: "\(raceId)-\(slug)", kind: kind, label: label, startTime: start))
        }
        add(FirstPractice,    kind: .practice,       label: "FP1",       slug: "fp1")
        add(SecondPractice,   kind: .practice,       label: "FP2",       slug: "fp2")
        add(ThirdPractice,    kind: .practice,       label: "FP3",       slug: "fp3")
        add(SprintQualifying, kind: .sprintShootout, label: "Sprint Quali", slug: "sq")
        add(Sprint,           kind: .sprint,         label: "Sprint",    slug: "sprint")
        add(Qualifying,       kind: .qualifying,     label: "Qualifying", slug: "quali")
        out.append(Session(id: "\(raceId)-race", kind: .race, label: "Race", startTime: raceStart))
        return out.sorted { $0.startTime < $1.startTime }
    }

    private nonisolated static func parseDate(date: String, time: String?) -> Date? {
        let iso = "\(date)T\(time ?? "00:00:00Z")"
        return jolpicaIsoFormatter.date(from: iso)
    }
}

/// 共享 formatter — 原本每次 parseDate / DriverDTO.toDomain 都 `ISO8601DateFormatter()` 新建,
/// 赛历 N 场 × 5 session + 20 个 driver 一次 fetch 创建上百个临时 formatter。
/// `ISO8601DateFormatter` 自 iOS 7 起 thread-safe,且整个文件 actor / nonisolated 上下文都能复用。
/// `ISO8601DateFormatter` 没标 Sendable(Foundation 历史原因),但自 iOS 7 起实测 thread-safe。
/// `nonisolated(unsafe)` 显式承认 — 我们只读不写 formatter 配置,read-only 共享安全。
nonisolated(unsafe) fileprivate let jolpicaIsoFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

private struct SessionDTO: Sendable, nonisolated Decodable {
    let date: String
    let time: String?
}

private struct CircuitDTO: Sendable, nonisolated Decodable {
    let circuitId: String
    let circuitName: String
    let Location: LocationDTO

    struct LocationDTO: Sendable, nonisolated Decodable {
        let locality: String
        let country: String
    }

    nonisolated func toDomain() -> Circuit {
        Circuit(id: circuitId, name: circuitName, locality: Location.locality, country: Location.country)
    }
}

private struct DriverDTO: Sendable, nonisolated Decodable {
    let driverId: String
    let permanentNumber: String?
    let code: String?
    let givenName: String
    let familyName: String
    let dateOfBirth: String?
    let nationality: String

    nonisolated func toDomain() -> F1Driver {
        F1Driver(
            id: driverId,
            code: code,
            permanentNumber: permanentNumber.flatMap(Int.init),
            givenName: givenName,
            familyName: familyName,
            nationality: nationality,
            dateOfBirth: dateOfBirth.flatMap { jolpicaIsoFormatter.date(from: "\($0)T00:00:00Z") }
        )
    }
}

private struct ConstructorDTO: Sendable, nonisolated Decodable {
    let constructorId: String
    let name: String
    let nationality: String

    nonisolated func toDomain() -> F1Constructor {
        F1Constructor(id: constructorId, name: name, nationality: nationality)
    }
}

private struct DriverStandingDTO: Sendable, nonisolated Decodable {
    let position: String
    let points: String
    let wins: String
    let Driver: DriverDTO
    let Constructors: [ConstructorDTO]

    nonisolated func toDomain() -> F1DriverStanding? {
        guard let pos = Int(position),
              let pts = Double(points),
              let w = Int(wins) else { return nil }
        return F1DriverStanding(
            position: pos,
            points: pts,
            wins: w,
            driver: Driver.toDomain(),
            constructorIds: Constructors.map(\.constructorId)
        )
    }
}

private struct ConstructorStandingDTO: Sendable, nonisolated Decodable {
    let position: String
    let points: String
    let wins: String
    let Constructor: ConstructorDTO

    nonisolated func toDomain() -> F1ConstructorStanding? {
        guard let pos = Int(position),
              let pts = Double(points),
              let w = Int(wins) else { return nil }
        return F1ConstructorStanding(
            position: pos,
            points: pts,
            wins: w,
            constructor: Constructor.toDomain()
        )
    }
}

// MARK: - Results DTOs

private struct RaceResultsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable { let RaceTable: RaceTable }
    struct RaceTable: Sendable, nonisolated Decodable { let Races: [RaceWrap] }
    struct RaceWrap: Sendable, nonisolated Decodable { let Results: [ResultDTO]? }
    let MRData: Inner
}

private struct SprintResultsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable { let RaceTable: RaceTable }
    struct RaceTable: Sendable, nonisolated Decodable { let Races: [RaceWrap] }
    struct RaceWrap: Sendable, nonisolated Decodable { let SprintResults: [ResultDTO]? }
    let MRData: Inner
}

private struct QualifyingResultsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable { let RaceTable: RaceTable }
    struct RaceTable: Sendable, nonisolated Decodable { let Races: [RaceWrap] }
    struct RaceWrap: Sendable, nonisolated Decodable { let QualifyingResults: [QualifyingResultDTO]? }
    let MRData: Inner
}

private struct DriversResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable { let DriverTable: DriverTable }
    struct DriverTable: Sendable, nonisolated Decodable { let Drivers: [DriverDTO] }
    let MRData: Inner
}

private struct ConstructorsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable { let ConstructorTable: ConstructorTable }
    struct ConstructorTable: Sendable, nonisolated Decodable { let Constructors: [ConstructorDTO] }
    let MRData: Inner
}

private struct ResultDTO: Sendable, nonisolated Decodable {
    let position: String
    let positionText: String
    let points: String
    let grid: String
    let laps: String
    let status: String
    let Driver: DriverDTO
    let Constructor: ConstructorDTO
    let Time: TimeDTO?
    let FastestLap: FastestLapDTO?

    struct TimeDTO: Sendable, nonisolated Decodable {
        let time: String?
    }

    struct FastestLapDTO: Sendable, nonisolated Decodable {
        let rank: String?
        let lap: String?
        let Time: InnerTime?
        struct InnerTime: Sendable, nonisolated Decodable { let time: String? }
    }

    nonisolated func toDomain() -> F1RaceResult? {
        guard let pos = Int(position),
              let pts = Double(points),
              let g = Int(grid),
              let l = Int(laps) else { return nil }
        let fl: F1FastestLap? = {
            guard let raw = FastestLap,
                  let rank = raw.rank.flatMap(Int.init),
                  let lap = raw.lap.flatMap(Int.init),
                  let timeText = raw.Time?.time else { return nil }
            return F1FastestLap(rank: rank, lap: lap, timeText: timeText)
        }()
        return F1RaceResult(
            position: pos,
            positionText: positionText,
            points: pts,
            grid: g,
            laps: l,
            status: status,
            timeText: Time?.time,
            driver: Driver.toDomain(),
            constructor: Constructor.toDomain(),
            fastestLap: fl
        )
    }
}

private struct DriverResultsResponse: Sendable, nonisolated Decodable {
    struct Inner: Sendable, nonisolated Decodable { let RaceTable: RaceTable }
    struct RaceTable: Sendable, nonisolated Decodable { let Races: [RaceWrap] }
    struct RaceWrap: Sendable, nonisolated Decodable {
        let round: String
        let raceName: String
        let Results: [PointsOnly]
    }
    struct PointsOnly: Sendable, nonisolated Decodable { let points: String }
    let MRData: Inner
}

private struct QualifyingResultDTO: Sendable, nonisolated Decodable {
    let position: String
    let Driver: DriverDTO
    let Constructor: ConstructorDTO
    let Q1: String?
    let Q2: String?
    let Q3: String?

    nonisolated func toDomain() -> F1QualifyingResult? {
        guard let pos = Int(position) else { return nil }
        return F1QualifyingResult(
            position: pos,
            driver: Driver.toDomain(),
            constructor: Constructor.toDomain(),
            q1: Q1,
            q2: Q2,
            q3: Q3
        )
    }
}
