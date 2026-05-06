import Foundation

/// 通用 TTL 缓存 — 按 key 存数据 + 过期时间,过期重新 fetch。
/// 4 个 motorsport client(F1/MotoGP/WSBK/FE)共用,避免 MotorsportTimelineView + RaceListView + AI agent
/// 各拉一份相同数据。
///
/// 用法(client actor 内):
/// ```swift
/// public actor JolpicaClient {
///     private var racesCache = SeasonCache<[F1Race]>(ttl: 3600)   // 1h
///
///     public func fetchSeasonRaces() async throws -> [F1Race] {
///         try await racesCache.fetchOr(key: "current") {
///             /// 真实网络调用
///             try await self._fetchSeasonRacesFromNetwork()
///         }
///     }
/// }
/// ```
///
/// 故意不加 cancellation / task coalescing:
/// - 同 actor 内串行调用,两个并发 fetch 概率低
/// - 真碰上重复 fetch 浪费一次请求,可以接受
///
/// `nonisolated` 让该类型脱离模块默认的 main-actor 隔离,可被 actor client 直接持有/调用。
public nonisolated struct SeasonCache<Value: Sendable>: Sendable {
    private final class Box: @unchecked Sendable {
        var entries: [String: (Date, Value)] = [:]
    }

    private let ttl: TimeInterval
    private let box: Box

    public init(ttl: TimeInterval) {
        self.ttl = ttl
        self.box = Box()
    }

    /// 命中且未过期 → 返 cache;过期 / 未命中 → 跑 `loader`,成功后写入。
    public func fetchOr(key: String, _ loader: () async throws -> Value) async throws -> Value {
        if let (timestamp, value) = box.entries[key],
           Date().timeIntervalSince(timestamp) < ttl {
            return value
        }
        let value = try await loader()
        box.entries[key] = (Date(), value)
        return value
    }

    /// 强制刷新(下拉手势用) — 清 key 的 cache 然后重新 load。
    public func refresh(key: String, _ loader: () async throws -> Value) async throws -> Value {
        box.entries.removeValue(forKey: key)
        return try await fetchOr(key: key, loader)
    }

    /// 清所有 entry(切语言 / 切赛季时调)。
    public func invalidate() {
        box.entries.removeAll()
    }
}
