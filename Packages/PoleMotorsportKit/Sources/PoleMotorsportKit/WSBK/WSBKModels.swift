import Foundation
import PoleDomain

// MARK: - Round

/// WSBK 一站 round。`circuit` 在列表页拿不到详细赛道名,只有国家三字码,
/// 详情页(目前未做)才能补全;v0.1 用国家代码占位 circuit.id/name。
public nonisolated struct WSBKRound: MotorsportEvent, Identifiable, Hashable, Sendable, Codable {
    public let id: String           // "wssp-2026-AUS"
    public let leagueId: String     // "wssp-2026"
    public let season: String
    public let round: Int
    public let countryCode: String  // "AUS" / "POR" / "JER"
    public let name: String         // "Australian Round" / "Pirelli Portuguese Round"
    public let dateRangeText: String // "20 - 22 Feb"——原始抓取文本,UI 直显
    public let circuit: Circuit
    public let dateStart: Date
    public let dateEnd: Date
    public let sessions: [Session]
    public let status: EventStatus
    /// 赛道线条简图 SVG URL——calendar HTML 卡片里抓到 circuit_tracks_*.svg 文件名后拼出。
    public let circuitMapImageURL: URL?

    public var sport: Sport { .motorsport }
    public var series: MotorsportSeries { .wssp }

    public var startTime: Date { mainRace?.startTime ?? dateStart }

    public var weekendStart: Date {
        sessions.first?.startTime ?? dateStart
    }

    public var weekendEnd: Date {
        if let last = sessions.last?.startTime {
            return last.addingTimeInterval(3 * 3600)
        }
        // dateEnd 是 GMT 0:00 周日,加 1 天让周日整天算 live
        return dateEnd.addingTimeInterval(24 * 3600)
    }

    /// 赛道航拍 banner 图(JPG)——保留备用,detail header 当前用线条简图 SVG。
    public var bannerImageURL: URL? {
        URL(string: "https://www.worldsbk.com/themes/responsive/static/img/calendar/cards/\(countryCode).jpg")
    }

    public var headline: String {
        Localization.wsbkRoundName(rawName: name, countryCode: countryCode)
    }

    public var subheadline: String {
        let countryDisplay = ChineseCountry.fromIOC(countryCode) ?? countryCode
        let prefix = L10n.effective == .en ? "Round" : "第"
        let suffix = L10n.effective == .en ? "" : "轮"
        return "\(prefix) \(round)\(suffix) · \(countryDisplay)"
    }

    /// 赛道布局 SVG —— 优先 julesr0y community(donington/jerez/portimao 等共享 F1 赛道命中);
    /// 没命中时回退到 worldsbk.com 解析的 svgURL(`circuitMapImageURL`)。
    public var trackMapURL: URL? {
        if let slug = CircuitMap.slug(forCircuitName: circuit.name, country: countryCode),
           let url = CircuitMap.url(slug: slug) {
            return url
        }
        return circuitMapImageURL
    }
}
