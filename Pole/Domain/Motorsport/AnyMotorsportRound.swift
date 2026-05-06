import Foundation

/// 跨 series 时间线/统一查询用的包装类型——SwiftUI ForEach 不能直接用
/// `any MotorsportEvent`,enum 包装让 NavigationLink / ForEach 都能用。
public nonisolated enum AnyMotorsportRound: Hashable, Sendable, Identifiable {
    case f1(F1Race)
    case motogp(MotoGPRound)
    case wssp(WSBKRound)
    case fe(FERound)

    public var id: String {
        switch self {
        case .f1(let r):     return "f1:\(r.id)"
        case .motogp(let r): return "motogp:\(r.id)"
        case .wssp(let r):   return "wssp:\(r.id)"
        case .fe(let r):     return "fe:\(r.id)"
        }
    }

    public var series: MotorsportSeries {
        switch self {
        case .f1:     return .f1
        case .motogp: return .motogp
        case .wssp:   return .wssp
        case .fe:     return .fe
        }
    }

    public var weekendStart: Date {
        switch self {
        case .f1(let r):     return r.weekendStart
        case .motogp(let r): return r.weekendStart
        case .wssp(let r):   return r.weekendStart
        case .fe(let r):     return r.weekendStart
        }
    }

    public var weekendEnd: Date {
        switch self {
        case .f1(let r):     return r.weekendEnd
        case .motogp(let r): return r.weekendEnd
        case .wssp(let r):   return r.weekendEnd
        case .fe(let r):     return r.weekendEnd
        }
    }

    public var currentStatus: EventStatus {
        switch self {
        case .f1(let r):     return r.currentStatus
        case .motogp(let r): return r.currentStatus
        case .wssp(let r):   return r.currentStatus
        case .fe(let r):     return r.currentStatus
        }
    }

    public var headline: String {
        switch self {
        case .f1(let r):     return r.headline
        case .motogp(let r): return r.headline
        case .wssp(let r):   return r.headline
        case .fe(let r):     return r.headline
        }
    }

    public var subheadline: String {
        switch self {
        case .f1(let r):     return r.subheadline
        case .motogp(let r): return r.subheadline
        case .wssp(let r):   return r.subheadline
        case .fe(let r):     return r.subheadline
        }
    }
}
