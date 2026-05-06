import SwiftUI
import WidgetKit

struct AccessoryCircularView: View {
    let entry: NextRaceEntry

    var body: some View {
        if let race = entry.snapshot?.nextRace, race.raceStart > Date() {
            // 显示距离开赛的小时数
            let hours = max(0, Int(race.raceStart.timeIntervalSinceNow / 3600))
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(hours)")
                        .font(.title2.weight(.bold).monospacedDigit())
                    Text("hr")
                        .font(.caption2)
                }
            }
            .widgetAccentable()
            // VoiceOver 不再读"12 hr"两段独立 Text;统一读距离 X 小时 + 比赛名
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("距离 \(race.roundName) 开赛还有 \(hours) 小时")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "flag.checkered")
            }
            .accessibilityLabel("赛季结束")
        }
    }
}
