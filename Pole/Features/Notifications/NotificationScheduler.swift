import Foundation
import SwiftData
import UserNotifications

/// 本地通知调度——为赛车 sessions 注册赛前提醒。
/// 策略 hardcode(仅自用):
///   race / superpoleRace : -30 min
///   qualifying / sprint / sprintShootout : -15 min
///   practice : 不推送
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "session:"

    /// 上次 reschedule 用的 races + skipKeys 哈希,5min 内同样的输入直接跳过 — 避免
    /// MotorsportTimelineView refreshable / RaceListView .task / scenePhase active 三处都触发
    /// 同一批 races 重复重排(每次都涉及 pendingNotificationRequests 拉取 + remove + N add)。
    private var lastRescheduleHash: Int?
    private var lastRescheduleAt: Date?
    private let rescheduleDebounce: TimeInterval = 300

    /// 在 app 首次启动 / 进入 Settings 时调用。重复调用安全。
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 给一组赛事重排所有 session 通知。先清掉已注册的 "session:*",再为未来 session 重新注册。
    /// 自动跳过用户已加日历的 session — EventKit 自带 -30min alarm,跳过避免双重打扰。
    func reschedule(for races: [some MotorsportEvent]) async {
        let skipSessionKeys = fetchAddedCalendarKeys()
        await reschedule(for: races, skipSessionKeys: skipSessionKeys)
    }

    /// 显式传 skipKeys 的低层入口(测试 / 自定义场景用)。
    func reschedule(for races: [some MotorsportEvent], skipSessionKeys: Set<String>) async {
        // 幂等:5min 内同 input 跳过(MotorsportTimelineView .refreshable / RaceListView .task /
        // scenePhase active 三处都会触发,绝大多数情况是同一批数据)。
        let inputHash = Self.hashInputs(races: races, skipKeys: skipSessionKeys)
        let now0 = Date()
        if let last = lastRescheduleAt,
           let h = lastRescheduleHash,
           h == inputHash,
           now0.timeIntervalSince(last) < rescheduleDebounce {
            return
        }
        lastRescheduleHash = inputHash
        lastRescheduleAt = now0

        let pending = await center.pendingNotificationRequests()
        let oldIds = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        let now = Date()
        for race in races {
            for session in race.sessions {
                guard let lead = leadTimeMinutes(for: session.kind) else { continue }
                // 已加日历的 session 让 EventKit alarm 通知,这里不重复。
                if skipSessionKeys.contains(session.id) { continue }
                let triggerDate = session.startTime.addingTimeInterval(TimeInterval(-lead * 60))
                guard triggerDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "\(race.headline) — \(session.localizedLabel)"
                content.body = L10n.t(zh: "\(lead) 分钟后开始 · \(race.circuit.name)",
                                       en: "Starts in \(lead) min · \(race.circuit.name)")
                content.sound = .default

                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(identifierPrefix)\(session.id)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
        WidgetSnapshotBuilder.refresh(force: true)
    }

    /// 全清(用户在 Settings 关掉总开关时用)。
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        lastRescheduleHash = nil
        lastRescheduleAt = nil
    }

    /// 输入 hash — 用 sessionId + startTime + skipKeys 组合,精度足够幂等判断。
    private static func hashInputs(races: [some MotorsportEvent], skipKeys: Set<String>) -> Int {
        var hasher = Hasher()
        for race in races {
            for session in race.sessions {
                hasher.combine(session.id)
                hasher.combine(session.startTime.timeIntervalSince1970)
            }
        }
        for k in skipKeys.sorted() {
            hasher.combine(k)
        }
        return hasher.finalize()
    }

    func pendingCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }

    private func leadTimeMinutes(for kind: Session.Kind) -> Int? {
        // 用户在 Settings 里可改:正赛 / 排位 各自一个 lead time;练习不推。
        // UserDefaults key: "leadTimeRace" / "leadTimeQualifying"(分钟,Int);默认 30 / 15。
        let raceLead = UserDefaults.standard.object(forKey: "leadTimeRace") as? Int ?? 30
        let qualLead = UserDefaults.standard.object(forKey: "leadTimeQualifying") as? Int ?? 15
        switch kind {
        case .race, .superpoleRace:                 return raceLead
        case .qualifying, .sprint, .sprintShootout: return qualLead
        case .practice:                              return nil
        }
    }

    /// 从全局 SwiftData container fetch 所有"已加日历"的 sessionKey。
    /// 失败/为空时返空 Set,本地通知正常注册(没双重提醒风险)。
    private func fetchAddedCalendarKeys() -> Set<String> {
        let context = PoleApp.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<AddedCalendarEvent>()
        guard let added = try? context.fetch(descriptor) else { return [] }
        return Set(added.map(\.sessionKey))
    }
}
