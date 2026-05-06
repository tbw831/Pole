import Foundation
import SwiftData

/// SwiftData 关注操作的薄封装。所有方法在 MainActor 上跑，因为 ModelContext
/// 不是 Sendable，View 层调用它最自然。
@MainActor
final class FollowStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func contains(_ target: FollowTarget) -> Bool {
        let key = FollowedItem.makeKey(target)
        let descriptor = FetchDescriptor<FollowedItem>(predicate: #Predicate { $0.key == key })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func toggle(_ target: FollowTarget, displayName: String) {
        let key = FollowedItem.makeKey(target)
        let descriptor = FetchDescriptor<FollowedItem>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        } else {
            context.insert(FollowedItem(target: target, displayName: displayName))
        }
        try? context.save()
        WidgetSnapshotBuilder.refresh(force: true)
    }

    func all() -> [FollowedItem] {
        let descriptor = FetchDescriptor<FollowedItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
