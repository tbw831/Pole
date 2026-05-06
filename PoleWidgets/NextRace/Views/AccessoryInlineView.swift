import SwiftUI
import WidgetKit

struct AccessoryInlineView: View {
    let entry: NextRaceEntry

    var body: some View {
        if let race = entry.snapshot?.nextRace, race.raceStart > Date() {
            Text("\(SeriesBrand.shortName(forRaw: race.seriesRaw)) · \(race.roundName) · \(race.raceStart, style: .relative)")
        } else {
            Text("赛季结束")
        }
    }
}
