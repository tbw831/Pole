import Foundation
import PoleDomain
import PoleDesignSystem

/// 跨 series 时间线/统一查询用的包装类型——SwiftUI ForEach 不能直接用
/// `any MotorsportEvent`,enum 包装让 NavigationLink / ForEach 都能用。
public nonisolated enum AnyMotorsportRound: Hashable, Sendable, Identifiable {
    case f1(F1Race)
    case motogp(MotoGPRound)
    case wssp(WSBKRound)
    case fe(FERound)
    case feWeekend(FEWeekend)

    public var id: String {
        switch self {
        case .f1(let r):          return "f1:\(r.id)"
        case .motogp(let r):      return "motogp:\(r.id)"
        case .wssp(let r):        return "wssp:\(r.id)"
        case .fe(let r):          return "fe:\(r.id)"
        case .feWeekend(let w):   return "fe-weekend:\(w.id)"
        }
    }

    public var series: MotorsportSeries {
        switch self {
        case .f1:          return .f1
        case .motogp:      return .motogp
        case .wssp:        return .wssp
        case .fe:          return .fe
        case .feWeekend:   return .fe
        }
    }

    public var weekendStart: Date {
        switch self {
        case .f1(let r):          return r.weekendStart
        case .motogp(let r):      return r.weekendStart
        case .wssp(let r):        return r.weekendStart
        case .fe(let r):          return r.weekendStart
        case .feWeekend(let w):   return w.rounds.first!.weekendStart
        }
    }

    public var weekendEnd: Date {
        switch self {
        case .f1(let r):          return r.weekendEnd
        case .motogp(let r):      return r.weekendEnd
        case .wssp(let r):        return r.weekendEnd
        case .fe(let r):          return r.weekendEnd
        case .feWeekend(let w):   return w.rounds.last!.weekendEnd
        }
    }

    public var currentStatus: EventStatus {
        switch self {
        case .f1(let r):          return r.currentStatus
        case .motogp(let r):      return r.currentStatus
        case .wssp(let r):        return r.currentStatus
        case .fe(let r):          return r.currentStatus
        case .feWeekend(let w):   return w.rounds.first!.currentStatus
        }
    }

    public var headline: String {
        switch self {
        case .f1(let r):          return r.headline
        case .motogp(let r):      return r.headline
        case .wssp(let r):        return r.headline
        case .fe(let r):          return r.headline
        case .feWeekend(let w):   return w.headline
        }
    }

    public var subheadline: String {
        switch self {
        case .f1(let r):          return r.subheadline
        case .motogp(let r):      return r.subheadline
        case .wssp(let r):        return r.subheadline
        case .fe(let r):          return r.subheadline
        case .feWeekend(let w):   return w.subheadline
        }
    }
}
