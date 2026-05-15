import Foundation
import PoleDomain

/// 4 个赛车系列 client 的统一接口。让 AI tool / cross-series view 不再用 `switch series`。
///
/// 注意:`series` 必须 `nonisolated` 才能在 actor 外同步访问。
/// `anyRounds()` 返回 enum 包装的统一类型,实际 wire 格式差异在 client 内部抹平。
///
/// JSON-string 形式的 standings / history / session results adapter:AI tool 直接把字符串
/// 回灌给 LLM,各 client 把自己 wire-format 的差异在 conformance 里抹掉。
public protocol MotorsportSeriesService: Actor {
    nonisolated var series: MotorsportSeries { get }

    /// 当前赛季的所有比赛回合。F1 走 jolpica 的 "current",其余客户端各自走"当前年份"逻辑。
    func anyRounds() async throws -> [AnyMotorsportRound]

    /// JSON 字符串形式的 standings(供 AI tool 直接 inject 给 LLM)。
    /// `kind` 取值:"driver" / "team" / "constructor"。`top` 限制前 N 行。
    /// 返回 `{"rows":[...]}` 结构,每行字段由各 series 自定。fetch 失败返 `{"error":"..."}`。
    func anyDriverStandingsJSON(kind: String, top: Int) async -> String

    /// JSON 字符串形式的 driver round-by-round 历史。`driverQuery` 可以是英文 / 中文 / code /
    /// 姓 / 含重音字符,client 内部走 fuzzy 匹配,没找到返 `{"error":"no driver match", ...}`。
    /// FE 暂不支持(API 不暴露逐站积分),返通用 error。
    func anyDriverHistoryJSON(driverQuery: String) async -> String

    /// JSON 字符串形式的 session results。`sessionKind` 取值:
    /// "race" / "sprint" / "qualifying" / "race_2"。
    /// 返回 `{"rows":[...]}`,fetch 失败返 `{"error":"fetch_failed", ...}`。
    func anySessionResultsJSON(round: Int, sessionKind: String) async -> String
}

// MARK: - 共用 helper

/// 把 [[String:Any]] 包成 `{"rows": [...]}` 字符串。
private func wrapRows(_ rows: [[String: Any]]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows])) ?? Data()
    return String(data: data, encoding: .utf8) ?? #"{"rows":[]}"#
}

/// `{"error":"fetch_failed","series":"...","message":"..."}`。
private func fetchFailedJSON(series: String, error: Error) -> String {
    let payload: [String: Any] = [
        "error": "fetch_failed",
        "series": series,
        "message": error.localizedDescription
    ]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? #"{"error":"fetch_failed"}"#
}

/// 通用 error JSON。
private func errorJSON(_ code: String, extras: [String: Any] = [:]) -> String {
    var payload: [String: Any] = ["error": code]
    for (k, v) in extras { payload[k] = v }
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? #"{"error":"\#(code)"}"#
}

/// normalize:去重音 + 小写。fuzzy 匹配各 series 共用。
private func _normalize(_ s: String) -> String {
    s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
}

// MARK: - F1(JolpicaClient)conformance

extension JolpicaClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .f1 }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let races = try await fetchSeasonRaces()
        return races.map { AnyMotorsportRound.f1($0) }
    }

    public func anyDriverStandingsJSON(kind: String, top: Int) async -> String {
        switch kind {
        case "driver":
            let s = (try? await fetchDriverStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.driver.fullName, series: .f1),
                 "points": st.points,
                 "wins": st.wins,
                 "team_id": st.constructorIds.first ?? ""]
            }
            return wrapRows(rows)
        case "team", "constructor":
            let s = (try? await fetchConstructorStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.constructor.name, series: .f1),
                 "points": st.points,
                 "wins": st.wins]
            }
            return wrapRows(rows)
        default:
            return errorJSON("unsupported_kind", extras: ["kind": kind])
        }
    }

    public func anyDriverHistoryJSON(driverQuery: String) async -> String {
        let standings = (try? await fetchDriverStandings()) ?? []
        guard let match = Self.fuzzyMatch(query: driverQuery, in: standings) else {
            return _noDriverMatch(query: driverQuery, candidates: standings.map {
                MotorsportNames.driverFullName(rawFullName: $0.driver.fullName, series: .f1)
            })
        }
        let rounds = (try? await fetchDriverSeasonResults(season: "current", driverId: match.driver.id)) ?? []
        let payload: [String: Any] = [
            "name": MotorsportNames.driverFullName(rawFullName: match.driver.fullName, series: .f1),
            "current_position": match.position,
            "current_points": match.points,
            "wins": match.wins,
            "rounds": rounds.map { r in
                ["round": r.round, "race": r.raceName, "points": r.points] as [String: Any]
            }
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func anySessionResultsJSON(round: Int, sessionKind: String) async -> String {
        let season = "current"
        switch sessionKind {
        case "race":
            do {
                let rows = try await fetchRaceResults(season: season, round: round)
                let payload: [[String: Any]] = rows.prefix(20).map { r in
                    ["position": r.position,
                     "name": MotorsportNames.driverFullName(rawFullName: r.driver.fullName, series: .f1),
                     "team": MotorsportNames.teamName(raw: r.constructor.name, series: .f1),
                     "time": r.timeText ?? r.status,
                     "points": r.points,
                     "status": r.status]
                }
                return wrapRows(payload)
            } catch {
                return fetchFailedJSON(series: "f1", error: error)
            }
        case "sprint":
            do {
                let rows = try await fetchSprintResults(season: season, round: round)
                let payload: [[String: Any]] = rows.prefix(20).map { r in
                    ["position": r.position,
                     "name": MotorsportNames.driverFullName(rawFullName: r.driver.fullName, series: .f1),
                     "team": MotorsportNames.teamName(raw: r.constructor.name, series: .f1),
                     "time": r.timeText ?? r.status,
                     "points": r.points]
                }
                return wrapRows(payload)
            } catch {
                return fetchFailedJSON(series: "f1", error: error)
            }
        case "qualifying":
            do {
                let rows = try await fetchQualifyingResults(season: season, round: round)
                let payload: [[String: Any]] = rows.prefix(20).map { r in
                    ["position": r.position,
                     "name": MotorsportNames.driverFullName(rawFullName: r.driver.fullName, series: .f1),
                     "team": MotorsportNames.teamName(raw: r.constructor.name, series: .f1),
                     "best_time": r.q3 ?? r.q2 ?? r.q1 ?? ""]
                }
                return wrapRows(payload)
            } catch {
                return fetchFailedJSON(series: "f1", error: error)
            }
        default:
            return errorJSON("unsupported_f1_session", extras: ["session": sessionKind])
        }
    }

    /// 模糊匹配:精确(normalize) → code → 部分 → 姓。
    fileprivate static func fuzzyMatch(query: String, in standings: [F1DriverStanding]) -> F1DriverStanding? {
        let q = _normalize(query)
        if let exact = standings.first(where: { _normalize($0.driver.fullName) == q }) { return exact }
        if let code = standings.first(where: { _normalize($0.driver.code ?? "") == q }) { return code }
        if let part = standings.first(where: { _driverMatches(query: query, candidate: $0.driver.fullName, series: .f1) }) { return part }
        if let last = standings.first(where: { _normalize($0.driver.familyName) == q }) { return last }
        return nil
    }
}

// MARK: - MotoGP(MotoGPClient)conformance

extension MotoGPClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .motogp }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let rounds = try await fetchSeasonRounds()
        return rounds.map { AnyMotorsportRound.motogp($0) }
    }

    public func anyDriverStandingsJSON(kind: String, top: Int) async -> String {
        switch kind {
        case "driver":
            let s = (try? await fetchRiderStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.rider.fullName, series: .motogp),
                 "points": st.points,
                 "wins": st.raceWins,
                 "team": MotorsportNames.teamName(raw: st.team.name, series: .motogp),
                 "constructor": MotorsportNames.teamName(raw: st.constructor.name, series: .motogp)]
            }
            return wrapRows(rows)
        case "team":
            let s = (try? await fetchTeamStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.team.name, series: .motogp),
                 "points": st.points,
                 "riders": st.riderNames.map { MotorsportNames.driverFullName(rawFullName: $0, series: .motogp) }]
            }
            return wrapRows(rows)
        case "constructor":
            let s = (try? await fetchConstructorStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.constructor.name, series: .motogp),
                 "points": st.points]
            }
            return wrapRows(rows)
        default:
            return errorJSON("unsupported_kind", extras: ["kind": kind])
        }
    }

    public func anyDriverHistoryJSON(driverQuery: String) async -> String {
        let standings = (try? await fetchRiderStandings()) ?? []
        guard let match = Self.fuzzyMatch(query: driverQuery, in: standings) else {
            return _noDriverMatch(query: driverQuery, candidates: standings.map {
                MotorsportNames.driverFullName(rawFullName: $0.rider.fullName, series: .motogp)
            })
        }
        let payload: [String: Any] = [
            "name": MotorsportNames.driverFullName(rawFullName: match.rider.fullName, series: .motogp),
            "current_position": match.position,
            "current_points": match.points,
            "wins": match.raceWins,
            "podiums": match.podiums,
            "team": MotorsportNames.teamName(raw: match.team.name, series: .motogp),
            "constructor": MotorsportNames.teamName(raw: match.constructor.name, series: .motogp),
            "note": "MotoGP API 不提供单 rider 逐站积分,仅当前赛季汇总"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func anySessionResultsJSON(round: Int, sessionKind: String) async -> String {
        let rounds: [MotoGPRound]
        do {
            rounds = try await fetchSeasonRounds()
        } catch {
            return fetchFailedJSON(series: "motogp", error: error)
        }
        guard let r = rounds.first(where: { $0.round == round }) else {
            return errorJSON("round_not_found", extras: ["round": round])
        }
        let refs: [MotoGPSessionRef]
        do {
            refs = try await fetchSessions(eventId: r.id)
        } catch {
            return fetchFailedJSON(series: "motogp", error: error)
        }
        let want: Session.Kind
        switch sessionKind {
        case "race":       want = .race
        case "sprint":     want = .sprint
        case "qualifying": want = .qualifying
        default:           return errorJSON("unsupported_motogp_session", extras: ["session": sessionKind])
        }
        let candidates = refs.filter { $0.session.kind == want }
            .sorted { $0.session.startTime < $1.session.startTime }
        guard let target = candidates.first else {
            return errorJSON("session_not_in_round", extras: ["round": round, "session": sessionKind])
        }
        let rows: [MotoGPRaceResult]
        do {
            rows = try await fetchSessionResults(sessionId: target.rawId)
        } catch {
            return fetchFailedJSON(series: "motogp", error: error)
        }
        let payload: [[String: Any]] = rows.prefix(20).map { row in
            ["position": row.position,
             "name": MotorsportNames.driverFullName(rawFullName: row.rider.fullName, series: .motogp),
             "team": MotorsportNames.teamName(raw: row.team.name, series: .motogp),
             "constructor": MotorsportNames.teamName(raw: row.constructor.name, series: .motogp),
             "time": row.timeText ?? row.gapToFirstText ?? row.status,
             "points": row.points]
        }
        return wrapRows(payload)
    }

    fileprivate static func fuzzyMatch(query: String, in standings: [MotoGPRiderStanding]) -> MotoGPRiderStanding? {
        let q = _normalize(query)
        if let exact = standings.first(where: { _normalize($0.rider.fullName) == q }) { return exact }
        if let part = standings.first(where: { _driverMatches(query: query, candidate: $0.rider.fullName, series: .motogp) }) { return part }
        return nil
    }
}

// MARK: - WSBK(WSBKClient)conformance

extension WSBKClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .wssp }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let rounds = try await fetchSeasonRounds()
        return rounds.map { AnyMotorsportRound.wssp($0) }
    }

    public func anyDriverStandingsJSON(kind: String, top: Int) async -> String {
        switch kind {
        case "driver":
            let s = (try? await fetchSSPRiderStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.rider.fullName, series: .wssp),
                 "points": st.points,
                 "country": st.rider.countryISO ?? ""]
            }
            return wrapRows(rows)
        case "team", "constructor":
            let s = (try? await fetchSSPBuilderStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.builder.name, series: .wssp),
                 "points": st.points,
                 "country": st.builder.countryISO ?? ""]
            }
            return wrapRows(rows)
        default:
            return errorJSON("unsupported_kind", extras: ["kind": kind])
        }
    }

    public func anyDriverHistoryJSON(driverQuery: String) async -> String {
        let standings = (try? await fetchSSPRiderStandings()) ?? []
        guard let match = Self.fuzzyMatch(query: driverQuery, in: standings) else {
            return _noDriverMatch(query: driverQuery, candidates: standings.map {
                MotorsportNames.driverFullName(rawFullName: $0.rider.fullName, series: .wssp)
            })
        }
        let lastName = match.rider.fullName.split(separator: " ").last.map(String.init) ?? match.rider.fullName
        let rounds = await fetchSSPRiderRoundPoints(riderLastName: lastName)
        let payload: [String: Any] = [
            "name": MotorsportNames.driverFullName(rawFullName: match.rider.fullName, series: .wssp),
            "current_position": match.position,
            "current_points": match.points,
            "wins": match.wins,
            "rounds": rounds.map { r in
                ["round": r.round,
                 "race": r.roundName,
                 "race1_points": r.race1Points,
                 "race2_points": r.race2Points,
                 "total": r.totalPoints] as [String: Any]
            }
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func anySessionResultsJSON(round: Int, sessionKind: String) async -> String {
        let rounds: [WSBKRound]
        do {
            rounds = try await fetchSeasonRounds()
        } catch {
            return fetchFailedJSON(series: "wsbk", error: error)
        }
        guard let r = rounds.first(where: { $0.round == round }) else {
            return errorJSON("round_not_found", extras: ["round": round])
        }
        let items: [WSSPSessionWithResults]
        do {
            items = try await fetchEventSessions(countryCode: r.countryCode, year: r.season)
        } catch {
            return fetchFailedJSON(series: "wsbk", error: error)
        }
        let candidates: [WSSPSessionWithResults]
        switch sessionKind {
        case "race":       candidates = items.filter { $0.session.label == "Race 1" }
        case "race_2":     candidates = items.filter { $0.session.label == "Race 2" }
        case "qualifying": candidates = items.filter { $0.session.kind == .qualifying }
        default:           return errorJSON("unsupported_wsbk_session", extras: ["session": sessionKind])
        }
        guard let target = candidates.first, let pdfURL = target.resultsPdfURL else {
            return errorJSON("session_not_available", extras: ["round": round, "session": sessionKind])
        }
        let rows: [WSSPRaceResult]
        do {
            rows = try await fetchSSPSessionResults(pdfURL: pdfURL)
        } catch {
            return fetchFailedJSON(series: "wsbk", error: error)
        }
        let payload: [[String: Any]] = rows.prefix(25).map { row in
            ["position": row.position,
             "name": MotorsportNames.driverFullName(rawFullName: row.riderName, series: .wssp),
             "team": MotorsportNames.teamName(raw: row.team, series: .wssp),
             "nat": row.nat,
             "time": row.timeText ?? row.gapText ?? ""]
        }
        return wrapRows(payload)
    }

    fileprivate static func fuzzyMatch(query: String, in standings: [WSSPRiderStanding]) -> WSSPRiderStanding? {
        let q = _normalize(query)
        if let exact = standings.first(where: { _normalize($0.rider.fullName) == q }) { return exact }
        if let part = standings.first(where: { _driverMatches(query: query, candidate: $0.rider.fullName, series: .wssp) }) { return part }
        return nil
    }
}

// MARK: - FormulaE(FormulaEClient)conformance

extension FormulaEClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .fe }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let rounds = try await fetchSeasonRounds()
        return rounds.map { AnyMotorsportRound.fe($0) }
    }

    public func anyDriverStandingsJSON(kind: String, top: Int) async -> String {
        switch kind {
        case "driver":
            let s = (try? await fetchDriverStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.driverFullName(rawFullName: st.driver.fullName, series: .fe),
                 "points": st.points,
                 "team": MotorsportNames.teamName(raw: st.teamName, series: .fe),
                 "country": st.driver.countryISO2 ?? ""]
            }
            return wrapRows(rows)
        case "team", "constructor":
            let s = (try? await fetchConstructorStandings()) ?? []
            let rows: [[String: Any]] = s.prefix(top).map { st in
                ["position": st.position,
                 "name": MotorsportNames.teamName(raw: st.team.name, series: .fe),
                 "points": st.points]
            }
            return wrapRows(rows)
        default:
            return errorJSON("unsupported_kind", extras: ["kind": kind])
        }
    }

    /// FE 暂未在 AI tool 暴露 driver history(API 不提供逐站积分)。返通用 error 占位。
    public func anyDriverHistoryJSON(driverQuery: String) async -> String {
        return errorJSON("not_supported", extras: ["series": "fe", "reason": "FE driver history not exposed"])
    }

    /// FE 暂未在 AI tool 暴露 session results(目前 tool 只支持 f1/motogp/wsbk)。
    public func anySessionResultsJSON(round: Int, sessionKind: String) async -> String {
        return errorJSON("not_supported", extras: ["series": "fe", "reason": "FE session results not exposed"])
    }
}

// MARK: - Fuzzy 匹配的共享工具

/// 单 candidate 命中查询:normalize 字面 / 中文反向 / 部分包含。
fileprivate func _driverMatches(query: String, candidate: String, series: MotorsportSeries) -> Bool {
    let q = _normalize(query)
    let c = _normalize(candidate)
    if c == q || c.contains(q) || q.contains(c) { return true }
    let zhFull = MotorsportNames.driverFullName(rawFullName: candidate, series: series)
    let zhShort = MotorsportNames.driverShortName(rawFullName: candidate, series: series)
    if zhFull != candidate, zhFull.contains(query) { return true }
    if zhShort != candidate, zhShort.contains(query) { return true }
    return false
}

/// 找不到 driver 时返结构化错误 + 前 15 个候选(给 LLM 反馈)。
fileprivate func _noDriverMatch(query: String, candidates: [String]) -> String {
    let payload: [String: Any] = [
        "error": "no driver match",
        "query": query,
        "candidates": Array(candidates.prefix(15))
    ]
    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}

// MARK: - Registry

/// 系列 → service 的注册表。AI tool / cross-series view 通过 `MotorsportRegistry.service(for:)`
/// 拿到 `any MotorsportSeriesService`,不再 switch 4 个 client 散点。
public enum MotorsportRegistry {
    public static func service(for series: MotorsportSeries) -> any MotorsportSeriesService {
        switch series {
        case .f1:     return JolpicaClient.shared
        case .motogp: return MotoGPClient.shared
        case .wssp:   return WSBKClient.shared
        case .fe:     return FormulaEClient.shared
        }
    }

    /// 通过 string id("f1"/"motogp"/"wsbk"/"fe")拿 service。AI tool 参数是 string。
    /// 注意 "wsbk" → `.wssp`(WorldSBK 数据源在 app 内 series enum 是 `.wssp`,但 tool 参数沿用 wsbk)。
    public static func service(forId id: String) -> (any MotorsportSeriesService)? {
        switch id {
        case "f1":     return JolpicaClient.shared
        case "motogp": return MotoGPClient.shared
        case "wsbk":   return WSBKClient.shared
        case "fe":     return FormulaEClient.shared
        default:       return nil
        }
    }

    /// 所有 series 的 service。用于 cross-series timeline 并行 fetch。
    public static var all: [any MotorsportSeriesService] {
        MotorsportSeries.allCases.map { service(for: $0) }
    }
}
