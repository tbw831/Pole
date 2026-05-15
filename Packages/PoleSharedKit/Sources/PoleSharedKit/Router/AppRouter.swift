import SwiftUI

/// 集中管理 5 个 Tab 的 navigation path 与跨 Tab 深链。
/// 用作 `@Environment(AppEnv.self)` 中的 router 字段。
@MainActor
@Observable
public final class AppRouter {

    /// Tab 标识。值与 ContentView 中 segment picker 的顺序一致。
    public enum Tab: Hashable, CaseIterable, Sendable {
        case motorsport
        case standings
        case chat
        case follow
        case settings
    }

    /// 详情页 destination。每个 Tab 的 NavigationStack(path:) 用这个类型。
    /// 注意:`AnyMotorsportRound` 仍在 main app target,本包看不到它;
    /// PR2 拆 PoleDomain 后会改回强类型 round 引用。
    /// 当前用 `(series:roundId:)` / `(series:driverId:)` 间接表示。
    public enum Destination: Hashable, Sendable {
        case roundDetail(series: String, roundId: String)
        case driverDetail(series: String, driverId: String)
        case teamDetail(series: String, teamId: String)
    }

    public var selectedTab: Tab = .motorsport
    public var motorsportPath: [Destination] = []
    public var standingsPath: [Destination] = []
    public var chatPath: [Destination] = []
    public var followPath: [Destination] = []
    public var settingsPath: [Destination] = []

    public init() {}

    /// 深链跳转入口:Live Activity / Notification / Spotlight / AppIntent 都走这里。
    public func deeplink(to destination: Destination) {
        switch destination {
        case .roundDetail:
            selectedTab = .motorsport
            motorsportPath.append(destination)
        case .driverDetail, .teamDetail:
            selectedTab = .standings
            standingsPath.append(destination)
        }
    }

    /// 清空指定 Tab 的 stack(回到该 Tab 的 root)
    public func popToRoot(_ tab: Tab) {
        switch tab {
        case .motorsport: motorsportPath.removeAll()
        case .standings:  standingsPath.removeAll()
        case .chat:       chatPath.removeAll()
        case .follow:     followPath.removeAll()
        case .settings:   settingsPath.removeAll()
        }
    }
}
