import Foundation

/// 通用 TTL 缓存 — 按 key 存数据 + 过期时间,过期重新 fetch。
/// 4 个 motorsport client(F1/MotoGP/WSBK/FE)共用,避免 MotorsportTimelineView + RaceListView + AI agent
/// 各拉一份相同数据。
///
/// 用法(client actor 内):
/// ```swift
/// public actor JolpicaClient {
///     private let racesCache = SeasonCache<[F1Race]>(ttl: 3600)   // 1h
///
///     public func fetchSeasonRaces() async throws -> [F1Race] {
///         try await racesCache.fetchOr(key: "current") {
///             try await self._fetchSeasonRacesFromNetwork()
///         }
///     }
/// }
/// ```
///
/// 自身是 actor —— 并发 fetchOr 调用安全串行,不会有 data race。
/// 加了 in-flight task coalescing:同 key 并发 miss 共享一次 loader 调用。
public actor SeasonCache<Value: Sendable> {
    private let ttl: TimeInterval
    private var entries: [String: (timestamp: Date, value: Value)] = [:]
    private var inflight: [String: Task<Value, Error>] = [:]

    public init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    /// 命中且未过期 → 返 cache;过期 / 未命中 → 跑 `loader`,成功后写入。
    /// 同 key 并发 miss 合并到一次 loader call(避免 4 client × N caller 的重复请求)。
    public func fetchOr(key: String, _ loader: @Sendable @escaping () async throws -> Value) async throws -> Value {
        // 缓存命中
        if let entry = entries[key], Date().timeIntervalSince(entry.timestamp) < ttl {
            return entry.value
        }
        // 同 key 已有 in-flight task → 复用
        if let task = inflight[key] {
            return try await task.value
        }
        // 开新 task,登记 in-flight,完成后写 entries 并清 inflight
        let task = Task { try await loader() }
        inflight[key] = task
        defer { inflight.removeValue(forKey: key) }
        let value = try await task.value
        entries[key] = (Date(), value)
        return value
    }

    /// 强制刷新(下拉手势用) — 清 key 的 cache 然后重新 load。
    public func refresh(key: String, _ loader: @Sendable @escaping () async throws -> Value) async throws -> Value {
        entries.removeValue(forKey: key)
        return try await fetchOr(key: key, loader)
    }

    /// 清所有 entry(切语言 / 切赛季时调)。
    public func invalidate() {
        entries.removeAll()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
    }
}
