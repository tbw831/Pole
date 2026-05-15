import Foundation
import ActivityKit

/// Live Activity 启停 + 周期 update 协调器。
///
/// 用法:
/// - `start(for: race)` — 调用方在赛事 weekendStart 前 30min 触发
/// - `stopAll()` — 用户点 Live Activity"停止"按钮 / 周末结束 / 主动取消时调
///
/// **更新策略(2026-05 重构)**:
/// 老版本用 `Timer.scheduledTimer(60s)` 全空 tick(8h activity 周期 480 次唤主线程),
/// 大部分 tick 状态没变化只是写同样内容。改为:
/// - `Activity.activityUpdates` async sequence 监听系统驱动的状态变化(用户 dismiss / staleDate / push)
/// - 自身用 `Task.sleep(until:)` 在已知边界(weekendEnd、估算 sessionEnd)单点唤醒一次推送
/// - 空闲零 tick,显著减电耗
///
/// **Live Activity 限制**:
/// - 单个 activity 最长 8 小时(staleDate);F1 周末跨 3 天,只在每个 session 半小时窗口启动一个
@MainActor
public final class RaceLiveActivityCoordinator {
    public static let shared = RaceLiveActivityCoordinator()

    /// 监听 ActivityKit 系统事件的 task(activity 启动时建,stopAll / 全部 end 时取消)。
    private var watchTask: Task<Void, Never>?
    /// phase 边界唤醒 task(activity 启动时建,update 后重排,activity 结束时 cancel)。
    private var boundaryTask: Task<Void, Never>?

    private init() {}

    // MARK: 启动

    /// 启动 Live Activity 跟看一场赛事。
    /// 赛事必须在 8 小时内开始或正在进行,否则 ActivityKit 会拒绝。
    @discardableResult
    public func start(
        raceId: String,
        seriesRaw: String,
        raceTitle: String,
        raceSubtitle: String,
        weekendStart: Date,
        weekendEnd: Date,
        initialState: RaceLiveActivityAttributes.ContentState
    ) -> Activity<RaceLiveActivityAttributes>? {
        // 检查权限
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else {
            print("[LiveActivity] 用户在系统设置关闭了 Live Activities,跳过")
            return nil
        }

        let attributes = RaceLiveActivityAttributes(
            raceId: raceId,
            seriesRaw: seriesRaw,
            raceTitle: raceTitle,
            raceSubtitle: raceSubtitle,
            weekendStart: weekendStart,
            weekendEnd: weekendEnd
        )

        // staleDate = weekendEnd 或 8h 后(取较近),system 自动 end
        let staleDate = min(weekendEnd, Date().addingTimeInterval(8 * 3600))
        let content = ActivityContent(state: initialState, staleDate: staleDate)

        do {
            let activity = try Activity<RaceLiveActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil   // 不走 APNs(纯本地 update),要真正实时推得加自有后端
            )
            startWatchingIfNeeded()
            scheduleNextBoundary()
            return activity
        } catch {
            print("[LiveActivity] 启动失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: 系统事件监听 + 边界唤醒

    /// 启动 `Activity.activityUpdates` 监听器(只起一次,所有 activity 共用)。
    /// 系统在 user dismiss / staleDate 触达 / push 抵达时推一个新事件,这样我们不再需要 60s 轮询。
    private func startWatchingIfNeeded() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            for await _ in Activity<RaceLiveActivityAttributes>.activityUpdates {
                guard let self else { return }
                await self.handleActivityListChange()
            }
        }
    }

    /// activity 列表变化(添加/移除)时调整边界唤醒。
    private func handleActivityListChange() async {
        if Activity<RaceLiveActivityAttributes>.activities.isEmpty {
            boundaryTask?.cancel()
            boundaryTask = nil
            watchTask?.cancel()
            watchTask = nil
        } else {
            scheduleNextBoundary()
        }
    }

    /// 找到所有 activity 中"最近的下一个 phase 边界"(weekendStart / weekendEnd),
    /// 在该时点单点唤醒,推一次 update;然后递归排下一次。空闲期间零 tick。
    private func scheduleNextBoundary() {
        boundaryTask?.cancel()
        let activities = Activity<RaceLiveActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        let now = Date()

        // 收集所有未来边界点(weekendStart 用于 .beforeWeekend → .inSession,weekendEnd 用于 → .finished)
        var nextBoundary: Date?
        for activity in activities {
            let attrs = activity.attributes
            for boundary in [attrs.weekendStart, attrs.weekendEnd] where boundary > now {
                if nextBoundary == nil || boundary < nextBoundary! {
                    nextBoundary = boundary
                }
            }
        }
        guard let target = nextBoundary else { return }

        boundaryTask = Task { [weak self] in
            let nanos = UInt64(max(0, target.timeIntervalSinceNow) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            await self?.tickAll()
            // 推完一次后排下一个边界(scheduleNextBoundary 是 sync MainActor,closure 已在 MainActor)
            self?.scheduleNextBoundary()
        }
    }

    private func tickAll() async {
        for activity in Activity<RaceLiveActivityAttributes>.activities {
            await Self.tickOne(activity)
        }
    }

    /// `@concurrent` + `nonisolated static` 显式跑在 cooperative thread pool 而不是 MainActor —
    /// Activity 的 `end()`/`update()` 是 @concurrent,跟着调用方走 isolation 会触发"task-isolated
    /// → @concurrent"数据竞争警告。Activity 本身 Sendable,放 @concurrent 上下文直接调安全。
    @concurrent
    private nonisolated static func tickOne(_ activity: Activity<RaceLiveActivityAttributes>) async {
        let attrs = activity.attributes
        let now = Date()

        // 周末结束 → end activity
        if now > attrs.weekendEnd {
            await activity.end(nil, dismissalPolicy: .immediate)
            return
        }

        // 推算当前 phase
        let phase: RaceLiveActivityAttributes.ContentState.Phase
        if now < attrs.weekendStart {
            phase = .beforeWeekend
        } else if now > attrs.weekendEnd {
            phase = .finished
        } else {
            // 周末内 — 假设当前在 session(简化:weekend 内永远 inSession,
            // 真正按 session 区间判断需要 fetch sessions list,先用粗粒度)
            phase = .inSession
        }

        // 估算当前 session 标签 — 这里只能基于赛事时段做粗略推断,
        // 周五:Practice,周六:Quali / Sprint,周日:Race。jolpica/Pulselive 不给实时圈速所以无法精确。
        let weekday = Calendar.current.component(.weekday, from: now)
        let sessionLabel: String
        switch weekday {
        case 6: sessionLabel = "Practice"   // Friday
        case 7: sessionLabel = "Qualifying" // Saturday
        case 1: sessionLabel = "Race"       // Sunday
        default: sessionLabel = "Session"
        }

        let newState = RaceLiveActivityAttributes.ContentState(
            phase: phase,
            currentSessionLabel: phase == .inSession ? sessionLabel : nil,
            currentSessionStart: attrs.weekendStart,
            currentSessionEnd: attrs.weekendEnd,
            lastSessionTop3: activity.content.state.lastSessionTop3,    // 保留(由其他路径填,如 fetchSessionResults)
            lastSessionLabel: activity.content.state.lastSessionLabel
        )

        let staleDate = min(attrs.weekendEnd, now.addingTimeInterval(2 * 3600))
        await activity.update(ActivityContent(state: newState, staleDate: staleDate))
    }

    // MARK: 停止

    /// 关掉所有 Live Activity(用户从灵动岛点"停止"或主 app 关 toggle 时)。
    public func stopAll() async {
        for activity in Activity<RaceLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        boundaryTask?.cancel()
        boundaryTask = nil
        watchTask?.cancel()
        watchTask = nil
    }

    /// 关单个赛事的 activity。
    public func stop(raceId: String) async {
        for activity in Activity<RaceLiveActivityAttributes>.activities {
            if activity.attributes.raceId == raceId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: 便捷启动入口(给 RaceDetailView "开始跟看"按钮 / Siri Intent 用)

    /// 用 RaceAppEntity 直接启动 — 自动填初始 state。
    public func start(from race: RaceAppEntity) -> Activity<RaceLiveActivityAttributes>? {
        let now = Date()
        let phase: RaceLiveActivityAttributes.ContentState.Phase =
            now < race.startDate ? .beforeWeekend : .inSession
        let initialState = RaceLiveActivityAttributes.ContentState(
            phase: phase,
            currentSessionLabel: phase == .inSession ? "Race" : nil,
            currentSessionStart: race.startDate,
            currentSessionEnd: race.startDate.addingTimeInterval(3 * 3600),
            lastSessionTop3: [],
            lastSessionLabel: nil
        )
        return start(
            raceId: race.id,
            seriesRaw: race.seriesRaw,
            raceTitle: race.displayName,
            raceSubtitle: race.subtitle,
            weekendStart: race.startDate,
            weekendEnd: race.startDate.addingTimeInterval(3 * 3600),
            initialState: initialState
        )
    }
}
