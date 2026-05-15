import Foundation
import AppIntents
import SwiftUI
import PoleDomain
import PoleMotorsportKit
import PoleAIKit

// MARK: - 1. NextRaceIntent — "下一场 X 在哪"

/// 「嘿 Siri,下一场 F1 在哪」/「Pole 最近的赛车」。
/// 默认 .all,Siri 给跨系列最近一场。
public struct NextRaceIntent: AppIntent {
    public static var title: LocalizedStringResource = "下一场比赛"
    public static var description = IntentDescription(
        "查询某系列的下一场即将开始的比赛",
        categoryName: "查询"
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "系列", default: .all)
    public var series: SeriesParameter

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<RaceAppEntity?> {
        let all = await RaceEntityQuery.allCachedEntities()
        let now = Date()
        let filtered = all
            .filter { $0.startDate >= now }
            .filter { series == .all || $0.seriesRaw == series.rawValue }
            .sorted { $0.startDate < $1.startDate }

        guard let next = filtered.first else {
            return .result(
                value: nil,
                dialog: IntentDialog(stringLiteral: L10n.t(zh: "暂无即将开始的比赛", en: "No upcoming races"))
            )
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: next.startDate)
        let speech = L10n.t(
            zh: "下一场是\(next.displayName),\(when) 开始",
            en: "Next is \(next.displayName) on \(when)"
        )
        return .result(value: next, dialog: IntentDialog(stringLiteral: speech))
    }
}

// MARK: - 2. AddWeekendRacesIntent — "把这周末赛事加日历"

public struct AddWeekendRacesIntent: AppIntent {
    public static var title: LocalizedStringResource = "本周末赛事加日历"
    public static var description = IntentDescription(
        "把本周末所有系列的正赛加到 iOS 日历",
        categoryName: "日历"
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let all = await RaceEntityQuery.allCachedEntities()
        let now = Date()
        let in7days = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let weekendRaces = all.filter { $0.startDate >= now && $0.startDate < in7days }

        guard !weekendRaces.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.t(
                zh: "本周末没有比赛", en: "No races this weekend"
            )))
        }

        var added = 0
        for race in weekendRaces {
            let id = await CalendarService.shared.addEvent(
                title: race.displayName,
                start: race.startDate,
                end: race.startDate.addingTimeInterval(2 * 3600),
                notes: race.subtitle
            )
            if id != nil { added += 1 }
        }

        let dialog = L10n.t(
            zh: "已加 \(added) 场到日历", en: "Added \(added) races to calendar"
        )
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - 3. DriverFormIntent — "X 最近怎么样"

public struct DriverFormIntent: AppIntent {
    public static var title: LocalizedStringResource = "车手近况"
    public static var description = IntentDescription(
        "用 AI 分析某车手最近表现",
        categoryName: "查询"
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "车手姓名", description: "如 Verstappen / 维斯塔潘 / Hamilton")
    public var driverName: String

    public init() {}
    public init(driverName: String) {
        self.driverName = driverName
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // 走 LLM 直接生成简短回答(LLMClient 已有重试机制)
        let prompt = L10n.t(
            zh: "用 1-2 句话(每句不超 20 字)总结 \(driverName) 最近表现,基于赛车圈常识。直接给段落不要客套。",
            en: "In 1-2 short sentences (≤15 words each) summarize \(driverName)'s recent racing form. No filler, just content."
        )
        let response = (try? await LLMClient.shared.chat(
            system: nil, user: prompt
        )) ?? L10n.t(zh: "暂时查不到该车手信息", en: "Driver info unavailable right now")

        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

// MARK: - 4. StandingsIntent — "F1 积分榜前几"

public struct StandingsIntent: AppIntent {
    public static var title: LocalizedStringResource = "积分榜"
    public static var description = IntentDescription(
        "读出某系列车手积分榜前 5",
        categoryName: "查询"
    )
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "系列", default: .f1)
    public var series: SeriesParameter

    public init() {}
    public init(series: SeriesParameter) {
        self.series = series
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let top = await Self.fetchTop5(series: series)
        guard !top.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.t(
                zh: "积分榜暂时拉不到",
                en: "Standings unavailable"
            )))
        }
        let formatted = top.enumerated().map { idx, line in
            "\(idx + 1). \(line)"
        }.joined(separator: ";")
        let prefix = L10n.t(
            zh: "\(series == .all ? "F1" : seriesDisplay(series)) 前 5 — ",
            en: "\(seriesDisplay(series)) top 5: "
        )
        return .result(dialog: IntentDialog(stringLiteral: prefix + formatted))
    }

    private func seriesDisplay(_ s: SeriesParameter) -> String {
        switch s {
        case .f1: return "F1"
        case .motogp: return "MotoGP"
        case .wsbk: return "WorldSBK"
        case .fe: return "Formula E"
        case .all: return "F1"
        }
    }

    /// 各系列的前 5 文本格式 "维斯塔潘 273 分"。
    static func fetchTop5(series: SeriesParameter) async -> [String] {
        switch series {
        case .f1, .all:
            let s = (try? await JolpicaClient.shared.fetchDriverStandings()) ?? []
            return s.prefix(5).map { "\($0.driver.displayName) \(Int($0.points)) 分" }
        case .motogp:
            let s = (try? await MotoGPClient.shared.fetchRiderStandings()) ?? []
            return s.prefix(5).map { "\($0.rider.displayName) \(Int($0.points)) 分" }
        case .wsbk:
            let s = (try? await WSBKClient.shared.fetchSSPRiderStandings()) ?? []
            return s.prefix(5).map { "\($0.rider.displayName) \(Int($0.points)) 分" }
        case .fe:
            let s = (try? await FormulaEClient.shared.fetchDriverStandings()) ?? []
            return s.prefix(5).map { "\($0.driver.displayName) \(Int($0.points)) 分" }
        }
    }
}

// MARK: - 5. WeekendScheduleIntent — "本周末有什么比赛"

public struct WeekendScheduleIntent: AppIntent {
    public static var title: LocalizedStringResource = "本周末赛程"
    public static var description = IntentDescription(
        "列出未来 7 天所有系列的比赛",
        categoryName: "查询"
    )
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let all = await RaceEntityQuery.allCachedEntities()
        let now = Date()
        let in7days = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let weekend = all.filter { $0.startDate >= now && $0.startDate < in7days }
            .sorted { $0.startDate < $1.startDate }

        guard !weekend.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: L10n.t(
                zh: "本周末没有比赛",
                en: "No races this weekend"
            )))
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let lines = weekend.map { race -> String in
            let when = formatter.string(from: race.startDate)
            return "\(race.displayName) \(when)"
        }
        let prefix = L10n.t(zh: "本周末 \(lines.count) 场:", en: "\(lines.count) races this weekend:")
        return .result(dialog: IntentDialog(stringLiteral: prefix + lines.joined(separator: ";")))
    }
}

// MARK: - 联动用 — 阶段 3 的 Intent

/// Live Activity 上的"打开 detail"按钮触发 — 跳进 app 对应 race detail。
/// 通过 NotificationCenter post 一个事件,主 app NavigationStack 监听跳转。
public struct OpenRaceDetailIntent: AppIntent {
    public static var title: LocalizedStringResource = "打开赛事详情"
    public static var description = IntentDescription("从锁屏 / 灵动岛跳到赛事 detail 页")
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "赛事")
    public var race: RaceAppEntity

    public init() {}
    public init(race: RaceAppEntity) {
        self.race = race
    }

    public func perform() async throws -> some IntentResult {
        // openAppWhenRun=true 自动开 app;NotificationCenter 通知 ContentView 跳到对应 race
        await MainActor.run {
            NotificationCenter.default.post(
                name: .openRaceDetail,
                object: nil,
                userInfo: ["raceEntityId": race.id]
            )
        }
        return .result()
    }
}

/// Live Activity 上"停止跟看"按钮 — 关掉当前 Live Activity。
public struct StopLiveActivityIntent: AppIntent {
    public static var title: LocalizedStringResource = "停止赛事跟看"
    public static var description = IntentDescription("关掉当前 Live Activity")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        await RaceLiveActivityCoordinator.shared.stopAll()
        return .result()
    }
}

/// 通知名 — 跨模块跳转用。
public extension Notification.Name {
    static let openRaceDetail = Notification.Name("openRaceDetail")
    /// 用户切到 AI tab — ChatView 收到后回到 starter(greeting)页,放弃当前会话(历史仍在)
    static let resetChatToStarter = Notification.Name("resetChatToStarter")
}
