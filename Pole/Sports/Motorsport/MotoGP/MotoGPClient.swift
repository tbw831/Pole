import Foundation
import os
import PoleDomain

// MARK: - Errors

public enum MotoGPError: Error, LocalizedError {
    case invalidResponse(Int, URL?)
    case decoding(Error)
    case network(Error)
    case noCurrentSeason
    case noMotoGPCategory

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code, let url):
            let path = url?.path ?? "?"
            return "MotoGP HTTP \(code) — \(path)"
        case .decoding(let err):
            // 解包 DecodingError 显示具体哪个字段错——默认 localizedDescription 只说 "data missing" 没用
            if let de = err as? DecodingError {
                let path: String
                switch de {
                case .keyNotFound(let key, let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    return L10n.t(zh: "MotoGP 缺字段 '\(key.stringValue)' @ \(path)",
                                  en: "MotoGP missing field '\(key.stringValue)' @ \(path)")
                case .typeMismatch(let type, let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    return L10n.t(zh: "MotoGP 类型不符 '\(type)' @ \(path)",
                                  en: "MotoGP type mismatch '\(type)' @ \(path)")
                case .valueNotFound(let type, let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    return L10n.t(zh: "MotoGP 值为 null '\(type)' @ \(path)",
                                  en: "MotoGP null value '\(type)' @ \(path)")
                case .dataCorrupted(let ctx):
                    path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
                    return L10n.t(zh: "MotoGP 数据损坏 @ \(path): \(ctx.debugDescription)",
                                  en: "MotoGP data corrupted @ \(path): \(ctx.debugDescription)")
                @unknown default: break
                }
            }
            return L10n.t(zh: "MotoGP 解析失败:\(err.localizedDescription)",
                          en: "MotoGP decode failed: \(err.localizedDescription)")
        case .network(let err):
            return L10n.t(zh: "MotoGP 网络异常:\(err.localizedDescription)",
                          en: "MotoGP network error: \(err.localizedDescription)")
        case .noCurrentSeason:
            return L10n.t(zh: "找不到当前赛季", en: "Current season not found")
        case .noMotoGPCategory:
            return L10n.t(zh: "找不到 MotoGP 类别", en: "MotoGP category not found")
        }
    }
}

// MARK: - Client

/// MotoGP API 客户端,基于 Pulselive 官方后端(motogp.com 同源)。
/// 无公开 API 文档,字段结构来自实测。Pulselive 的资源用 UUID 索引,
/// 每次拉数据需要先取 seasonUuid + MotoGP categoryUuid,actor 内做 lazy 缓存。
public actor MotoGPClient {
    public static let shared = MotoGPClient()

    private let baseURL = URL(string: "https://api.motogp.pulselive.com/motogp/v1/results")!
    private let session: URLSession
    private let decoder: JSONDecoder
    private let isoDateTimeFormatter: ISO8601DateFormatter
    private let isoDateOnlyFormatter: ISO8601DateFormatter

    // 缓存——actor 内可变,跨调用复用避免重复请求
    private var currentSeasonCache: SeasonInfo?
    private var motoGPCategoryIdCache: String?

    // 顶层 cache(避免 Timeline + RaceList + Standings + AI agent 各拉一份重复数据)
    private let roundsCache         = SeasonCache<[MotoGPRound]>(ttl: 3600)         // 赛历 1h
    private let riderStandingsCache = SeasonCache<[MotoGPRiderStanding]>(ttl: 300)  // 积分榜 5min

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
        self.decoder = JSONDecoder()
        self.isoDateTimeFormatter = ISO8601DateFormatter()
        self.isoDateTimeFormatter.formatOptions = [.withInternetDateTime]
        self.isoDateOnlyFormatter = ISO8601DateFormatter()
        self.isoDateOnlyFormatter.formatOptions = [.withFullDate]
    }

    private struct SeasonInfo: Sendable {
        let id: String
        let year: Int
    }

    // MARK: Public API

    /// 当年所有比赛(剔除 test events)。
    public func fetchSeasonRounds() async throws -> [MotoGPRound] {
        try await roundsCache.fetchOr(key: "current") {
            let season = try await self.currentSeason()
            let categoryId = try await self.motoGPCategoryId(seasonId: season.id)
            _ = categoryId  // categoryId 留给 fetchSessions 用,赛历不需要

            var url = self.baseURL.appendingPathComponent("events")
            url.append(queryItems: [URLQueryItem(name: "seasonUuid", value: season.id)])
            let dtos: [EventDTO] = try await self.fetch(url: url)

            let leagueId = "motogp-\(season.year)"
            let real = dtos.filter { $0.test == false }
            return real.enumerated().compactMap { idx, dto in
                dto.toDomain(round: idx + 1, leagueId: leagueId, seasonYear: season.year)
            }
        }
    }

    /// 单个 event 的周末完整 sessions(MotoGP class)。详情页 task 中调用。
    /// 返回 `MotoGPSessionRef` 而非裸 `Session`,保留原始 UUID 给 classification 端点用。
    public func fetchSessions(eventId: String) async throws -> [MotoGPSessionRef] {
        let season = try await currentSeason()
        let categoryId = try await motoGPCategoryId(seasonId: season.id)

        var url = baseURL.appendingPathComponent("sessions")
        url.append(queryItems: [
            URLQueryItem(name: "eventUuid", value: eventId),
            URLQueryItem(name: "categoryUuid", value: categoryId),
        ])
        let dtos: [SessionDTO] = try await fetch(url: url)
        return dtos
            .compactMap { $0.toRef(eventId: eventId, formatter: isoDateTimeFormatter) }
            .sorted { $0.session.startTime < $1.session.startTime }
    }

    /// 单 session 的 classification——已结束的 session 才有数据。
    public func fetchSessionResults(sessionId: String) async throws -> [MotoGPRaceResult] {
        let url = baseURL
            .appendingPathComponent("session")
            .appendingPathComponent(sessionId)
            .appendingPathComponent("classification")
        let response: ClassificationResponse = try await fetch(url: url)
        return response.classification.compactMap { $0.toDomain() }
    }

    /// 车手积分榜(MotoGP class)。
    public func fetchRiderStandings() async throws -> [MotoGPRiderStanding] {
        try await riderStandingsCache.fetchOr(key: "current") {
            let dtos = try await self.fetchRawClassification()
            return dtos.compactMap { $0.toDomain() }
        }
    }

    /// 车队积分榜——客户端按 team.id 聚合 rider points(Pulselive `type=team` 参数无效)。
    public func fetchTeamStandings() async throws -> [MotoGPTeamStanding] {
        let riderStandings = try await fetchRiderStandings()
        // 按 team.id 分组,points 求和;每组 rider 名按 points 倒序保留
        let groups = Dictionary(grouping: riderStandings, by: { $0.team.id })
        let teams: [(team: MotoGPTeam, points: Double, riders: [String])] = groups.values.map { rows in
            let sortedByPoints = rows.sorted { $0.points > $1.points }
            let totalPoints = rows.reduce(0.0) { $0 + $1.points }
            return (sortedByPoints[0].team, totalPoints, sortedByPoints.map { $0.rider.fullName })
        }
        let sorted = teams.sorted { $0.points > $1.points }
        return sorted.enumerated().map { idx, t in
            MotoGPTeamStanding(position: idx + 1, points: t.points, team: t.team, riderNames: t.riders)
        }
    }

    /// 单 rider 整季 round-by-round 积分(给积分趋势图用)。
    /// MotoGP 没有公开的"单车手 season trajectory"端点,自己拉每个 finished round 的
    /// race + sprint classification,从中提取目标 rider 的 points。
    ///
    /// 网络代价:`O(N)` 个 round × 1-2 个 race/sprint session,每个 round 大约 2-3 次请求。
    /// 进车手详情页时一次性串行拉完(并发可能触发 Pulselive 速率限制,保守串行)。
    /// fetchSeasonRounds 自身已 cache,所以只有 fetchSessions/fetchSessionResults 是新请求。
    public func fetchRiderRoundPoints(riderId: String) async -> [MotoGPRiderRoundPoints] {
        guard let rounds = try? await fetchSeasonRounds() else { return [] }
        let finished = rounds.filter { $0.currentStatus == .finished }
                             .sorted { $0.round < $1.round }
        var result: [MotoGPRiderRoundPoints] = []
        for round in finished {
            guard let sessionRefs = try? await fetchSessions(eventId: round.id) else { continue }
            var racePts = 0.0
            var sprintPts = 0.0
            for ref in sessionRefs where ref.session.kind == .race || ref.session.kind == .sprint {
                guard let rows = try? await fetchSessionResults(sessionId: ref.rawId),
                      let row = rows.first(where: { $0.rider.id == riderId })
                else { continue }
                if ref.session.kind == .race {
                    racePts = row.points
                } else if ref.session.kind == .sprint {
                    sprintPts = row.points
                }
            }
            result.append(MotoGPRiderRoundPoints(
                round: round.round,
                roundName: round.shortName,
                racePoints: racePts,
                sprintPoints: sprintPts
            ))
        }
        return result
    }

    /// 厂商榜——客户端按 constructor.id 聚合(同一厂商旗下多个车队)。
    /// 注意:严格的 MotoGP 厂商榜规则是"每个厂商每场只算最高名次车手得分",
    /// 我们这里简化为车手 points 直接求和——结果绝对值偏大,但相对顺序通常一致。
    public func fetchConstructorStandings() async throws -> [MotoGPConstructorStanding] {
        let riderStandings = try await fetchRiderStandings()
        let groups = Dictionary(grouping: riderStandings, by: { $0.constructor.id })
        let constructors: [(constructor: MotoGPConstructor, points: Double)] = groups.values.map { rows in
            let totalPoints = rows.reduce(0.0) { $0 + $1.points }
            return (rows[0].constructor, totalPoints)
        }
        let sorted = constructors.sorted { $0.points > $1.points }
        return sorted.enumerated().map { idx, c in
            MotoGPConstructorStanding(position: idx + 1, points: c.points, constructor: c.constructor)
        }
    }

    private func fetchRawClassification() async throws -> [ClassificationDTO] {
        let season = try await currentSeason()
        let categoryId = try await motoGPCategoryId(seasonId: season.id)

        var url = baseURL.appendingPathComponent("standings")
        url.append(queryItems: [
            URLQueryItem(name: "seasonUuid", value: season.id),
            URLQueryItem(name: "categoryUuid", value: categoryId),
        ])
        let response: StandingsResponse = try await fetch(url: url)
        return response.classification
    }

    // MARK: Cache helpers

    private func currentSeason() async throws -> SeasonInfo {
        if let hit = currentSeasonCache { return hit }
        let url = baseURL.appendingPathComponent("seasons")
        let dtos: [SeasonDTO] = try await fetch(url: url)
        guard let cur = dtos.first(where: { $0.current == true }) else {
            throw MotoGPError.noCurrentSeason
        }
        let info = SeasonInfo(id: cur.id, year: cur.year)
        currentSeasonCache = info
        return info
    }

    private func motoGPCategoryId(seasonId: String) async throws -> String {
        if let hit = motoGPCategoryIdCache { return hit }
        var url = baseURL.appendingPathComponent("categories")
        url.append(queryItems: [URLQueryItem(name: "seasonUuid", value: seasonId)])
        let dtos: [CategoryDTO] = try await fetch(url: url)
        // 用 legacy_id == 3 兜底,name 偶尔含 ™ 字符可能不稳;两条件都试
        guard let cat = dtos.first(where: { $0.legacy_id == 3 || $0.name.contains("MotoGP") }) else {
            throw MotoGPError.noMotoGPCategory
        }
        motoGPCategoryIdCache = cat.id
        return cat.id
    }

    // MARK: Generic fetch

    private func fetch<T: Decodable & Sendable>(url: URL) async throws -> T {
        // Pulselive 某些端点(尤其 /session/{uuid}/classification)对默认 CFNetwork UA 返 403,
        // 加 Origin / Referer / 浏览器 UA 模拟 motogp.com 网页请求。
        var request = URLRequest(url: url)
        request.setValue("https://www.motogp.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.motogp.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MotoGPError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw MotoGPError.invalidResponse(-1, url)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MotoGPError.invalidResponse(http.statusCode, url)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MotoGPError.decoding(error)
        }
    }
}

// MARK: - DTOs (Pulselive wire format,严格 file private)

private struct SeasonDTO: Sendable, nonisolated Decodable {
    let id: String
    let year: Int
    let current: Bool
}

private struct CategoryDTO: Sendable, nonisolated Decodable {
    let id: String
    let name: String
    let legacy_id: Int?
}

private struct EventDTO: Sendable, nonisolated Decodable {
    let id: String
    let name: String
    let short_name: String?
    let sponsored_name: String?
    let date_start: String   // "2026-05-08"
    let date_end: String
    let status: String       // "NOT-STARTED" / "ONGOING" / "FINISHED"
    let test: Bool?
    let country: CountryDTO?
    let circuit: CircuitDTO?

    struct CountryDTO: Sendable, nonisolated Decodable {
        let iso: String?
        let name: String?
    }

    struct CircuitDTO: Sendable, nonisolated Decodable {
        let id: String
        let name: String?
        let place: String?
        let nation: String?
    }

    nonisolated func toDomain(round: Int, leagueId: String, seasonYear: Int) -> MotoGPRound? {
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        guard let start = dateOnly.date(from: date_start),
              let end = dateOnly.date(from: date_end) else { return nil }

        let circuit = Circuit(
            id: self.circuit?.id ?? "unknown",
            name: self.circuit?.name ?? "未知赛道",
            locality: self.circuit?.place ?? "",
            country: country?.name ?? self.circuit?.nation ?? ""
        )
        let st: EventStatus = {
            switch status {
            case "FINISHED":    return .finished
            case "ONGOING":     return .live
            case "POSTPONED":   return .postponed
            default:            return .upcoming
            }
        }()
        return MotoGPRound(
            id: id,
            leagueId: leagueId,
            season: String(seasonYear),
            round: round,
            name: name,
            shortName: short_name ?? "",
            circuit: circuit,
            dateStart: start,
            dateEnd: end,
            sessions: [],
            status: st
        )
    }
}

private struct SessionDTO: Sendable, nonisolated Decodable {
    let id: String
    let type: String         // "FP" / "PR" / "Q" / "SPR" / "WUP" / "RAC"
    let number: Int?
    let date: String         // "2026-05-08T10:45:00+00:00"

    nonisolated func toRef(eventId: String, formatter: ISO8601DateFormatter) -> MotoGPSessionRef? {
        guard let session = toDomain(eventId: eventId, formatter: formatter) else { return nil }
        return MotoGPSessionRef(rawId: id, session: session)
    }

    nonisolated func toDomain(eventId: String, formatter: ISO8601DateFormatter) -> Session? {
        guard let startTime = formatter.date(from: date) else { return nil }
        let kind: Session.Kind
        let label: String
        switch type {
        case "FP":
            kind = .practice
            label = "FP\(number ?? 1)"
        case "PR":
            kind = .practice
            label = "Practice"
        case "WUP":
            kind = .practice
            label = "Warm Up"
        case "Q":
            kind = .qualifying
            label = "Q\(number ?? 1)"
        case "SPR":
            kind = .sprint
            label = "Sprint"
        case "RAC":
            kind = .race
            label = "Race"
        default:
            // Pulselive 加新 type 时丢弃这条 session 而不是静默归 practice。
            // 老逻辑把未知 type 当 practice + label = type 让 UI 显示"SPRSHO 练习"误导用户。
            // 真碰上新 type 该 session 不显示,但其它 session 正常,日志可定位。
            MotoGPLogger.warning("MotoGP unknown session type=\(type) id=\(id)")
            return nil
        }
        return Session(
            id: "\(eventId)-\(id)",
            kind: kind,
            label: label,
            startTime: startTime
        )
    }
}

private enum MotoGPLogger {
    nonisolated static let log = Logger(subsystem: "com.tiebowen.Pole", category: "MotoGPClient")
    nonisolated static func warning(_ msg: String) { log.warning("\(msg, privacy: .public)") }
}

// MARK: - Standings DTOs

private struct StandingsResponse: Sendable, nonisolated Decodable {
    let classification: [ClassificationDTO]
}

fileprivate struct ClassificationDTO: Sendable, nonisolated Decodable {
    let position: Int
    let points: Double
    let race_wins: Int?
    let podiums: Int?
    let rider: RiderDTO
    let team: TeamDTO
    let constructor: ConstructorDTO

    struct RiderDTO: Sendable, nonisolated Decodable {
        let id: String
        let full_name: String
        let number: Int?
        let country: CountryDTO?

        struct CountryDTO: Sendable, nonisolated Decodable {
            let iso: String?
        }
    }

    struct TeamDTO: Sendable, nonisolated Decodable {
        let id: String
        let name: String
    }

    struct ConstructorDTO: Sendable, nonisolated Decodable {
        let id: String
        let name: String
    }

    nonisolated func toDomain() -> MotoGPRiderStanding? {
        let r = MotoGPRider(
            id: rider.id,
            fullName: rider.full_name,
            number: rider.number,
            countryISO: rider.country?.iso
        )
        return MotoGPRiderStanding(
            position: position,
            points: points,
            raceWins: race_wins ?? 0,
            podiums: podiums ?? 0,
            rider: r,
            team: MotoGPTeam(id: team.id, name: team.name),
            constructor: MotoGPConstructor(id: constructor.id, name: constructor.name)
        )
    }
}

// MARK: - Session Classification DTOs

private struct ClassificationResponse: Sendable, nonisolated Decodable {
    let classification: [ClassificationRowDTO]
}

fileprivate struct ClassificationRowDTO: Sendable, nonisolated Decodable {
    let position: Int?      // DNF / DSQ / Withdrawn 车手 final position 是 null
    let points: Double?
    let total_laps: Int?
    let time: String?
    let average_speed: Double?
    let status: String?
    let gap: GapDTO?
    let rider: ClassificationDTO.RiderDTO
    let team: ClassificationDTO.TeamDTO
    let constructor: ClassificationDTO.ConstructorDTO

    struct GapDTO: Sendable, nonisolated Decodable {
        let first: String?
        let lap: String?
    }

    nonisolated func toDomain() -> MotoGPRaceResult? {
        let r = MotoGPRider(
            id: rider.id,
            fullName: rider.full_name,
            number: rider.number,
            countryISO: rider.country?.iso
        )
        // gap.first = "0.000" 对应领先者,显示成 nil 让 UI 改显总时间
        let gapText: String? = {
            guard let g = gap?.first, g != "0.000", !g.isEmpty else { return nil }
            return "+" + g
        }()
        // DNF/DSQ 车手没 position——用 999 占位排到最后
        let pos = position ?? 999
        return MotoGPRaceResult(
            position: pos,
            rider: r,
            team: MotoGPTeam(id: team.id, name: team.name),
            constructor: MotoGPConstructor(id: constructor.id, name: constructor.name),
            totalLaps: total_laps,
            timeText: time,
            gapToFirstText: gapText,
            points: points ?? 0,
            averageSpeed: average_speed,
            status: status ?? ""
        )
    }
}
