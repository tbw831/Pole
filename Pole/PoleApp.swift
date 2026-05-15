import SwiftUI
import SwiftData
import PoleSharedKit
import PoleDomain
import PoleAIKit
import PoleFeatures

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
        // 用 PoleMigrationPlan(SchemaV1)而不是 inline Schema(...) —
        // 后续破坏性 schema 变动可以加 MigrationStage 而不需要改这里的 init。
        let schema = Schema(versionedSchema: SchemaV1.self)
        // 第一次试持久化
        let persistent = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let c = try? ModelContainer(
            for: schema,
            migrationPlan: PoleMigrationPlan.self,
            configurations: persistent
        ) {
            return c
        }
        // schema 升级失败 → 退到 in-memory,标记 flag,不闪退
        Self.containerInitFailed = true
        let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let c = try? ModelContainer(
            for: schema,
            migrationPlan: PoleMigrationPlan.self,
            configurations: inMemory
        ) {
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
                    // PoleFeatures 包内的 NotificationScheduler / WidgetSnapshotBuilder 通过
                    // PoleAppContext 读 SwiftData container(包不能引用主 app `PoleApp.sharedModelContainer`)。
                    PoleAppContext.shared.modelContainer = Self.sharedModelContainer
                    // PoleDomain.FollowStore 是 package，不依赖主 app 的 WidgetSnapshotBuilder；
                    // 这里把"关注列表变更"和"widget snapshot 刷新"挂起来。
                    FollowStore.onChange = { WidgetSnapshotBuilder.refresh(force: true) }
                    // 启动后异步刷新 widget snapshot,不阻塞 UI。
                    WidgetSnapshotBuilder.refresh()
                    // Live Activity 启停跨 target(widget extension),包不能直接调
                    // RaceLiveActivityCoordinator —— 改成 NotificationCenter 解耦。
                    subscribeLiveActivityBridges()
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

    /// 订阅 PoleFeatures 包发出的 Live Activity 启停通知。
    /// 包不能直接 import 主 app 的 `RaceLiveActivityCoordinator` / `RaceAppEntity`(跨 target with widget),
    /// 用通知解耦。
    @MainActor
    private func subscribeLiveActivityBridges() {
        NotificationCenter.default.addObserver(
            forName: .stopAllLiveActivities, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await RaceLiveActivityCoordinator.shared.stopAll()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .startLiveActivityForRace, object: nil, queue: .main
        ) { note in
            guard let info = note.userInfo,
                  let raceId = info["raceId"] as? String,
                  let seriesRaw = info["seriesRaw"] as? String,
                  let displayName = info["displayName"] as? String,
                  let subtitle = info["subtitle"] as? String,
                  let startDate = info["startDate"] as? Date else { return }
            Task { @MainActor in
                let entity = RaceAppEntity(
                    id: raceId,
                    seriesRaw: seriesRaw,
                    displayName: displayName,
                    subtitle: subtitle,
                    startDate: startDate
                )
                _ = RaceLiveActivityCoordinator.shared.start(from: entity)
            }
        }
    }
}
