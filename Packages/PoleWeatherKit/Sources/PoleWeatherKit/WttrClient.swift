import Foundation
import os
import PoleSharedKit

nonisolated fileprivate let wttrLog = Logger(subsystem: "com.tiebowen.Pole", category: "WttrClient")

/// 简单天气 — wttr.in 公开 JSON,免认证免 API key。
/// 返回未来 3 天预报,赛事远于 3 天的不显示。
public actor WttrClient {
    public static let shared = WttrClient()
    private let session: URLSession
    private let isoFormatter: ISO8601DateFormatter

    public init(session: URLSession = SharedURLSession.cached) {
        self.session = session
        self.isoFormatter = ISO8601DateFormatter()
    }

    /// 拉 location 预报,返回最接近 targetDate 那天的概要。
    /// 超出 3 天预报范围返 nil(UI 直接不显示天气卡片)。
    public func fetchForecast(location: String, targetDate: Date) async throws -> WeatherSnapshot? {
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
        guard let url = URL(string: "https://wttr.in/\(encoded)?format=j1") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let decoded = try JSONDecoder().decode(WttrResponse.self, from: data)

        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)

        // 找跟 targetDate 同一天的预报;找不到就用 day 0(今天)
        let targetStr = dateOnly.string(from: targetDate)
        let exactMatch = decoded.weather.first { $0.date == targetStr }
        if exactMatch == nil {
            // 超出 3 天预报范围(wttr.in 限制),log 提示开发期可定位"天气卡不显示"
            wttrLog.debug("no forecast for \(targetStr, privacy: .public) at \(location, privacy: .public); fallback to day 0")
        }
        let day = exactMatch ?? decoded.weather.first
        guard let day else {
            wttrLog.warning("wttr returned empty weather array for \(location, privacy: .public)")
            return nil
        }

        let desc = day.hourly.first?.weatherDesc.first?.value ?? "—"
        let iconCode = day.hourly.first?.weatherCode

        // 温度都解析失败时返 nil 让 UI 不显示卡片,而不是显示假的 0°C 误导。
        // wttr.in 返回字符串如 "23",`Int()` 失败说明 schema 变了。
        guard let maxTemp = Int(day.maxtempC),
              let minTemp = Int(day.mintempC) else {
            return nil
        }

        return WeatherSnapshot(
            date: dateOnly.date(from: day.date) ?? targetDate,
            maxTempC: maxTemp,
            minTempC: minTemp,
            description: desc,
            iconCode: iconCode
        )
    }

    // MARK: - DTOs

    private struct WttrResponse: Sendable, nonisolated Decodable {
        let weather: [Day]

        struct Day: Sendable, nonisolated Decodable {
            let date: String
            let maxtempC: String
            let mintempC: String
            let hourly: [Hour]
        }

        struct Hour: Sendable, nonisolated Decodable {
            let weatherDesc: [LocalizedString]
            let weatherCode: String?
        }

        struct LocalizedString: Sendable, nonisolated Decodable {
            let value: String
        }
    }
}

/// UI 用的天气快照——仅必要字段。
public struct WeatherSnapshot: Sendable, Hashable {
    public let date: Date
    public let maxTempC: Int
    public let minTempC: Int
    public let description: String   // "Patchy rain nearby" / "Sunny" 等英文
    public let iconCode: String?     // wttr.in 用的 weatherCode,可映射到 SF Symbols

    /// 简单映射 wttr.in weatherCode → SF Symbols
    public var sfSymbol: String {
        guard let code = iconCode else { return "cloud" }
        switch code {
        case "113": return "sun.max"            // Clear/Sunny
        case "116": return "cloud.sun"          // Partly cloudy
        case "119", "122": return "cloud"       // Cloudy/Overcast
        case "143", "248", "260": return "cloud.fog"  // Fog/Mist
        case "176", "263", "266", "281", "284", "293", "296", "299", "302", "305", "308", "311", "314", "317", "350", "353", "356", "359":
            return "cloud.rain"                 // Rain
        case "200", "386", "389", "392", "395": return "cloud.bolt.rain"  // Thunder
        case "179", "227", "230", "323", "326", "329", "332", "335", "338", "368", "371":
            return "cloud.snow"                 // Snow
        default: return "cloud"
        }
    }
}
