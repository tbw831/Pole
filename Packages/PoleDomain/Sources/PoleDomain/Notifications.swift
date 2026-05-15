import Foundation

public extension Notification.Name {
    /// Posted from FollowFeedView empty-state CTA to switch ContentView's selected tab to Motorsport.
    static let navigateToMotorsportTab = Notification.Name("navigateToMotorsportTab")

    /// Posted from SettingsView when user disables Live Activity toggle.
    /// Main app subscribes and calls `RaceLiveActivityCoordinator.shared.stopAll()`.
    static let stopAllLiveActivities = Notification.Name("stopAllLiveActivities")

    /// Posted from RaceDetailView "开始跟看" button.
    /// `userInfo` keys: `raceId` / `seriesRaw` / `displayName` / `subtitle` / `startDate` (Date).
    /// Main app subscribes and calls `RaceLiveActivityCoordinator.shared.start(from:)`.
    static let startLiveActivityForRace = Notification.Name("startLiveActivityForRace")

    /// 灵动岛/Live Activity 点击 → 主 app 跳转。由 AppIntent 触发,ContentView 订阅。
    static let openRaceDetail = Notification.Name("openRaceDetail")

    /// 用户切到 AI tab — ChatView 收到后回到 starter(greeting)页,放弃当前会话(历史仍在)
    static let resetChatToStarter = Notification.Name("resetChatToStarter")
}
