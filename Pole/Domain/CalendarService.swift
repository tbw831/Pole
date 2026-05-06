import Foundation
import EventKit

/// EventKit 写入封装——每个 session 独立加日历事件,iOS 17+ 用 write-only 权限。
/// 写入用户 default calendar,同时挂个 -30min 提醒。
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    var authStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            return try await store.requestWriteOnlyAccessToEvents()
        } catch {
            return false
        }
    }

    /// 创建 event,返回 EKEvent identifier(成功) 或 nil(失败/拒绝)。
    func addEvent(title: String, start: Date, end: Date, notes: String? = nil) async -> String? {
        guard await ensureAccess() else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        // 系统级提前 30 分钟提醒——日历 app 自带的 alarm,不依赖 app 本地通知
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// 移除已添加的 event(用 identifier 在 EventStore 找)。
    @discardableResult
    func removeEvent(identifier: String) async -> Bool {
        guard await ensureAccess() else { return false }
        guard let event = store.event(withIdentifier: identifier) else { return false }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    private func ensureAccess() async -> Bool {
        switch authStatus {
        case .fullAccess, .writeOnly, .authorized:
            return true
        case .notDetermined:
            return await requestAccess()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
