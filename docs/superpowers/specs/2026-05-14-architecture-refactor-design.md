# 架构 & 性能重构 Spec (借鉴 Ice Cubes 风)

**Status**: Draft — awaiting user review
**Date**: 2026-05-14
**Author**: tiebowen (with Claude Code)
**Branch strategy**: 逐项小 PR,每个独立 merge 到 `main`
**Target style**: Ice Cubes 风(SPM workspace 拆包),但保留 Pole 当前的 0 第三方依赖原则

## 1. 背景与目标

### 1.1 项目当前状态

Pole 是 iOS 26.2 + SwiftUI + SwiftData 的多系列赛车追踪 app,覆盖 F1 / MotoGP / WSSP / Formula E,~19,500 行 Swift,0 第三方依赖,单 Xcode project 结构。

代码体检结果(健康面):
- 全仓 0 个 `try!` / `as!` / 强解包(只 1 处 `fatalError` 是 ModelContainer init 兜底)
- 0 个 `ObservableObject` / `@StateObject`,早已全迁 `@Observable`
- actor + DTO file-private + enum State 模式贯彻较好
- 仅 1 处 `AsyncImage`,基础设施面无明显毒点

### 1.2 痛点(用户反馈)

四个方向用户全部确认是问题:
1. **启动慢 / 列表卡 / 网络慢** — Cold start `KnowledgeImporter` 同步跑、AsyncImage 无 disk 缓存、Timeline "全部"等最慢 client
2. **AI 聊天 / RAG 反馈慢** — Agent maxSteps=10 每步 LLM round-trip,闲聊也走 agent;streaming 渲染顶层数组替换导致重渲
3. **未来扩展难** — 加新系列要改 ≥10 处(CLAUDE.md 已记录),加新 AI tool / 新数据源类似
4. **代码清理需求** — 多个文件 >700 行(ChatView 1470 / ChatViewModel 917 / WSBKClient 877 / LLMClient 836 / Localization 956 / StandingsView 761),边界不清

### 1.3 目标

- **架构**:Ice Cubes 风 SPM workspace,~10 个 Swift Package,主 app target 收窄成 router + tab + intents
- **扩展性**:抽 `MotorsportSeriesService` protocol 收口 4 个 client,加新系列从 13 步降至 ≤ 6 步
- **性能**(用户可感知):Cold start UI 出现 ≤ 700ms、第二次进详情图片 ≤ 100ms、Timeline 首条 200ms 出来、闲聊 AI 首 token ≤ 1.5s
- **稳定**:统一 `PoleError` + `os.Logger`、Task cancellation audit、SwiftData 显式 migration
- **翻译完整性**:4 系列 driver/team 全部有中文映射,fixture test 防回归

### 1.4 非目标(明确不做)

- ❌ 引入第三方依赖(Nuke / Composable Architecture / Alamofire 等)
- ❌ 引入远程 CI(无 GitHub Actions)
- ❌ 重写 SwiftData → GRDB / Core Data
- ❌ 替换 SwiftUI 为 UIKit
- ❌ App Intents 重构(留主 app target,接口稳)
- ❌ Widget / Live Activity 视觉调整(只跨编译打通)
- ❌ 全季度数据 fixture 入仓库(只存最少必要 driver list)

## 2. 目标架构

### 2.1 SPM Workspace 拓扑

```
PoleApp.xcworkspace
├── Pole/                              # 主 app target(~10 files)
│   ├── PoleApp.swift                  # @main + sharedModelContainer + AppEnv 注入
│   ├── ContentView.swift              # 5 Tab + 深链分发
│   ├── Sports/Intents/                # AppIntents 必须在 host (SDK 限制)
│   └── Resources/                     # AppIcon / Assets / Knowledge .md / CircuitMaps SVG
│                                       # (Resources 是否搬入包,各 Phase 视 ROI 决定)
│
├── PoleWidgets/                       # widget extension target
│
└── Packages/
    ├── PoleSharedKit/                 # AppGroup + WidgetSnapshot + SeriesBrand + Router
    │                                   #   主 app + widget 双引
    ├── PoleDesignSystem/              # DS namespace + SeriesTheme + Racing components
    ├── PoleDomain/                    # MotorsportSeries / Sport / League / SportEvent /
    │                                   #   FollowTarget / @Model schemas
    ├── PoleMotorsportKit/             # 4 actor client + MotorsportSeriesService protocol +
    │                                   #   SeasonCache + MotorsportRegistry
    ├── PoleNewsKit/                   # RSSFeedClient + ZXMOTOClient + TeamNewsAggregator
    ├── PoleWeatherKit/                # WttrClient
    ├── PoleAIKit/                     # LLMClient + AgentRuntime + Tools + RAG
    ├── PoleSpeechKit/                 # SpeechService
    ├── PoleUI/                        # GlassHeroHeader + WeatherCard + WikipediaSummarySection
    │                                   #   等共享 view + LoadingViewModel protocol
    └── PoleFeatures/                  # 5 Tab 内容(Motorsport / Chat / Standings / Follow /
                                       #   Settings),Phase 3 决定是否再拆 sub-package
```

### 2.2 关键决策

| 决策点 | 选择 | 原因 |
|---|---|---|
| `PoleFeatures` 是否按 Tab 拆 5 个包 | 暂不(Phase 3 时按 ROI 投票) | Cross-tab 跳转多,Router 兜底前先一包 |
| `PoleDomain` 是否暴露 `@Model` | 是,主 app `import PoleDomain` 后 Schema 仍可见 | 物理隔离 Domain |
| AppIntents 是否进包 | 否,必须 host target | SDK 限制 |
| `RaceAppEntity`(intent 用) 是否进包 | 是,放 `PoleSharedKit`(已是双 target membership) | 已经是双引状态 |
| `Resources/Knowledge` 是否进包 | Phase 2 拆 `PoleAIKit` 时一起搬,Bundle.module 解析 | 解耦 RAG 模块 |

### 2.3 收益对比

| 操作 | 当前 | 重构后 |
|---|---|---|
| 加新系列 | 改 13 处 | 改 ≤ 6 处 |
| 测试 1 个 AI tool | 必须真实拉 4 个网站 | mock `MotorsportSeriesService` 一行 |
| 加新 LLM 模型 | 改 `LLMClient` 836 行 | 新增 `LLMProvider` 实现 |
| Cold build 时间 | 单 project 顺序编译 | Xcode 16 多包并行,预计 -30% |

## 3. 核心 Protocol 抽象

### 3.1 `MotorsportSeriesService` (架构承重墙)

```swift
// PoleMotorsportKit/Sources/Protocols/MotorsportSeriesService.swift
public protocol MotorsportSeriesService: Actor {
    var series: MotorsportSeries { get }

    func fetchRounds(season: Int) async throws -> [AnyMotorsportRound]
    func fetchSessionResults(roundId: String, sessionKind: Session.Kind)
        async throws -> SessionResults
    func fetchDriverStandings(season: Int) async throws -> [DriverStanding]
    func fetchConstructorStandings(season: Int) async throws -> [ConstructorStanding]
    func fetchDriverRoundPoints(driverId: String, season: Int)
        async throws -> [DriverRoundPoints]
}

// 4 个 client 各自实现
public actor JolpicaClient: MotorsportSeriesService { ... }
public actor MotoGPClient: MotorsportSeriesService { ... }
public actor WSBKClient:   MotorsportSeriesService { ... }
public actor FormulaEClient: MotorsportSeriesService { ... }

// 统一注册表
public enum MotorsportRegistry {
    public static func service(for series: MotorsportSeries)
        -> any MotorsportSeriesService {
        switch series {
        case .f1:     return JolpicaClient.shared
        case .motogp: return MotoGPClient.shared
        case .wsbk:   return WSBKClient.shared
        case .fe:     return FormulaEClient.shared
        }
    }
}
```

**跨系列数据 schema 用 enum 关联值统一**:

```swift
public enum DriverStanding {
    case f1(F1DriverStanding)
    case motogp(MotoGPRiderStanding)
    case wsbk(WSSPRiderStanding)
    case fe(FEDriverStanding)

    public var position: Int { ... }
    public var displayName: String { ... }
    public var points: Double { ... }
    public var seriesAccent: Color { ... }
}
```

(沿用 `AnyMotorsportRound` 的现有风格,保持一致。)

**AI tool 重写后**:

```swift
// FindRoundTool / GetSessionResultsTool / GetStandingsTool / GetDriverHistoryTool
let service = MotorsportRegistry.service(for: series)
let rounds = try await service.fetchRounds(season: 2026)
// 不再 switch series 散点
```

### 3.2 其他 protocol

| Protocol | 何时引入 | ROI |
|---|---|---|
| `LLMProvider` (DeepSeek + 未来) | **本期不抽**,DeepSeekProvider actor 就够,protocol 留到真要换模型时 | 低 |
| `NewsSource` (RSS + ZXMOTO + ...) | Phase 3 拆 `PoleNewsKit` 时顺手抽,`TeamNewsAggregator` 持有 `[any NewsSource]` 走 TaskGroup 并行 | 中 |

### 3.3 `LoadingViewModel` Protocol(替代 17 个 VM 的重复 enum State)

```swift
// PoleUI/Sources/ViewModels/LoadingViewModel.swift
public enum LoadingState<Value> {
    case idle, loading, loaded(Value), failed(String)
}

public protocol LoadingViewModel: AnyObject {
    associatedtype Value
    var state: LoadingState<Value> { get set }
    func loadValue() async throws -> Value
}

public extension LoadingViewModel {
    func load() async {
        state = .loading
        do {
            let value = try await loadValue()
            state = .loaded(value)
        } catch is CancellationError {
            // 不切到 failed,保持原态
        } catch {
            state = .failed(L10n.errorMessage(PoleError.from(error)))
        }
    }
}
```

收益:每个 VM 少 30-50 行重复 + 统一 cancellation 处理 + 统一错误本地化。

## 4. 数据流与状态架构

### 4.1 `AppEnv` 全局服务注入

```swift
// PoleSharedKit/Sources/Env/AppEnv.swift
@MainActor
@Observable
public final class AppEnv {
    public let appearance: AppearanceStore
    public let follow: FollowStore
    public let calendar: CalendarService
    public let notifications: NotificationScheduler
    public let router: AppRouter

    public let motorsport: MotorsportServiceRegistry
    public let llm: DeepSeekProvider
    public let knowledge: KnowledgeRetriever
    public let news: TeamNewsAggregator
    public let weather: WttrClient
}

// PoleApp.swift
@main struct PoleApp: App {
    @State private var env = AppEnv.bootstrap()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(env)
                .modelContainer(env.sharedModelContainer)
        }
    }
}

// 调用方
struct ChatView: View {
    @Environment(AppEnv.self) private var env
    @State private var vm: ChatViewModel
}
```

**收益**:
- 测试时 `AppEnv.testing(motorsport: MockRegistry, ...)` 一行 mock
- ViewModel 单点依赖 `AppEnv`,不直接 `import` 各 client 包
- 添加全局服务时不用改 5 个 ViewModel init 签名

### 4.2 `AppRouter` 集中导航(Phase 0 引入)

```swift
// PoleSharedKit/Sources/Router/AppRouter.swift
@MainActor
@Observable
public final class AppRouter {
    public enum Tab: Hashable { case motorsport, standings, chat, follow, settings }
    public enum Destination: Hashable {
        case roundDetail(AnyMotorsportRound)
        case driverDetail(series: MotorsportSeries, driverId: String)
        case teamDetail(series: MotorsportSeries, teamId: String)
    }

    public var selectedTab: Tab = .motorsport
    public var motorsportPath: [Destination] = []
    public var standingsPath: [Destination] = []

    public func deeplink(to destination: Destination) {
        switch destination {
        case .roundDetail:   selectedTab = .motorsport; motorsportPath.append(destination)
        case .driverDetail,
             .teamDetail:    selectedTab = .standings;  standingsPath.append(destination)
        }
    }
}

// ContentView
NavigationStack(path: $env.router.motorsportPath) {
    MotorsportListView()
        .navigationDestination(for: AppRouter.Destination.self) { ... }
}
```

**Live Activity / Notification / Spotlight / AppIntent → 一行**:
`env.router.deeplink(to: .roundDetail(round))`,删 `NotificationCenter` post/subscribe 那套。

### 4.3 拆 `ChatViewModel` (917 行) + `ChatView` (1470 行)

**ChatViewModel 拆 4 块**:

```
ChatViewModel.swift          ~200 行  UI state + 用户输入
AgentStreamCoordinator.swift ~300 行  LLMClient + AgentRuntime 包装(streaming → @Observable)
ChatPersistence.swift        ~150 行  ChatMessage SwiftData 持久化
ChatGreetingProvider.swift   ~100 行  racing/friendly 文案 + TriviaCard
```

**ChatView 拆 6 块**:

```
ChatView.swift               ~400 行  顶层布局
ChatBubbleView.swift         ~200 行  单条消息渲染(user + assistant + tool call)
ChatComposerView.swift       ~250 行  底部输入区(text + voice + tools)
ChatToolCallView.swift       ~250 行  tool call 状态显示
ChatHistoryList.swift        ~200 行  历史会话切换
ChatStreamingCursor.swift    (已独立,保留)
```

## 5. 性能优化(用户可感知)

### 5.1 启动慢 → `KnowledgeImporter` 后台延迟

```swift
// PoleApp.swift
@main struct PoleApp: App {
    @State private var env = AppEnv.bootstrap()   // 不调 KnowledgeImporter

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(env)
                .task {
                    // 启动后 1.5s 在 background 跑
                    await env.knowledge.importIfNeededInBackground()
                }
        }
    }
}

// PoleAIKit/Sources/Knowledge/KnowledgeImporter.swift
public func importIfNeededInBackground() async {
    try? await Task.sleep(for: .seconds(1.5))
    await Task.detached(priority: .background) {
        // 扫描 + embed + 入库
    }.value
}
```

**已知行为**:RAG 第一次提问可能等 importer 跑完(加 progress 状态)。

### 5.2 列表卡 → SVG / Banner Disk Cache

自管 `ImageDiskCache` actor(~120 行,FileManager + URLSession + UIImage):

```swift
// PoleUI/Sources/Cache/ImageDiskCache.swift
public actor ImageDiskCache {
    public static let shared = ImageDiskCache()

    private let cacheDir: URL                    // Caches/PoleImages/
    private let maxBytes: Int = 200_000_000      // 200 MB LRU

    public func image(for url: URL) async -> UIImage?
    public func store(_ image: UIImage, for url: URL) async
    public func svgData(for url: URL) async throws -> Data    // for WKWebView
}

// 替换 AsyncImage → CachedAsyncImage(走 disk cache)
// SVGImageView 改造:先查 disk → loadHTMLString
```

收益:第二次进图片 < 100ms,无网络。

### 5.3 ChatView Streaming 渲染

1. 拆 `ChatBubbleView` 后,每条消息独立 `.id(message.id)`
2. 流式 token 走单条消息的 `@Bindable streamingText` 局部更新,不替换整个 `messages` 数组
3. `LazyVStack` → `List` + `.listRowSeparator(.hidden)` + `.listStyle(.plain)`,让 SwiftUI 内置 diff 接管

### 5.4 网络慢 → TaskGroup yield-as-they-come

```swift
// MotorsportTimelineView "全部" filter
state = .loading
var rounds: [AnyMotorsportRound] = []
await withTaskGroup(of: [AnyMotorsportRound].self) { group in
    for series in MotorsportSeries.allCases {
        group.addTask(priority: .userInitiated) {
            (try? await MotorsportRegistry.service(for: series)
                .fetchRounds(season: 2026)) ?? []
        }
    }
    for await partial in group {
        rounds.append(contentsOf: partial)
        rounds.sort { $0.startDate < $1.startDate }
        state = .loaded(rounds)   // 增量 update UI
    }
}
```

加上 `SeasonCache` stale-while-revalidate:TTL 内立即返回 + 后台刷新。

### 5.5 AI 慢 → Fast Path 绕过 Agent

```swift
public func send(_ message: String) async {
    if !needsAgent(message) {
        // 闲聊/简单问题:直连 LLM,不走 agent maxSteps=10 round-trip
        let stream = await llm.chat(messages: history + [message], tools: nil)
    } else {
        // 涉及 race / standings / driver / calendar 关键词时走 agent
    }
}
```

判定函数 `needsAgent(_ message: String) -> Bool`:
- 中英关键词列表(race / 比赛、standings / 积分、driver / 车手、calendar / 日历、find / 查 / 找 等)
- LLM 系统 prompt 加一句"如果不需要工具就直接回答"作为兜底

### 5.6 预期收益数字

| 场景 | 当前 | 重构后 | 收益 |
|---|---|---|---|
| Cold start UI 出现 | 1-1.5s | 0.5-0.8s | -500ms |
| 第二次进 round detail(图片已缓存) | 800ms-1s | 100ms | -700ms |
| 时间线"全部"出第一条卡 | 等 2s | 200ms | -1.8s |
| 闲聊 AI 回复首 token | 3-5s | 0.8-1.5s | -2s |
| ChatView 长回复滚动 | 偶尔丢帧 | 平滑 | 体感 |

## 6. 稳定性 + 错误处理

### 6.1 `PoleError` 统一

```swift
// PoleSharedKit/Sources/Errors/PoleError.swift
public enum PoleError: LocalizedError {
    case network(URLError)
    case http(statusCode: Int, body: Data?)
    case decoding(any Error, source: String)
    case rateLimited(retryAfter: TimeInterval?)
    case cancelled
    case underlying(any Error)

    public var errorDescription: String? { ... }   // 中英文双语
}

extension PoleError {
    public static func from(_ error: any Error) -> PoleError {
        if let e = error as? PoleError { return e }
        if error is CancellationError { return .cancelled }
        if let e = error as? URLError { return .network(e) }
        return .underlying(error)
    }
}
```

各 client 内部仍可保留具体 enum(`JolpicaError` 等),对外暴露统一 `PoleError`。

### 6.2 `os.Logger` 分类日志

```swift
// PoleSharedKit/Sources/Logging/PoleLog.swift
import os
public enum PoleLog {
    public static let net      = Logger(subsystem: "com.tiebowen.Pole", category: "net")
    public static let agent    = Logger(subsystem: "com.tiebowen.Pole", category: "agent")
    public static let cache    = Logger(subsystem: "com.tiebowen.Pole", category: "cache")
    public static let liveAct  = Logger(subsystem: "com.tiebowen.Pole", category: "liveActivity")
}
```

Console.app + Instruments 按 category 过滤排查问题。

### 6.3 Task Cancellation Audit

**现状**:48 个 `Task {}`,4 个 `Task.checkCancellation`/`Task.detached`。

**audit 范围 + 修复模式**:
- `NotificationScheduler.reschedule(for:)` 持 task handle,新 reschedule 前 cancel 旧的
- `RaceLiveActivityCoordinator` 周期 update Task 在 Activity 结束时 cancel
- `SpeechService` 录音 task 在 VC dismiss 时 cancel

```swift
@MainActor
@Observable
public final class NotificationScheduler {
    private var rescheduleTask: Task<Void, Never>?

    public func reschedule(for series: MotorsportSeries) {
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? Task.checkCancellation()
            // ...
        }
    }
}
```

预估 ~10 处需要改。

### 6.4 Swift 6 Concurrency 预备

1. 验证 `SWIFT_STRICT_CONCURRENCY = complete`(Xcode 26 默认开)warning-free
2. 修剩余 warning(`Sendable`、`@MainActor` 隔离、capture list)
3. **暂不**升 Swift 6 language mode

## 7. 翻译完整性

### 7.1 离线 Audit 测试

```swift
// PoleTests/LocalizationCompletenessTests.swift
import Testing
@testable import PoleDomain
@testable import PoleMotorsportKit

@Test func allF1DriversHaveChineseName() async throws {
    let drivers: [F1DriverDTO] = try loadFixture("f1_drivers_2024_2026.json")
    var missing: [String] = []
    for d in drivers {
        let name = MotorsportNames.driverFullName(raw: d.fullName, series: .f1)
        if name == d.fullName {
            missing.append(d.fullName)
        }
    }
    #expect(missing.isEmpty, "F1 缺中文映射: \(missing.joined(separator: ", "))")
}
// 同理 motogp / wsbk / fe / 各 team
```

### 7.2 Fixture 生成

一次性脚本(不入 build),抓 2024-2026 三季实际名单:
- `PoleTests/Fixtures/f1_drivers_2024_2026.json`
- `PoleTests/Fixtures/motogp_riders_2024_2026.json`
- `PoleTests/Fixtures/wsbk_riders_2024_2026.json`
- `PoleTests/Fixtures/fe_drivers_2024_2026.json`
- 各 teams 同上,4 个 json

### 7.3 补漏

测试报缺失后,批量补 `Localization.swift` 的 `MotorsportNames` 映射表。**预估补 20-50 个**(F1 替补 + MotoGP 卫星队 + WSSP 全 30 人 + FE 替补)。

## 8. 测试策略(轻投入)

**原则**:个人 app,不追覆盖率,只测会改的、影响体验的、易回归的。

| 层 | 覆盖目标 | 工具 |
|---|---|---|
| `MotorsportNames` 翻译表 | 100% mapping 函数(driver/team × 4 系列) | Swift Testing + fixture |
| Domain enum switch 一致性 | 80%(`AnyMotorsportRound` 等) | Swift Testing |
| `MotorsportSeriesService` protocol contract | 100%(mock + 真实 4 实现都跑同一组 test) | Swift Testing |
| 其他 | **不强求** | — |

**Fixture 策略**:saved JSON 不打网络,test 跑 < 2s。

**CI**:本期不引,本地 `xcodebuild test` 通过即可。

## 9. SwiftData Migration 护栏(Phase 4 末)

```swift
// PoleDomain/Sources/SchemaV1.swift
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] = [
        FollowedItem.self, AddedCalendarEvent.self, ChatSession.self, ChatMessage.self,
        DailyTrivia.self, RaceRecap.self, CircuitHighlight.self, KnowledgeChunk.self
    ]
}

public enum PoleMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    public static var stages: [MigrationStage] = []
}
```

破坏性升级时加 `.lightweight(...)` 或 `.custom(...)` 迁移 stage,保护用户数据。

## 10. PR 路线图

| PR | Phase | 内容 | 风险 | 预估改动 |
|---:|---|---|---|---:|
| **PR1** | Phase 0 | SPM workspace 化:拆 `PoleSharedKit` + `PoleDesignSystem`,引入 `AppRouter` + `AppEnv` 骨架。验证 widget 跨编、Preview、build/test 走通。Router 接管深链。 | 高 | ~30 文件移动 + 5 文件新增 |
| **PR2** | Phase 1 | 拆 `PoleDomain` + `PoleMotorsportKit`:4 个 client 实现 `MotorsportSeriesService`、`LoadingViewModel` protocol、`PoleError` + `os.Logger` 引入。 | 中 | ~25 文件移动 + 10 文件新增/改 |
| **PR3** | Phase 1 收尾 | 重写 5 个 AI tool 用 `MotorsportRegistry`,删 `switch series` 散点;Standings/Timeline 用 registry 收口。 | 中 | ~12 文件改 |
| **PR4** | Phase 2 | 拆 `PoleAIKit`(LLMClient + Agent + RAG)。`ChatViewModel` → 4 个子类,`ChatView` → 5 个子 View。Agent fast-path。 | 中 | ~10 文件移动 + 拆出 8 文件 |
| **PR5** | Phase 3 | 拆 `PoleUI` + `PoleNewsKit` + `PoleWeatherKit` + `PoleSpeechKit` + `PoleFeatures`(一个大包先)。 | 低 | ~40 文件移动 |
| **PR6** | Phase 4a | **性能**:KnowledgeImporter 延迟 + `ImageDiskCache` + Timeline TaskGroup yield-as-they-come + ChatView streaming 优化。 | 低 | ~8 文件改 + 1 包新增 |
| **PR7** | Phase 4b | **稳定**:Task cancellation audit(~10 处)、SwiftData `VersionedSchema` 显式 migration、Swift 6 strict concurrency 验证、翻译完整性 + fixture test。 | 低 | ~15 文件小改 + 1 fixture 目录 |

### 10.1 每个 PR 的"完成定义"

合并前必须:
- ✅ `xcodebuild build` 主 app + widget extension 均成功
- ✅ Happy path 手测一遍(开 app → 各 Tab 切 → 进详情 → AI 对话一次)
- ✅ DerivedData 清空后 cold build 也成功
- ✅ Widget snapshot 写入正常(关注的下场比赛在主屏 widget 显示)
- ✅ Commit 信息清晰

### 10.2 PR1 风险细节(最危险一步,单独展开)

**变更内容**:
1. 新建 `Packages/PoleSharedKit/Package.swift`,把 `Pole/Shared/*.swift` 全移过去
2. 新建 `Packages/PoleDesignSystem/Package.swift`,把 `Pole/Theme/*.swift` 全移过去
3. 修主 app + widget extension 引用,两 target 各加 `.package(path: "Packages/PoleSharedKit")` 等
4. 改 .xcodeproj 文件夹结构(用 Xcode UI 操作,不手编 pbxproj)
5. 新建 `PoleRouter` + `AppEnv`,接管深链(原 NotificationCenter 保留并行,验证后下 PR 再删)

**回滚策略**:PR1 整 commit revert 即可。无 SwiftData schema 改动,无数据风险。

**已知坑点**:
- `Pole/Shared/RaceLiveActivityAttributes.swift` 当前手动双 target membership → 搬到包后改 `import PoleSharedKit`,两 target 各加一次依赖,Xcode 不自动推
- `Theme/DesignSystem.swift` 内 `DS.Palette` 用 dynamic `UIColor` → 验证 `import SwiftUI` + `import UIKit` 在 package context 都能 resolve
- `Resources/Knowledge/` 暂留主 app target,Phase 2 拆 `PoleAIKit` 一起搬

### 10.3 风险总览

| 风险 | 等级 | 缓解 |
|---|---|---|
| Widget extension 跨包编译失败 | 高(影响 PR1) | PR1 第一步就是 build widget,失败立刻回退 |
| Resources(`.md`/SVG)搬包后 `Bundle.module` 路径不通 | 中 | 用 `.process(...)` / `.copy(...)` 资源声明,本地实测 |
| SwiftData ModelContainer 在包里看不到全部 Schema | 中 | `@Model` 都放 `PoleDomain`,主 app `import PoleDomain` 即可 |
| AppIntents 在包里编译失败 | 已知 | 不动,intent 全部留主 app target |
| SourceKit-LSP 翻新 DerivedData 后短暂全红 | 低 | 已知,cli build 是 ground truth |
| 中途用户提新功能 | 中 | 每个 PR 独立可 merge,新功能插队进单独 PR,不阻断重构 |

## 11. 终止条件

7 个 PR 全 merge 后,验证项:
1. Xcode workspace 10 个 SPM package,各自独立可单测
2. 加新系列 checklist 从 13 步降到 ≤ 6 步(同步更新 CLAUDE.md)
3. Cold start UI 出现时间 ≤ 700ms(measure with `os_signpost`)
4. 4 个系列的 driver / team 列表里 0 个未翻译条目(fixture test 通过)
5. 全仓 0 `try!` / `as!`(已是),0 个未持 handle 的长存 Task

## 12. 决策日志(本次 brainstorm 已 confirm)

| 决策点 | 选择 | Section |
|---|---|---|
| 子项目优先级 | 架构 + 性能重构优先,翻译完整性归入 Phase 4b | 1 |
| 节奏 | 逐项小 PR | 10 |
| 参考风格 | Ice Cubes 风(SPM workspace) | 2 |
| 拆包粒度 | 渐进 Phase 0→4(B 方案) | 10 |
| `LoadingViewModel` | Protocol 版 | 3.3 |
| `AppRouter` | Phase 0 同步做 | 4.2 |
| `LLMProvider` 抽 | 本期不做 | 3.2 |
| 测试覆盖 | 只做翻译完整性 + Domain switch 一致性 | 8 |
| SwiftData migration | Phase 4 末顺手做 | 9 |
