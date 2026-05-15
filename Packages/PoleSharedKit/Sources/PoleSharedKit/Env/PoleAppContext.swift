import Foundation
import SwiftData

/// 主 app 启动时注入的全局上下文。
///
/// 历史:`WidgetSnapshotBuilder` / `NotificationScheduler` 之类的 MainActor 单例
/// 需要直接读 SwiftData `ModelContext`(因为它们不是 SwiftUI View,拿不到
/// `@Environment(\.modelContext)`)。最早版本直接读 `PoleApp.sharedModelContainer`,
/// 但 PoleFeatures 拆 SPM 后包内不能再引用主 app 类型。
///
/// 这里给出一个静态注入点:主 app `@main` bootstrap 时调
/// `PoleAppContext.shared.modelContainer = container`,包内单例从这里读。
///
/// **注意**:`ModelContainer` 在主线程访问安全(`@unchecked Sendable`),静态注入合规。
/// 若赋值前包内代码先访问会 crash —— 这要求 bootstrap 必须早于任何包内代码读取。
@MainActor
public final class PoleAppContext {
    public static let shared = PoleAppContext()

    /// 主 app `@main` 注入。包内代码读这个拿 `mainContext`。
    /// 注入前不要访问 `requireModelContainer()` —— 会 fatalError。
    public var modelContainer: ModelContainer?

    private init() {}

    /// 强制取 container,未注入时 fatalError(开发期 fail-fast)。
    public func requireModelContainer() -> ModelContainer {
        guard let c = modelContainer else {
            fatalError("PoleAppContext.modelContainer not set — 主 app 必须在 bootstrap 时注入 sharedModelContainer")
        }
        return c
    }
}
