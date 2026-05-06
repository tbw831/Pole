import WidgetKit
import SwiftUI

struct NextRaceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct NextRaceProvider: TimelineProvider {
    typealias Entry = NextRaceEntry

    func placeholder(in context: Context) -> NextRaceEntry {
        NextRaceEntry(date: Date(), snapshot: Self.previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextRaceEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.read() ?? Self.previewSnapshot
        completion(NextRaceEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextRaceEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read()

        // 如果 snapshot 知道下场比赛的关键时刻,在那些时刻各排一个 entry,
        // 让 widget 在比赛开始 / 结束时自动刷新。
        var entries: [NextRaceEntry] = []
        entries.append(NextRaceEntry(date: now, snapshot: snapshot))

        if let race = snapshot?.nextRace {
            // 在 raceStart 前 1 小时 / 5 分钟 / 0 秒 / weekendEnd 各刷一次
            let triggers: [Date] = [
                race.raceStart.addingTimeInterval(-3600),
                race.raceStart.addingTimeInterval(-300),
                race.raceStart,
                race.weekendEnd
            ].filter { $0 > now }

            for date in triggers {
                entries.append(NextRaceEntry(date: date, snapshot: snapshot))
            }
        }

        // 远期(下场比赛 > 24h)用 .atEnd 让 entries 自然走完后等下次主 app 主动 reloadTimelines;
        // 近期用 30min 兜底,容错 snapshot 长时间没更新。
        // 以前一律 30min 唤醒,即使下场比赛在 7 天后也每 30min reload widget 浪费电。
        let policy: TimelineReloadPolicy
        if let race = snapshot?.nextRace, race.raceStart.timeIntervalSinceNow > 24 * 3600 {
            policy = .atEnd
        } else {
            let nextRefresh = entries.last?.date.addingTimeInterval(1800) ?? now.addingTimeInterval(1800)
            policy = .after(nextRefresh)
        }
        completion(Timeline(entries: entries, policy: policy))
    }

    /// 占位用:Xcode preview / widget gallery / snapshot 没生成时显示。
    static let previewSnapshot: WidgetSnapshot = {
        let now = Date()
        return WidgetSnapshot(
            generatedAt: now,
            nextRace: .init(
                seriesRaw: "f1",
                roundName: "Spanish Grand Prix",
                circuitName: "Circuit de Barcelona-Catalunya",
                countryCode: "ES",
                weekendStart: now.addingTimeInterval(86400 * 2),
                weekendEnd: now.addingTimeInterval(86400 * 4),
                raceStart: now.addingTimeInterval(86400 * 4),
                sessions: [
                    .init(label: "FP1", kindRaw: "practice", start: now.addingTimeInterval(86400 * 2)),
                    .init(label: "FP2", kindRaw: "practice", start: now.addingTimeInterval(86400 * 2 + 14400)),
                    .init(label: "FP3", kindRaw: "practice", start: now.addingTimeInterval(86400 * 3)),
                    .init(label: "Qualifying", kindRaw: "qualifying", start: now.addingTimeInterval(86400 * 3 + 14400)),
                    .init(label: "Race", kindRaw: "race", start: now.addingTimeInterval(86400 * 4))
                ],
                statusRaw: "upcoming"
            ),
            followedDrivers: []
        )
    }()
}
