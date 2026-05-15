import Foundation
import SwiftData
import PoleSharedKit
import PoleDomain
import PoleMotorsportKit

/// 主 app → widget snapshot 的桥。每次 app 启动 / 数据变化时调 refresh()。
/// - 跨四系列查"最早未结束"的 race(用 weekendStart 排序)。
/// - 拉一份关注车手的当前积分(只取已关注的 athlete 类型,最多 5 条)。
/// - 容错:任一 client 失败时该系列贡献为空,不影响其它系列。
@MainActor
public enum WidgetSnapshotBuilder {
    private static let f1 = JolpicaClient()
    private static let motogp = MotoGPClient()
    private static let wsbk = WSBKClient()
    private static let fe = FormulaEClient()

    /// scenePhase active 重触发 / 用户切前台连发的防抖窗口。10 分钟内不重复刷。
    /// 数据变更场景(FollowStore.toggle / NotificationScheduler.reschedule)用 `force: true` 旁路。
    private static let refreshDebounce: TimeInterval = 600
    private static var lastRefreshAt: Date?

    /// 当前在飞的 refresh Task 句柄。新 refresh 会先 cancel 旧的,
    /// 避免 FollowStore.onChange 等高频触发场景下多个 build() 并发写 WidgetSnapshotStore。
    private static var refreshTask: Task<Void, Never>?

    /// 异步生成并写入 snapshot。
    /// - Parameter force: true 时跳过防抖窗口,确保数据变更立即反映。
    public static func refresh(force: Bool = false) {
        let now = Date()
        if !force, let last = lastRefreshAt, now.timeIntervalSince(last) < refreshDebounce {
            return
        }
        lastRefreshAt = now
        refreshTask?.cancel()
        refreshTask = Task {
            let snapshot = await build()
            WidgetSnapshotStore.write(snapshot)
        }
    }

    /// 同步入口(供 testing / 手动触发)。返回构建结果但不写入。
    public static func build() async -> WidgetSnapshot {
        async let f1Rounds: [F1Race]       = (try? await f1.fetchSeasonRaces()) ?? []
        async let motoGPRounds: [MotoGPRound] = (try? await motogp.fetchSeasonRounds()) ?? []
        async let wsbkRounds: [WSBKRound]  = (try? await wsbk.fetchSeasonRounds()) ?? []
        async let feRounds: [FERound]      = (try? await fe.fetchSeasonRounds()) ?? []

        let allRounds: [AnyMotorsportRound] =
            (await f1Rounds).map { .f1($0) } +
            (await motoGPRounds).map { .motogp($0) } +
            (await wsbkRounds).map { .wssp($0) } +
            (await feRounds).map { .fe($0) }

        let now = Date()
        let next = allRounds
            .filter { $0.weekendEnd > now }
            .min(by: { $0.weekendStart < $1.weekendStart })

        let nextRaceDTO = next.map { Self.toDTO($0, now: now) }
        let followed = await Self.collectFollowedDrivers()

        return WidgetSnapshot(
            generatedAt: now,
            nextRace: nextRaceDTO,
            followedDrivers: followed
        )
    }

    // MARK: - Domain → DTO

    private static func toDTO(_ round: AnyMotorsportRound, now: Date) -> WidgetSnapshot.NextRace {
        let sessions = Self.sessions(of: round)
        let mainRace = sessions.last(where: { $0.kindRaw == "race" }) ?? sessions.last
        let raceStart = mainRace?.start ?? round.weekendStart

        let circuitName: String
        let countryCode: String?
        switch round {
        case .f1(let r):
            circuitName = r.circuit.name
            countryCode = nil  // F1 wire 没直接 ISO code,暂略
        case .motogp(let r):
            circuitName = r.circuit.name
            countryCode = r.shortName  // MotoGP 用 "FRA" / "ITA" 等三字码
        case .wssp(let r):
            circuitName = r.circuit.name
            countryCode = r.countryCode  // "AUS" / "POR"
        case .fe(let r):
            circuitName = r.circuit.name
            countryCode = r.circuit.country  // FE circuit.country 就是 ISO2 ("DE")
        case .feWeekend(let w):
            circuitName = w.rounds.first!.circuit.name
            countryCode = w.rounds.first!.circuit.country
        }

        return WidgetSnapshot.NextRace(
            seriesRaw: round.series.rawValue,
            roundName: round.headline,
            circuitName: circuitName,
            countryCode: countryCode,
            weekendStart: round.weekendStart,
            weekendEnd: round.weekendEnd,
            raceStart: raceStart,
            sessions: sessions,
            statusRaw: round.currentStatus.rawValue
        )
    }

    private static func sessions(of round: AnyMotorsportRound) -> [WidgetSnapshot.SessionInfo] {
        let raw: [Session]
        switch round {
        case .f1(let r):     raw = r.sessions
        case .motogp(let r): raw = r.sessions
        case .wssp(let r):   raw = r.sessions
        case .fe(let r):          raw = r.sessions
        case .feWeekend(let w):   raw = w.rounds.first!.sessions
        }
        return raw.map {
            WidgetSnapshot.SessionInfo(
                label: $0.label,
                kindRaw: $0.kind.rawValue,
                start: $0.startTime
            )
        }
    }

    // MARK: - Followed drivers

    /// 读 SwiftData 中的关注 athlete,按 series 分组,**每系列只拉一次 standings**(以前是每人独立拉,
    /// 关注同系列 N 人 = N 次重复 fetch)。最多 5 条结果。
    /// 失败/空时返空数组,任一系列 fetch 失败不影响其它。
    private static func collectFollowedDrivers() async -> [WidgetSnapshot.FollowedDriver] {
        let context = PoleAppContext.shared.requireModelContainer().mainContext
        let descriptor = FetchDescriptor<FollowedItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return [] }

        struct Entry {
            let series: MotorsportSeries
            let refId: String
            let name: String
        }
        let athletes: [Entry] = items
            .compactMap { item in
                guard let target = item.target,
                      case .athlete(let id, _, let seriesRaw) = target,
                      let series = MotorsportSeries(rawValue: seriesRaw) else { return nil }
                return Entry(series: series, refId: id, name: item.displayName)
            }
        let top = Array(athletes.prefix(5))
        if top.isEmpty { return [] }

        // 按 series 分组 + 并行拉对应 series 的 standings(每系列至多 1 次,有 SeasonCache 进一步去重)
        let groupedSeries: Set<MotorsportSeries> = Set(top.map(\.series))
        async let f1Standings: [F1DriverStanding]?         = groupedSeries.contains(.f1)     ? (try? await f1.fetchDriverStandings())      : nil
        async let motogpStandings: [MotoGPRiderStanding]?   = groupedSeries.contains(.motogp) ? (try? await motogp.fetchRiderStandings())   : nil
        async let wsspStandings: [WSSPRiderStanding]?       = groupedSeries.contains(.wssp)   ? (try? await wsbk.fetchSSPRiderStandings()) : nil
        async let feStandings: [FEDriverStanding]?          = groupedSeries.contains(.fe)     ? (try? await fe.fetchDriverStandings())     : nil

        let f1S    = (await f1Standings)    ?? []
        let mgpS   = (await motogpStandings) ?? []
        let wsspS  = (await wsspStandings)   ?? []
        let feS    = (await feStandings)     ?? []

        // 保留原 athletes 顺序(用户加关注的倒序)。
        return top.map { entry in
            switch entry.series {
            case .f1:
                let m = f1S.first(where: { $0.driver.id == entry.refId || $0.driver.fullName == entry.name })
                return WidgetSnapshot.FollowedDriver(seriesRaw: "f1", name: entry.name,
                                                     rank: m?.position, points: m?.points,
                                                     teamName: nil)
            case .motogp:
                let m = mgpS.first(where: { $0.rider.id == entry.refId || $0.rider.fullName == entry.name })
                return WidgetSnapshot.FollowedDriver(seriesRaw: "motogp", name: entry.name,
                                                     rank: m?.position, points: m?.points,
                                                     teamName: m?.team.name)
            case .wssp:
                let m = wsspS.first(where: { $0.rider.id == entry.refId || $0.rider.fullName == entry.name })
                return WidgetSnapshot.FollowedDriver(seriesRaw: "wssp", name: entry.name,
                                                     rank: m?.position, points: m?.points,
                                                     teamName: nil)
            case .fe:
                let m = feS.first(where: { $0.driver.id == entry.refId || $0.driver.fullName == entry.name })
                return WidgetSnapshot.FollowedDriver(seriesRaw: "fe", name: entry.name,
                                                     rank: m?.position, points: m?.points,
                                                     teamName: m?.teamName)
            }
        }
    }
}
