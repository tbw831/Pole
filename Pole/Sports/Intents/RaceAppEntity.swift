import Foundation
import AppIntents
import PoleDomain
import PoleMotorsportKit

/// 跨 4 系列的赛事 AppEntity — 让 Siri / Spotlight / Shortcuts 都能引用某场赛。
///
/// 设计:
/// - `id` = "<series>:<raceId>" (例 "f1:2025-1"),作 stable identifier
/// - 单一 entity 类型代替 4 个 (F1RaceEntity / MotoGPRoundEntity / ...) — Siri 介绍简单
/// - 用户问"维斯塔潘下一场"时 LLM 不需要先决定哪个 series,直接给 entity
///
/// `query` 实现 EntityStringQuery 让 Siri 通过文字模糊匹配("巴塞罗那"),Spotlight 直接 indexed。
public struct RaceAppEntity: AppEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "赛事")
    }

    public static let defaultQuery = RaceEntityQuery()

    public var id: String                          // "f1:2025-1" / "motogp:abc-uuid"
    public var seriesRaw: String                   // "f1" / "motogp" / "wssp" / "fe"
    public var displayName: String                 // "巴塞罗那大奖赛" / "Spanish Grand Prix"
    public var subtitle: String                    // "第 7 轮 · Barcelona, Spain"
    public var startDate: Date

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(subtitle)"
        )
    }
}

// MARK: - 查询(让 Siri "巴塞罗那"模糊查赛事)

public struct RaceEntityQuery: EntityStringQuery {
    public init() {}

    /// `entities(for:)` — 给 ID 反查(Spotlight 点击恢复 entity 时用)。
    public func entities(for identifiers: [RaceAppEntity.ID]) async throws -> [RaceAppEntity] {
        // 全 4 系列拉一遍,匹配 id;数据已被 SeasonCache 缓存所以不重。
        let all = await Self.allCachedEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    /// 字符串模糊查询(Siri "查 X 大奖赛")。
    public func entities(matching string: String) async throws -> [RaceAppEntity] {
        let all = await Self.allCachedEntities()
        let q = string.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.subtitle.lowercased().contains(q) ||
            $0.id.lowercased().contains(q)
        }
    }

    /// Siri / Shortcuts 的"建议列表"(默认显示前 N 个)。
    public func suggestedEntities() async throws -> [RaceAppEntity] {
        let all = await Self.allCachedEntities()
        let now = Date()
        // 优先 upcoming,其次最近 finished
        return all
            .sorted { abs($0.startDate.timeIntervalSince(now)) < abs($1.startDate.timeIntervalSince(now)) }
            .prefix(10)
            .map { $0 }
    }

    /// 拉 4 系列已缓存赛事 → 转 RaceAppEntity。已经接 SeasonCache,不重复请求。
    static func allCachedEntities() async -> [RaceAppEntity] {
        async let f1 = (try? await JolpicaClient.shared.fetchSeasonRaces()) ?? []
        async let motogp = (try? await MotoGPClient.shared.fetchSeasonRounds()) ?? []
        async let wsbk = (try? await WSBKClient.shared.fetchSeasonRounds()) ?? []
        async let fe = (try? await FormulaEClient.shared.fetchSeasonRounds()) ?? []
        let (f1List, motogpList, wsbkList, feList) = await (f1, motogp, wsbk, fe)

        var out: [RaceAppEntity] = []
        for r in f1List {
            out.append(RaceAppEntity(
                id: "f1:\(r.id)",
                seriesRaw: "f1",
                displayName: r.headline,
                subtitle: r.subheadline,
                startDate: r.weekendStart
            ))
        }
        for r in motogpList {
            out.append(RaceAppEntity(
                id: "motogp:\(r.id)",
                seriesRaw: "motogp",
                displayName: r.headline,
                subtitle: r.subheadline,
                startDate: r.weekendStart
            ))
        }
        for r in wsbkList {
            out.append(RaceAppEntity(
                id: "wssp:\(r.id)",
                seriesRaw: "wssp",
                displayName: r.headline,
                subtitle: r.subheadline,
                startDate: r.weekendStart
            ))
        }
        for r in feList {
            out.append(RaceAppEntity(
                id: "fe:\(r.id)",
                seriesRaw: "fe",
                displayName: r.headline,
                subtitle: r.subheadline,
                startDate: r.weekendStart
            ))
        }
        return out
    }
}

// MARK: - Series enum (Siri 参数用)

/// Siri 输入参数 series 枚举 — 跟 MotorsportSeries 对齐但加 .all 兜底。
public enum SeriesParameter: String, AppEnum {
    case f1, motogp, wsbk, fe, all

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "赛车系列")
    }

    public static let caseDisplayRepresentations: [SeriesParameter: DisplayRepresentation] = [
        .f1:     DisplayRepresentation(title: "F1"),
        .motogp: DisplayRepresentation(title: "MotoGP"),
        .wsbk:   DisplayRepresentation(title: "WorldSBK"),
        .fe:     DisplayRepresentation(title: "Formula E"),
        .all:    DisplayRepresentation(title: "全部系列")
    ]
}
