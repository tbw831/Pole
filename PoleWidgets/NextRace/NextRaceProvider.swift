import WidgetKit
import SwiftUI

struct NextRaceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// 用户在 widget 编辑器里选的系列(`.all` = 不过滤)。
    /// 由 `SelectSeriesIntent.series` 传入 — 当 snapshot.nextRace.seriesRaw
    /// 与之不匹配时,Provider 会把 nextRace 置 nil,view 走"赛季结束"占位。
    let selectedSeries: SeriesSelection
}

struct NextRaceProvider: AppIntentTimelineProvider {
    typealias Intent = SelectSeriesIntent
    typealias Entry = NextRaceEntry

    func placeholder(in context: Context) -> NextRaceEntry {
        NextRaceEntry(
            date: Date(),
            snapshot: Self.previewSnapshot,
            selectedSeries: .all
        )
    }

    func snapshot(for configuration: SelectSeriesIntent, in context: Context) async -> NextRaceEntry {
        let snapshot = WidgetSnapshotStore.read() ?? Self.previewSnapshot
        let filtered = Self.filter(snapshot: snapshot, by: configuration.series)
        return NextRaceEntry(
            date: Date(),
            snapshot: filtered,
            selectedSeries: configuration.series
        )
    }

    func timeline(for configuration: SelectSeriesIntent, in context: Context) async -> Timeline<NextRaceEntry> {
        let now = Date()
        let rawSnapshot = WidgetSnapshotStore.read()
        let snapshot = rawSnapshot.flatMap { Self.filter(snapshot: $0, by: configuration.series) }

        // 如果 snapshot 知道下场比赛的关键时刻,在那些时刻各排一个 entry,
        // 让 widget 在比赛开始 / 结束时自动刷新。
        var entries: [NextRaceEntry] = []
        entries.append(NextRaceEntry(date: now, snapshot: snapshot, selectedSeries: configuration.series))

        if let race = snapshot?.nextRace {
            // 在 raceStart 前 1 小时 / 5 分钟 / 0 秒 / weekendEnd 各刷一次
            let triggers: [Date] = [
                race.raceStart.addingTimeInterval(-3600),
                race.raceStart.addingTimeInterval(-300),
                race.raceStart,
                race.weekendEnd
            ].filter { $0 > now }

            for date in triggers {
                entries.append(NextRaceEntry(date: date, snapshot: snapshot, selectedSeries: configuration.series))
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
        return Timeline(entries: entries, policy: policy)
    }

    /// 按用户选择的系列过滤 snapshot.nextRace。
    /// - `.all`:原样返回。
    /// - 具体系列:nextRace 的 seriesRaw 不匹配时把 nextRace 置 nil。
    ///   followedDrivers 不动 — view 端按 driver.seriesRaw 自行展示即可。
    ///
    /// 注:当前 main app 写出的 snapshot 只有"四系列里最早一场",
    /// 所以选具体系列时如果那个系列不是最早,nextRace 会被置 nil
    /// (短期内 view 显示"赛季结束")。后续 main app 升级写多系列各自 nextRace
    /// 时这里不用改,过滤逻辑一致。
    private static func filter(snapshot: WidgetSnapshot, by selection: SeriesSelection) -> WidgetSnapshot {
        guard let wantedRaw = selection.seriesRaw else { return snapshot }
        guard let race = snapshot.nextRace, race.seriesRaw == wantedRaw else {
            return WidgetSnapshot(
                generatedAt: snapshot.generatedAt,
                nextRace: nil,
                followedDrivers: snapshot.followedDrivers
            )
        }
        return snapshot
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
