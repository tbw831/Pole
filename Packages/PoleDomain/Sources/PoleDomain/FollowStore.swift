import Foundation
import SwiftData

/// SwiftData 关注操作的薄封装。所有方法在 MainActor 上跑，因为 ModelContext
/// 不是 Sendable，View 层调用它最自然。
@MainActor
public final class FollowStore {
    public let context: ModelContext

    /// 关注列表变化时主 app 注入的回调（譬如 WidgetSnapshotBuilder.refresh(force:true)）。
    /// PoleDomain 不依赖 widget / 上层 feature，所以以 hook 形式向外暴露。
    /// 由 PoleApp 在启动时设置一次。
    public static var onChange: (@MainActor () -> Void)?

    public init(context: ModelContext) {
        self.context = context
    }

    public func contains(_ target: FollowTarget) -> Bool {
        let key = FollowedItem.makeKey(target)
        let descriptor = FetchDescriptor<FollowedItem>(predicate: #Predicate { $0.key == key })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    public func toggle(_ target: FollowTarget, displayName: String) {
        let key = FollowedItem.makeKey(target)
        let descriptor = FetchDescriptor<FollowedItem>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        } else {
            context.insert(FollowedItem(target: target, displayName: displayName))
        }
        try? context.save()
        Self.onChange?()
    }

    public func all() -> [FollowedItem] {
        let descriptor = FetchDescriptor<FollowedItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
