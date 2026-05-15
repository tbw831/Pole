import Foundation
import PoleDomain
import PoleDesignSystem

// MARK: - Round

/// MotoGP 一站大奖赛(一个比赛周末)。
/// `sessions` 在赛历列表里通常为空,详情页 task 加载完真实 sessions 后由 ViewModel 持有,
/// 不直接 mutate struct(struct 不可变,详情 ViewModel 持有 [Session] 状态)。
public nonisolated struct MotoGPRound: MotorsportEvent, Identifiable, Hashable, Sendable, Codable {
    public let id: String           // event UUID(Pulselive)
    public let leagueId: String     // "motogp-2026"
    public let season: String       // "2026"
    public let round: Int           // 在赛季 events 里的位置(1 起,自己排)
    public let name: String         // "GRAND PRIX DE FRANCE"
    public let shortName: String    // "FRA"
    public let circuit: Circuit
    public let dateStart: Date      // 周五(无时间,Pulselive 只给日期)
    public let dateEnd: Date        // 周日
    public let sessions: [Session]  // 列表页通常 [] ,详情页加载后单独保存
    public let status: EventStatus

    public var sport: Sport { .motorsport }
    public var series: MotorsportSeries { .motogp }

    public var startTime: Date {
        // 没 sessions 时退回 dateStart;有 race session 时取它
        mainRace?.startTime ?? dateStart
    }

    public var weekendStart: Date {
        sessions.first?.startTime ?? dateStart
    }

    public var weekendEnd: Date {
        // 列表页 sessions=[] 时只有日期级精度,给 dateEnd 多 1 天 grace,
        // 让周日整天都算 live(实际正赛在周日下午)
        if let last = sessions.last?.startTime {
            return last.addingTimeInterval(3 * 3600)
        }
        return dateEnd.addingTimeInterval(24 * 3600)
    }

    public var headline: String {
        Localization.motoGPRoundName(rawName: name, countryCode: shortName)
    }

    public var subheadline: String {
        let prefix = L10n.effective == .en ? "Round" : "第"
        let suffix = L10n.effective == .en ? "" : "轮"
        return "\(prefix) \(round)\(suffix) · \(circuit.locality), \(circuit.country)"
    }

    /// 赛道布局 SVG —— 共享 F1 赛道的命中 ~50%,独有赛道(misano/aragon/assen 等)返 nil。
    public var trackMapURL: URL? {
        guard let slug = CircuitMap.slug(forCircuitName: circuit.name, country: circuit.country)
        else { return nil }
        return CircuitMap.url(slug: slug)
    }
}
