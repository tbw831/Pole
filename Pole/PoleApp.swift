import SwiftUI
import SwiftData
import PoleSharedKit
import PoleDomain
import PoleAIKit

@main
struct PoleApp: App {
    /// 全局 SwiftData container — 也暴露给非 SwiftUI 代码(如 NotificationScheduler 单例)
    /// 通过 `PoleApp.sharedModelContainer` 拿 mainContext。
    /// init 失败 fallback in-memory 避免上线后 schema 升级闪退;失败时一次性记录,UI 后续可读
    /// `containerInitFailed` 提示用户"本地数据迁移失败,已切换临时存储"。
    static let sharedModelContainer: ModelContainer = makeContainer()
    static private(set) var containerInitFailed: Bool = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var appearance = AppearanceStore.shared
    @State private var env = AppEnv.bootstrap()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            FollowedItem.self,
            AddedCalendarEvent.self,
            ChatSession.self,
            ChatMessage.self,
            DailyTrivia.self,
            RaceRecap.self,
            CircuitHighlight.self,
            KnowledgeChunk.self,    // RAG 知识库 chunk(向量+原文)
        ])
        // 第一次试持久化
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let c = try? ModelContainer(for: schema, configurations: [persistent]) {
            return c
        }
        // schema 升级失败 → 退到 in-memory,标记 flag,不闪退
        Self.containerInitFailed = true
        let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let c = try? ModelContainer(for: schema, configurations: [inMemory]) {
            return c
        }
        // 连 in-memory 都建不了那真没救了
        fatalError("Could not create ModelContainer (both persistent and in-memory failed)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.current.colorScheme)
                .environment(env)
                .environment(appearance)
                .task {
                    // PoleDomain.FollowStore 是 package，不依赖主 app 的 WidgetSnapshotBuilder；
                    // 这里把"关注列表变更"和"widget snapshot 刷新"挂起来。
                    FollowStore.onChange = { WidgetSnapshotBuilder.refresh(force: true) }
                    // 启动后异步刷新 widget snapshot,不阻塞 UI。
                    WidgetSnapshotBuilder.refresh()
                    // RAG 知识库延迟到 background,避免阻塞首屏(spec section 5.1)。
                    // 1.5s 让 UI 先稳;低优先级让 importer 不抢主线程渲染资源。
                    // 仍走 MainActor task(ModelContext 不 Sendable),只是 sleep 让出首屏。
                    try? await Task.sleep(for: .seconds(1.5))
                    await KnowledgeImporter.importIfNeeded(
                        context: Self.sharedModelContainer.mainContext
                    )
                }
        }
        .modelContainer(Self.sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // app 切到前台时也刷新一次(用户可能已经过了好几小时)。
            if newPhase == .active {
                WidgetSnapshotBuilder.refresh()
            }
        }
    }
}
