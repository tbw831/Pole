import SwiftUI
import WidgetKit

struct LargeView: View {
    let entry: NextRaceEntry

    var body: some View {
        if let race = entry.snapshot?.nextRace {
            VStack(alignment: .leading, spacing: 8) {
                // 顶部:系列 + 标题 + 倒计时
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SeriesBrand.color(forRaw: race.seriesRaw))
                            .frame(width: 10, height: 10)
                        Text(SeriesBrand.displayName(forRaw: race.seriesRaw))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        CountdownLabel(target: race.raceStart)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(SeriesBrand.color(forRaw: race.seriesRaw))
                    }
                    Text(race.roundName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(race.circuitName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 中部:周末赛程
                Text("周末赛程")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(race.sessions.prefix(6))) { session in
                        HStack {
                            Text(session.label)
                                .font(.caption.weight(.medium))
                                .frame(width: 80, alignment: .leading)
                            Text(session.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyStateView()
        }
    }
}
