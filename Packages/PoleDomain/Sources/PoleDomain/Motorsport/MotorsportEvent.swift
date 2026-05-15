import Foundation

/// 赛车赛事抽象——一站大奖赛/一个比赛周末。
/// F1Round、MotoGPRound、WSBKRound 都实现此协议，让"赛车周末时间线"页面无需关心具体系列。
///
/// 同 SportEvent，故意不继承 Identifiable，避免 SwiftUI 把 Identifiable 默认 @MainActor 隔离
/// 后与 Sendable 在 Swift 6 严格并发下冲突。具体类型自带 id 即自动满足 Identifiable。
public nonisolated protocol MotorsportEvent: SportEvent {
    nonisolated var series: MotorsportSeries { get }
    nonisolated var round: Int { get }
    nonisolated var circuit: Circuit { get }
    /// 周末完整 session 列表，按 startTime 升序。
    nonisolated var sessions: [Session] { get }
    /// 周末开始(用于状态判断和"下一场"排序)。
    /// F1 用 sessions 第一项;MotoGP/WSBK 用 dateStart(列表页 sessions 为空)。
    nonisolated var weekendStart: Date { get }
    /// 周末结束(状态判断用,过了就 finished)。
    nonisolated var weekendEnd: Date { get }
}

public extension MotorsportEvent {
    /// 周末主赛 session（最后一个 race / 第二场 race）；用于"赛事开始时间"等单点计算。
    nonisolated var mainRace: Session? {
        sessions.last(where: { $0.kind == .race })
    }

    /// 基于当前时间和 weekendStart/End 实时算的状态——比 stored `status` 更准
    /// (列表 load 时 status 是历史快照;用户晚一天打开,实际正赛已过)。
    /// API 标了 postponed 时保留。
    nonisolated var currentStatus: EventStatus {
        if status == .postponed { return .postponed }
        let now = Date()
        if now < weekendStart { return .upcoming }
        if now <= weekendEnd { return .live }
        return .finished
    }
}
