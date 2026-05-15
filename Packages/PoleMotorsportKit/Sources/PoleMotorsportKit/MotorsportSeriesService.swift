import Foundation
import PoleDomain

/// 4 个赛车系列 client 的统一接口。让 AI tool / cross-series view 不再用 `switch series`。
///
/// 注意:`series` 必须 `nonisolated` 才能在 actor 外同步访问。
/// `anyRounds()` 返回 enum 包装的统一类型,实际 wire 格式差异在 client 内部抹平。
public protocol MotorsportSeriesService: Actor {
    nonisolated var series: MotorsportSeries { get }

    /// 当前赛季的所有比赛回合。F1 走 jolpica 的 "current",其余客户端各自走"当前年份"逻辑。
    func anyRounds() async throws -> [AnyMotorsportRound]
}

// MARK: - 4 个 client 的 conformance

extension JolpicaClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .f1 }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let races = try await fetchSeasonRaces()
        return races.map { AnyMotorsportRound.f1($0) }
    }
}

extension MotoGPClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .motogp }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let rounds = try await fetchSeasonRounds()
        return rounds.map { AnyMotorsportRound.motogp($0) }
    }
}

extension WSBKClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .wssp }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let rounds = try await fetchSeasonRounds()
        return rounds.map { AnyMotorsportRound.wssp($0) }
    }
}

extension FormulaEClient: MotorsportSeriesService {
    public nonisolated var series: MotorsportSeries { .fe }

    public func anyRounds() async throws -> [AnyMotorsportRound] {
        let rounds = try await fetchSeasonRounds()
        return rounds.map { AnyMotorsportRound.fe($0) }
    }
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

    /// 所有 series 的 service。用于 cross-series timeline 并行 fetch。
    public static var all: [any MotorsportSeriesService] {
        MotorsportSeries.allCases.map { service(for: $0) }
    }
}
