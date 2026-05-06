import WidgetKit
import SwiftUI

/// Widget Extension bundle 入口 — 一个 extension 可以注册多个 widget。
/// - `NextRaceWidget`:主屏 / 锁屏 / StandBy 显示下场比赛(读 App Group JSON snapshot)
/// - `RaceLiveActivityWidget`:用户主动从 RaceDetailView 启动的 Live Activity(锁屏 + 灵动岛)
@main
struct PoleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextRaceWidget()
        RaceLiveActivityWidget()
    }
}
