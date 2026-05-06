import SwiftUI
import WidgetKit

struct MediumView: View {
    let entry: NextRaceEntry

    var body: some View {
        if let race = entry.snapshot?.nextRace {
            HStack(alignment: .top, spacing: 12) {
                // 左侧:系列色条 + 标题区
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SeriesBrand.color(forRaw: race.seriesRaw))
                            .frame(width: 8, height: 8)
                        Text(SeriesBrand.displayName(forRaw: race.seriesRaw))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(race.roundName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(race.circuitName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    CountdownLabel(target: race.raceStart)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(SeriesBrand.color(forRaw: race.seriesRaw))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // 右侧:关注车手简表(最多 3 条),没有就显示主 race 时间
                if let drivers = entry.snapshot?.followedDrivers, !drivers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关注")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(drivers.prefix(3))) { driver in
                            HStack(spacing: 4) {
                                if let rank = driver.rank {
                                    Text("P\(rank)")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(SeriesBrand.color(forRaw: driver.seriesRaw))
                                        .frame(width: 24, alignment: .leading)
                                }
                                Text(driver.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正赛时间")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(race.raceStart, style: .date)
                            .font(.caption)
                        Text(race.raceStart, style: .time)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        } else {
            EmptyStateView()
        }
    }
}
