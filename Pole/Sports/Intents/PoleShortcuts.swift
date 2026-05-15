import Foundation
import AppIntents

/// AppShortcutsProvider — iOS 16+ 自动把这里注册的 phrase 收进:
/// - Siri(可直接说出 phrase)
/// - Shortcuts app(用户能拖进自动化)
/// - Spotlight 建议
/// - iOS 26 Apple Intelligence 模糊语义匹配
///
/// 每个 phrase **必须**含 `\(.applicationName)` 锚定到本 app(不强制以 app 名开头,
/// 但 Apple 强烈建议),否则 Siri 可能歧义匹配到别的 app。
///
/// 中英文 phrase 都给,iOS 按系统语言自动选。
public struct PoleShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextRaceIntent(),
            phrases: [
                "在 \(.applicationName) 里下一场比赛",
                "\(.applicationName) 下一场",
                "\(.applicationName) 下一场 F1",
                "\(.applicationName) 下一场比赛",
                "Next race in \(.applicationName)",
                "When is the next race in \(.applicationName)",
                "What's the next race in \(.applicationName)"
            ],
            shortTitle: "下一场",
            systemImageName: "flag.checkered"
        )

        AppShortcut(
            intent: AddWeekendRacesIntent(),
            phrases: [
                "把本周末的比赛加日历用 \(.applicationName)",
                "\(.applicationName) 本周末加日历",
                "\(.applicationName) 加这周末的比赛",
                "Add this weekend's races in \(.applicationName)",
                "Add weekend races in \(.applicationName)"
            ],
            shortTitle: "本周末加日历",
            systemImageName: "calendar.badge.plus"
        )

        AppShortcut(
            intent: WeekendScheduleIntent(),
            phrases: [
                "\(.applicationName) 本周末有什么比赛",
                "\(.applicationName) 本周末赛程",
                "\(.applicationName) 这周比赛",
                "What races this weekend in \(.applicationName)",
                "Weekend schedule in \(.applicationName)"
            ],
            shortTitle: "本周末赛程",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: StandingsIntent(),
            phrases: [
                "\(.applicationName) 积分榜",
                "\(.applicationName) F1 积分榜",
                "\(.applicationName) 车手积分榜前 5",
                "Standings in \(.applicationName)",
                "Top 5 drivers in \(.applicationName)"
            ],
            shortTitle: "积分榜",
            systemImageName: "list.number"
        )

        AppShortcut(
            intent: DriverFormIntent(),
            phrases: [
                "\(.applicationName) 车手近况",
                "在 \(.applicationName) 查车手",
                "Driver form in \(.applicationName)",
                "How is the driver doing in \(.applicationName)"
            ],
            shortTitle: "车手近况",
            systemImageName: "person.fill"
        )
    }

    /// 推荐分类(Shortcuts app 显示用)。
    public static let shortcutTileColor: ShortcutTileColor = .purple
}
