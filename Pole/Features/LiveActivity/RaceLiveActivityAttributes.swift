import Foundation
import ActivityKit

/// 赛事 Live Activity attributes — 对应锁屏卡片 + 灵动岛(iPhone 14 Pro+)。
///
/// **重要数据约束**: jolpica/Pulselive 没有真正实时圈速,所以 `ContentState` 只能呈现:
/// - 当前正在跑的 session 名称(从赛历估算)
/// - 已经过去的时间 / 总时长(用于进度条)
/// - 上一个完成的 session 的 top 3(SessionResult fetch 后 update)
///
/// 不是 F1 TV 那种秒级实时,但对"周末看到比赛进行到哪"是够用的体验。
///
/// **并发说明**: `nonisolated` 显式跳过项目默认 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。
/// ActivityKit 的 `Activity.update()`/`end()` 是 @concurrent,如果 Attributes/State 是 MainActor
/// 隔离的,跨 actor 传递会触发 Swift 6 数据竞争警告。所有字段都是 Sendable 值类型,无 UI 状态。
public nonisolated struct RaceLiveActivityAttributes: ActivityAttributes {

    public typealias ContentState = State

    /// 静态属性 — Live Activity 启动后不变。
    public let raceId: String              // RaceAppEntity.id 一致 ("f1:2025-1")
    public let seriesRaw: String           // "f1" / "motogp" / "wssp" / "fe"
    public let raceTitle: String           // "巴塞罗那大奖赛"
    public let raceSubtitle: String        // "第 7 轮 · Barcelona, Spain"
    public let weekendStart: Date
    public let weekendEnd: Date

    public init(raceId: String, seriesRaw: String, raceTitle: String, raceSubtitle: String, weekendStart: Date, weekendEnd: Date) {
        self.raceId = raceId
        self.seriesRaw = seriesRaw
        self.raceTitle = raceTitle
        self.raceSubtitle = raceSubtitle
        self.weekendStart = weekendStart
        self.weekendEnd = weekendEnd
    }

    /// 动态状态 — 周期 update 这里。
    public nonisolated struct State: Codable, Hashable, Sendable {
        /// 赛事大状态。
        public let phase: Phase
        /// 当前 session 标签(估算或已知,如 "FP1" / "Q3" / "Race")。
        public let currentSessionLabel: String?
        /// 当前 session 起止 — 灵动岛进度条用。
        public let currentSessionStart: Date?
        public let currentSessionEnd: Date?
        /// 上一 session 完成后的 top 3 名字(已知则填,流式更新)。
        public let lastSessionTop3: [String]
        /// 上一 session 名称(top3 的 session)。
        public let lastSessionLabel: String?

        public init(
            phase: Phase,
            currentSessionLabel: String? = nil,
            currentSessionStart: Date? = nil,
            currentSessionEnd: Date? = nil,
            lastSessionTop3: [String] = [],
            lastSessionLabel: String? = nil
        ) {
            self.phase = phase
            self.currentSessionLabel = currentSessionLabel
            self.currentSessionStart = currentSessionStart
            self.currentSessionEnd = currentSessionEnd
            self.lastSessionTop3 = lastSessionTop3
            self.lastSessionLabel = lastSessionLabel
        }

        public enum Phase: String, Codable, Hashable, Sendable {
            case beforeWeekend       // 启动了但还没到 weekendStart(可能提前 30min 启动了)
            case inSession           // 某个 session 正在进行
            case betweenSessions     // 周末内但当前没 session(intermission)
            case finished            // 周末结束
        }
    }
}
