import WidgetKit
import SwiftUI

struct NextRaceWidget: Widget {
    let kind: String = "NextRaceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextRaceProvider()) { entry in
            NextRaceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("下场比赛")
        .description("跨 F1 / MotoGP / WorldSBK / Formula E 显示最近一场比赛")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

/// 按 widgetFamily 路由到对应的子 view。
struct NextRaceWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextRaceEntry

    var body: some View {
        switch family {
        case .systemSmall:           SmallView(entry: entry)
        case .systemMedium:          MediumView(entry: entry)
        case .systemLarge:           LargeView(entry: entry)
        case .accessoryRectangular: AccessoryRectangularView(entry: entry)
        case .accessoryCircular:    AccessoryCircularView(entry: entry)
        case .accessoryInline:      AccessoryInlineView(entry: entry)
        @unknown default:            SmallView(entry: entry)
        }
    }
}
