import Foundation
import os
import PoleDomain
import PoleSharedKit

nonisolated fileprivate let feLog = Logger(subsystem: "com.tiebowen.Pole", category: "FormulaEClient")

public enum FormulaEError: Error, LocalizedError {
    case invalidResponse(Int)
    case decoding(Error)
    case network(Error)
    case noActiveChampionship

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return "Formula E HTTP \(code)"
        case .decoding(let e):           return L10n.t(zh: "Formula E 数据解析失败:\(e.localizedDescription)", en: "Formula E decode failed: \(e.localizedDescription)")
        case .network(let e):            return L10n.t(zh: "Formula E 网络异常:\(e.localizedDescription)", en: "Formula E network error: \(e.localizedDescription)")
        case .noActiveChampionship:      return L10n.t(zh: "Formula E 找不到当前赛季", en: "Formula E current season not found")
        }
    }
}

/// Formula E 数据源——FIA Formula E 官方 Pulselive API。
/// 流程:先 fetch /championships 找 status=Present 的赛季,缓存其 UUID,
/// 再用 UUID 拿 races / standings/drivers / standings/teams。
public actor FormulaEClient {
    public static let shared = FormulaEClient()

    private let baseURL = URL(string: "https://api.formula-e.pulselive.com/formula-e/v1")!
    private let session: URLSession
    private let decoder: JSONDecoder

    /// 缓存当前 championship,避免每次都 fetch 一遍 championships 列表。
    private var cachedChampionshipId: String?
    private var cachedSeasonName: String?  // "SEASON 2025-2026"

    // 顶层 cache(避免 Timeline + RaceList + Standings + Widget + AI agent 各拉一份)
    private let roundsCache             = SeasonCache<[FERound]>(ttl: 3600)            // 赛历 1h
    private let driverStandingsCache    = SeasonCache<[FEDriverStanding]>(ttl: 300)    // 车手榜 5min
    private let teamStandingsCache      = SeasonCache<[FEConstructorStanding]>(ttl: 300) // 厂商榜 5min

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
        let dec = JSONDecoder()
        // FE 日期是 "2025-12-06" yyyy-MM-dd
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        dec.dateDecodingStrategy = .formatted(fmt)
        self.decoder = dec
    }

    // MARK: - Public

    /// 获取当前赛季所有 round。
    public func fetchSeasonRounds() async throws -> [FERound] {
        try await roundsCache.fetchOr(key: "current") {
            let (cid, seasonName) = try await self.currentChampionship()
            let url = self.baseURL.appendingPathComponent("races")
                .appending(queryItems: [URLQueryItem(name: "championshipId", value: cid)])
            let dto: RacesResponseDTO = try await self.get(url: url)
            let season = Self.parseSeason(seasonName)
            return dto.races.compactMap { $0.toDomain(seasonString: season) }
                .sorted { $0.round < $1.round }
        }
    }

    /// 当前赛季车手积分榜。
    public func fetchDriverStandings() async throws -> [FEDriverStanding] {
        try await driverStandingsCache.fetchOr(key: "current") {
            let (cid, _) = try await self.currentChampionship()
            let url = self.baseURL.appendingPathComponent("standings/drivers")
                .appending(queryItems: [URLQueryItem(name: "championshipId", value: cid)])
            let dto: [DriverStandingDTO] = try await self.get(url: url)
            return dto.compactMap { $0.toDomain() }.sorted { $0.position < $1.position }
        }
    }

    /// 当前赛季车队积分榜。
    public func fetchConstructorStandings() async throws -> [FEConstructorStanding] {
        try await teamStandingsCache.fetchOr(key: "current") {
            let (cid, _) = try await self.currentChampionship()
            let url = self.baseURL.appendingPathComponent("standings/teams")
                .appending(queryItems: [URLQueryItem(name: "championshipId", value: cid)])
            let dto: [TeamStandingDTO] = try await self.get(url: url)
            return dto.compactMap { $0.toDomain() }.sorted { $0.position < $1.position }
        }
    }

    // MARK: - Race detail(sessions + results)

    /// 单 race 的所有 sessions(FP/Qual/Race + 汇总表)。
    public func fetchSessions(raceId: String) async throws -> [FESession] {
        let url = baseURL.appendingPathComponent("races/\(raceId)/sessions")
        let dto: SessionsResponseDTO = try await get(url: url)
        return dto.sessions.map { $0.toDomain() }
    }

    /// 单 session 的完整 results。
    public func fetchSessionResults(raceId: String, sessionId: String) async throws -> [FESessionResult] {
        let url = baseURL.appendingPathComponent("races/\(raceId)/sessions/\(sessionId)/results")
        let dto: [SessionResultDTO] = try await get(url: url)
        return dto.map { $0.toDomain() }
            .sorted { ($0.driverPosition ?? 999) < ($1.driverPosition ?? 999) }
    }

    /// 单 driver 整季 round-by-round 积分(给积分趋势图用)。
    /// FE 没有公开的"单车手 season trajectory"端点,自己拉每个 finished round 的
    /// race session results,从中提取目标 driver 的 points(API 已含 pole/FL bonus)。
    ///
    /// 网络代价:`O(N)` 个 round × 2 次请求(fetchSessions + fetchSessionResults)。
    /// fetchSeasonRounds 自身已 cache,只有 N 次后续请求是新的,串行不并发避免速率限制。
    public func fetchDriverRoundPoints(driverId: String) async -> [FEDriverRoundPoints] {
        guard let rounds = try? await fetchSeasonRounds() else { return [] }
        let finished = rounds.filter { $0.currentStatus == .finished }
                             .sorted { $0.round < $1.round }
        var result: [FEDriverRoundPoints] = []
        for round in finished {
            guard let sessions = try? await fetchSessions(raceId: round.id) else { continue }
            // FE 单日单 race,找 kind == race 且有 result 的 session
            guard let raceSession = sessions.first(where: { $0.kind == .race && $0.hasResults }) else {
                continue
            }
            guard let rows = try? await fetchSessionResults(raceId: round.id, sessionId: raceSession.id),
                  let row = rows.first(where: { $0.driverId == driverId })
            else { continue }
            result.append(FEDriverRoundPoints(
                round: round.round,
                roundName: round.name,
                points: row.points,
                polePosition: row.polePosition,
                fastestLap: row.fastestLap
            ))
        }
        return result
    }

    // MARK: - Private

    /// 拿当前 championship UUID + 赛季名,带内存缓存(actor 隔离)。
    private func currentChampionship() async throws -> (id: String, seasonName: String) {
        if let cid = cachedChampionshipId, let name = cachedSeasonName {
            return (cid, name)
        }
        let url = baseURL.appendingPathComponent("championships")
        let dto: ChampionshipsResponseDTO = try await get(url: url)
        // 优先选 status="Present" 的当前赛季,找不到时降级到列表最后一个并 log 警告
        // (老逻辑 silent fallback 到 .last,Pulselive 改 status 字段名时整 app 显示上赛季无任何信号)。
        let active: ChampionshipDTO
        if let present = dto.championships.first(where: { $0.status == "Present" }) {
            active = present
        } else if let last = dto.championships.last {
            feLog.warning("currentChampionship: no status=Present, falling back to last (\(last.name, privacy: .public)) — Pulselive 可能改了 status 字段")
            active = last
        } else {
            throw FormulaEError.noActiveChampionship
        }
        cachedChampionshipId = active.id
        cachedSeasonName = active.name
        return (active.id, active.name)
    }

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FormulaEError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FormulaEError.invalidResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FormulaEError.invalidResponse(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw FormulaEError.decoding(error)
        }
    }

    /// "SEASON 2025-2026" → "2025-2026"
    nonisolated private static func parseSeason(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.last.map(String.init) ?? name
    }
}

// MARK: - DTOs(私有,只 toDomain 后对外)

private struct ChampionshipsResponseDTO: Sendable, nonisolated Decodable {
    let championships: [ChampionshipDTO]
}

private struct ChampionshipDTO: Sendable, nonisolated Decodable {
    let id: String
    let name: String
    let status: String
}

private struct RacesResponseDTO: Sendable, nonisolated Decodable {
    let races: [RaceDTO]
}

private struct RaceDTO: Sendable, nonisolated Decodable {
    let id: String
    let name: String
    let sequence: Int
    let country: String?
    let city: String?
    let date: Date?
    let raceLiveStatus: String?
    let circuit: CircuitDTO?
    let metadata: MetadataDTO?

    nonisolated func toDomain(seasonString: String) -> FERound? {
        guard let date else { return nil }
        let circuitDomain = Circuit(
            id: circuit?.id ?? "fe-circuit-\(sequence)",
            name: circuit?.circuitFullName ?? circuit?.circuitName ?? city ?? "Unknown",
            locality: city ?? "",
            country: country ?? circuit?.countryCode ?? ""
        )
        return FERound(
            id: id,
            leagueId: "fe-\(seasonString)",
            season: seasonString,
            round: sequence,
            name: name,
            circuit: circuitDomain,
            raceDate: date,
            status: Self.mapStatus(raceLiveStatus),
            racePath: metadata?.racePath
        )
    }

    nonisolated private static func mapStatus(_ raw: String?) -> EventStatus {
        switch raw {
        case "RACE_FINISHED":  return .finished
        case "RACE_LIVE":      return .live
        case "RACE_POSTPONED": return .postponed
        default:               return .upcoming
        }
    }
}

private struct CircuitDTO: Sendable, nonisolated Decodable {
    let id: String
    let circuitName: String
    let circuitFullName: String?
    let countryCode: String?
}

private struct MetadataDTO: Sendable, nonisolated Decodable {
    let racePath: String?
}

private struct DriverStandingDTO: Sendable, nonisolated Decodable {
    let driverId: String
    let driverFirstName: String
    let driverLastName: String
    let driverTLA: String?
    let driverCountry: String?
    let driverPosition: Int
    let driverPoints: Double
    let driverTeamName: String

    nonisolated func toDomain() -> FEDriverStanding {
        FEDriverStanding(
            position: driverPosition,
            points: driverPoints,
            driver: FEDriver(
                id: driverId,
                firstName: driverFirstName,
                lastName: driverLastName,
                tla: driverTLA,
                countryISO2: driverCountry
            ),
            teamName: driverTeamName
        )
    }
}

private struct TeamStandingDTO: Sendable, nonisolated Decodable {
    let teamId: String
    let teamName: String
    let teamPosition: Int
    let teamPoints: Double

    nonisolated func toDomain() -> FEConstructorStanding {
        FEConstructorStanding(
            position: teamPosition,
            points: teamPoints,
            team: FETeam(id: teamId, name: teamName)
        )
    }
}

private struct SessionsResponseDTO: Sendable, nonisolated Decodable {
    let sessions: [SessionDTO]
}

private struct SessionDTO: Sendable, nonisolated Decodable {
    let id: String
    let sessionName: String
    let startTime: String?
    let hasResults: Bool?
    let sessionLiveStatus: String?

    nonisolated func toDomain() -> FESession {
        FESession(
            id: id,
            sessionName: sessionName,
            startTime: startTime ?? "0",
            hasResults: hasResults ?? false,
            liveStatusRaw: sessionLiveStatus
        )
    }
}

private struct SessionResultDTO: Sendable, nonisolated Decodable {
    let driverPosition: Int?
    let driverId: String
    /// 淘汰赛(Qual Quarter-Final 等) result 不返 firstName/lastName,所以必须 optional。
    let driverFirstName: String?
    let driverLastName: String?
    let driverNumber: String?
    let driverTLA: String?
    let driverCountry: String?
    let team: TeamRefDTO?
    let sessionTime: String?
    let bestTime: String?
    let delay: String?
    let points: Double?
    let startingPosition: Int?
    let polePosition: Bool?
    let fastestLap: Bool?
    let dnf: Bool?
    let dnq: Bool?
    let dns: Bool?
    let dsq: Bool?
    let exc: Bool?

    struct TeamRefDTO: Sendable, nonisolated Decodable {
        let id: String?
        let name: String?
    }

    nonisolated func toDomain() -> FESessionResult {
        FESessionResult(
            driverPosition: driverPosition,
            driverId: driverId,
            driverFirstName: driverFirstName,
            driverLastName: driverLastName,
            driverNumber: driverNumber,
            driverTLA: driverTLA,
            driverCountryISO2: driverCountry,
            teamName: team?.name,
            sessionTimeText: sessionTime,
            bestTimeText: bestTime,
            delayText: delay,
            points: points ?? 0,
            startingPosition: startingPosition,
            polePosition: polePosition ?? false,
            fastestLap: fastestLap ?? false,
            dnf: dnf ?? false,
            dnq: dnq ?? false,
            dns: dns ?? false,
            dsq: dsq ?? false,
            exc: exc ?? false
        )
    }
}
