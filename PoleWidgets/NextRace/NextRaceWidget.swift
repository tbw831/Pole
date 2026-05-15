import WidgetKit
import SwiftUI

struct NextRaceWidget: Widget {
    let kind: String = "NextRaceWidget"

    var body: some WidgetConfiguration {
        // AppIntentConfiguration:用户可在 long-press 编辑器里 pin 特定系列
        // (F1 / MotoGP / WSBK / FE),也可保持 "全部" 看四系列里最早的一场。
        // 替代之前的 StaticConfiguration —— 单实例无配置,无法分系列。
        AppIntentConfiguration(
            kind: kind,
            intent: SelectSeriesIntent.self,
            provider: NextRaceProvider()
        ) { entry in
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
