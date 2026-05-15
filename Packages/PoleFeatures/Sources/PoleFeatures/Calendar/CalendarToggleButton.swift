import SwiftUI
import SwiftData
import PoleDomain

/// 单个 session 的"加入日历"开关。
/// 用 `sessionKey`(formula 见各 detail view 调用方)做唯一键,SwiftData @Query 监听同 key
/// 来决定 button 显示 + / ✓。点击 toggle 写入或移除苹果日历事件。
public struct CalendarToggleButton: View {
    let sessionKey: String
    let title: String
    let start: Date
    let end: Date
    let notes: String?

    @Environment(\.modelContext) private var context
    @Query private var matches: [AddedCalendarEvent]

    public init(sessionKey: String, title: String, start: Date, end: Date, notes: String? = nil) {
        self.sessionKey = sessionKey
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        _matches = Query(filter: #Predicate<AddedCalendarEvent> { $0.sessionKey == sessionKey })
    }

    private var added: AddedCalendarEvent? { matches.first }

    public var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: added != nil ? "calendar.badge.checkmark" : "calendar.badge.plus")
                .foregroundStyle(added != nil ? .green : .accentColor)
                .font(.body)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(added != nil
                            ? L10n.t(zh: "已加入日历", en: "Added to Calendar")
                            : L10n.t(zh: "加入日历", en: "Add to Calendar"))
        .sensoryFeedback(.success, trigger: added != nil)
        .contentTransition(.symbolEffect(.replace))
    }

    private func toggle() async {
        if let existing = added {
            _ = await CalendarService.shared.removeEvent(identifier: existing.ekIdentifier)
            context.delete(existing)
            try? context.save()
        } else {
            if let id = await CalendarService.shared.addEvent(
                title: title,
                start: start,
                end: end,
                notes: notes
            ) {
                context.insert(AddedCalendarEvent(sessionKey: sessionKey, ekIdentifier: id))
                try? context.save()
            }
        }
    }
}

// MARK: - Helpers
// `Session.defaultDuration` 已迁移到 PoleDomain 的 Session.swift,所有调用方共用。
