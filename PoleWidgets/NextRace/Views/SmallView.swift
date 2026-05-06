import SwiftUI
import WidgetKit

struct SmallView: View {
    let entry: NextRaceEntry

    var body: some View {
        if let race = entry.snapshot?.nextRace {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(SeriesBrand.color(forRaw: race.seriesRaw))
                        .frame(width: 8, height: 8)
                    Text(SeriesBrand.shortName(forRaw: race.seriesRaw))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(race.roundName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                CountdownLabel(target: race.raceStart)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(SeriesBrand.color(forRaw: race.seriesRaw))
                Text(race.circuitName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyStateView()
        }
    }
}

/// 倒计时 label——SwiftUI Text 自带 .timer style,不需要 timeline 频繁刷新。
struct CountdownLabel: View {
    let target: Date

    var body: some View {
        if target > Date() {
            Text(target, style: .timer)
        } else {
            Text("进行中")
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("赛季结束")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
