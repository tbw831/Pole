import SwiftUI
import WidgetKit

struct AccessoryRectangularView: View {
    let entry: NextRaceEntry

    var body: some View {
        if let race = entry.snapshot?.nextRace {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .imageScale(.small)
                    Text(SeriesBrand.shortName(forRaw: race.seriesRaw))
                        .font(.caption2.weight(.semibold))
                }
                Text(race.roundName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                CountdownLabel(target: race.raceStart)
                    .font(.caption2.monospacedDigit())
            }
            .widgetAccentable()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(SeriesBrand.shortName(forRaw: race.seriesRaw)) \(race.roundName)")
        } else {
            HStack {
                Image(systemName: "flag.checkered")
                Text("赛季结束")
                    .font(.caption)
            }
            .accessibilityLabel("赛季结束")
        }
    }
}
