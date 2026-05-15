import SwiftUI
import SwiftData
import PoleSharedKit
import PoleDomain

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
                    // 启动后异步刷新 widget snapshot,不阻塞 UI。
                    WidgetSnapshotBuilder.refresh()
                    // RAG 知识库懒导入:首次启动 embed 全部 chunk(~10-20s),已导入则直接 return。
                    // KnowledgeImporter 内部 actor 串行,真正耗时的 embed 在 EmbeddingService actor
                    // 不在 MainActor,所以 await 不阻 UI(只是 yield 给 SwiftUI 继续渲染)。
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
