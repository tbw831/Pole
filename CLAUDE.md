# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> 本文是项目主指南：架构骨架 + 容易踩坑的具体规则 + 活的工具引用。
> Widget extension 一次性接入步骤详见 `PoleWidgets/SETUP.md`，真机部署见 `docs/deploy.md`。

## 项目概览

**Pole** — iOS 赛车多系列追踪 app（SwiftUI + SwiftData，目标 **iOS 26.2**，Swift 5.0，Bundle ID `com.tiebowen.Pole`，App Group `group.com.tiebowen.Pole`，作者署名 ByteDance）。

覆盖 **F1 / MotoGP / WSSP（WorldSBK 中量级 class）/ Formula E** 四个系列。能力面：赛程 + 积分榜 + 车手详情、本地赛前通知、系统日历写入、天气、新闻聚合（RSS + ZXMOTO 中文站）、DeepSeek LLM tool calling 助手、关注系统、每日冷知识、赛后 AI 复盘、主屏 Widget + 灵动岛 Live Activity、Siri Shortcuts、语音输入。

`Sport` 枚举留了 `basketball / football` 占位但当前**未实现**，`MotorsportSeries` 才是真正在用的"系列"维度。

## 构建与测试

**Linux 上无法构建**（仓库被 checkout 到 Linux 仅供编辑；`build-errors.txt` 已记录 `xcode-select` 报错）。所有 build / test 必须在装 Xcode 26+ 的 Mac 上执行：

```bash
# 全量构建（iOS 模拟器）
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' build

# 单元测试（Swift Testing 框架，import Testing / @Test / #expect — 不是 XCTest）
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test

# 跑单个 Swift Testing 用例
xcodebuild test -project Pole.xcodeproj -scheme Pole \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' \
  -only-testing:PoleTests/PoleTests/example
```

`PoleTests/` 用 Swift Testing；`PoleUITests/` 仍用 XCTest。Linux 端被要求构建时，先告知然后请用户在 Mac 验证。

## 架构（四层）

```
Domain（跨系列抽象，无 wire 格式）
  → Sports（按数据源分目录的 Model + actor Client，无 SwiftUI）
    → Features（按系列分目录的 SwiftUI View + ViewModel，不直接发请求）
      → Theme（DesignSystem token + 系列品牌色）
```

跨层泄露要避免：Domain 不知 JSON / HTTP；Sports 不知 SwiftUI；Features 调 actor client 而不是直接 URLSession。

### Domain — `Pole/Domain/`

跨系列抽象。**新增运动只在此层加 `Sport` case**；**新增赛车系列在 `MotorsportSeries` 加 case**。

核心类型：
- `Sport`（enum，目前只有 `motorsport` 真正接入）
- `MotorsportSeries`（enum：`f1 / motogp / wssp / fe`）
- `League`（赛季容器，`id` 为稳定 slug 如 `f1-2025`）
- `SportEvent`（protocol，**故意不继承 `Identifiable`**，避免 SwiftUI 默认 `@MainActor` 隔离与 Swift 6 `Sendable` 冲突；具体类型只要有 `id` 属性即自动满足 `Identifiable`）
- `MotorsportEvent`（protocol，提供 `currentStatus` 实时计算 + `mainRace`）
- `AnyMotorsportRound`（enum 包装四 case，给 SwiftUI `ForEach` / `NavigationLink` 用，不能用 existential `any MotorsportEvent`）
- `FollowTarget`（关注三粒度 `athlete / team / league`，`series` 字段对齐 `League.series`）

**SwiftData @Model（共 8 个，新增 `@Model` 必须同步加进 `PoleApp.sharedModelContainer` 的 `Schema(...)` 数组，否则启动 fatalError）**：
`FollowedItem` / `AddedCalendarEvent` / `ChatSession` / `ChatMessage` / `DailyTrivia` / `RaceRecap` / `CircuitHighlight` / `KnowledgeChunk`（RAG 知识库 chunk + 向量）。

容器 init 走 **三段 fallback**：persistent 失败 → in-memory（标记 `containerInitFailed=true`，UI 后续可读取作提示）→ 仍失败才 `fatalError`。Schema 升级失败时不会闪退，但用户的关注/历史会丢一次会话。

服务：
- `FollowStore` — `@MainActor` 包 `ModelContext`（`ModelContext` 不 `Sendable`，放 MainActor 最自然）
- `CalendarService` — EventKit，iOS 17+ 用 `requestWriteOnlyAccessToEvents`，写入自动加 `-30min EKAlarm`
- `L10n.current` 读 `UserDefaults["languageMode"]`（`zh / en / auto`），`L10n.t(zh:en:)` 二选一短串入口；`Localization` 提供 series/race/country code 映射

**所有用户可见字符串走 `L10n.t` 或 `Localization.*`，禁止硬编码中文/英文在 View body**。错误提示双语。

### Sports — `Pole/Sports/`

| 子目录 | 功能 | 数据源 / 实现 |
|---|---|---|
| `Motorsport/F1/` | F1 赛程 + 结果 | `JolpicaClient`（actor），Ergast 兼容 jolpica，免认证 |
| `Motorsport/MotoGP/` | MotoGP | `MotoGPClient`（actor），Pulselive |
| `Motorsport/WSBK/` | WSSP（class） | `WSBKClient`（actor），worldsbk.com 官方 |
| `Motorsport/FormulaE/` | FE | `FormulaEClient`（actor），Pulselive 不同 endpoint，DTO 与 MotoGP 不通用 |
| `Motorsport/SeasonCache.swift` | 通用 TTL 缓存 | 4 个 client 共用，避免多页面重复 fetch |
| `Weather/` | 天气卡 | `WttrClient`（wttr.in `format=j1`，免 key，UA 必设 Mozilla，3 天范围；超出返 nil） |
| `News/` | 新闻聚合 | `RSSFeedClient`（用 `NSRegularExpression` 解析 `<item>`，绕过 `XMLParser` delegate，CDATA 自动剥离）+ `ZXMOTOClient` 中文站 + `TeamNewsAggregator`（按 `TeamNewsKeywords` 归类） |
| `AI/` | LLM 助手 | `LLMClient`（actor，DeepSeek `deepseek-chat`，OpenAI 兼容，`thinking: .disabled`）+ `Agent/AgentRuntime`（流式 tool calling，maxSteps 10，`withTaskGroup` 并行执行 tool，支持 `Task.checkCancellation`）+ `Agent/Tools/`（7 个：`FindRound` / `GetSessionResults` / `GetStandings` / `GetDriverHistory` / `ListFollowed` / `AddToCalendar` / `RetrieveKnowledge`） |
| `Domain/Knowledge/` | RAG 知识库 | **不需要向量数据库** — 500-5000 chunk 规模本地 SwiftData 存 `KnowledgeChunk`（text + Float vector blob）+ 客户端全量 cosine ~5-30ms。`EmbeddingService`（actor，包 Apple `NLContextualEmbedding` iOS 17+，多语言）+ `KnowledgeRetriever`（top-K 语义检索）+ `KnowledgeImporter`（启动时扫 `Resources/Knowledge/**/*.md` 切 chunk → embed → 入库）。Markdown 按 `# 一级标题` 切 chunk，frontmatter `series:`/`topic:` 标签或文件路径自动推断。**Knowledge 文件夹必须以 Folder Reference (蓝色) 加入 Xcode**，不然 subdirectory lookup 失效。|
| `Voice/` | 语音输入 | `SpeechService`（Speech + AVAudioEngine；on-device recognition；中英跟 `L10n.effective`） |
| `Intents/` | App Intents | `OpenRaceDetailIntent`（Live Activity / 灵动岛跳转）+ `StopLiveActivityIntent` + `PoleShortcuts`（Siri / Spotlight，每个 phrase 含 `\(.applicationName)` 防歧义） |
| `SharedURLSession.swift` | 共享 URLSession | 50MB RAM + 200MB disk URLCache（`URLSession.shared` config 只读改不了 cache，故另立） |

**新增数据源必须遵循的分层规范**：
1. Domain Model 实现 `MotorsportEvent`，`public nonisolated struct`，`Sendable + Codable + Hashable`
2. API client 用 `public actor`
3. **DTO 严格 file-private**——wire format（如 Ergast"所有数字皆字符串"）封装在 `private struct RaceDTO` 内，只对外暴露 `toDomain()` 后的 Domain 类型，转换失败 `return nil` 静默丢弃，不抛异常阻断整条数据流
4. 错误用专属 `LocalizedError` enum（参考 `JolpicaError`：`network(Error) / invalidResponse(Int) / decoding(Error)`，每 case 中文 `errorDescription`）
5. 缓存走 `SeasonCache<Value>`（client actor 内持有）

**所有 7 个 tool 都支持 4 系列**（`f1/motogp/wsbk/fe`）。`FindRound` 多支持 `when="season_overview"` 一次返赛季总览（避免 LLM by_round 死循环 enumerate 总站数）。`RetrieveKnowledge` 是 RAG 入口（语义搜本地知识库，不查实时数据）。

### Features — `Pole/Features/`

每个系列一个子目录，4 件套：`RoundListView` / `RoundDetailView` / `SessionResultsView` / `DriverDetailView`。

| 子目录 | 内容 |
|---|---|
| `Motorsport/` | `MotorsportListView`（segmented picker：全部 / F1 / MotoGP / WSBK / FE） + `MotorsportTimelineView`（"全部"用 `AnyMotorsportRound` 跨系列时间线） |
| `F1/` `MotoGP/` `WSBK/` `FE/` | 各系列四件套 + ViewModel |
| `Standings/` | 跨系列积分榜 |
| `Chat/` | `ChatView` + `ChatViewModel`（agent 流式事件 → SwiftData `ChatMessage` 持久化）+ `ChatStore` + `TriviaCard`（每日冷知识）+ `ChatHistoryView` |
| `Follow/` | `FollowFeedView` + `FollowToggleButton` |
| `News/` | `TeamDetailView`（车队名 → keywords 拉 RSS） |
| `Calendar/` | `CalendarToggleButton`（写入后 ID 持久化到 `AddedCalendarEvent` 避重复） |
| `Notifications/` | `NotificationScheduler`（`@MainActor` 单例） |
| `Settings/` | 语言切换、通知开关、Live Activity 开关 |
| `LiveActivity/` | `RaceLiveActivityCoordinator`（Activity 启停 + 周期 update）+ `RaceLiveActivityAttributes`（**双 target 编译**：主 app + PoleWidgets） |
| `Widget/` | `WidgetSnapshotBuilder`（主 app 把"下场比赛"写到 App Group JSON，widget 读） |
| `Common/` | `MotorsportCard` / `WeatherCard` / `RaceRecapSection` / `WikipediaSummarySection` / `GlassHeroHeader` / `StatusBadge` / `SeriesGradientBar` / `SVGImageView` / `SafariView` |

**ViewModel 规范**（不是协商，是约束）：
- 一律 `@MainActor @Observable final class`（不是旧 `ObservableObject`）
- 状态走 `enum State { case idle, loading, loaded(...), failed(message:) }`
- View 持有：`@State private var viewModel = …`（不是 `@StateObject`）
- 加载入口：`.task { if case .idle = viewModel.state { await viewModel.load() } }`，下拉走 `.refreshable`
- `@ViewBuilder` switch 三分支必须全覆盖，`failed` 必须有"重试"按钮

**通知策略（hardcode）**：`race / superpoleRace` 提前 30min；`qualifying / sprint / sprintShootout` 提前 15min；`practice` 不推。`reschedule(for:)` 每次先 remove 全部 `session:*` identifier 再重排。

### Theme — `Pole/Theme/`

- **`DesignSystem.swift`** — 全局视觉 token 系统：`DS.Spacing` / `DS.Radius` / `DS.Palette` / `DS.Font` / `DS.Shadow` / `DS.Motion` + 便捷 `ViewModifier`（`dsAIBubble()` / `dsToolCard()` / `dsDetailList()` / `dsListCard()`）+ 复用组件 `SegmentedPillPicker` / `AIAvatar` / `StreamingCursor`。**用 `DS` token，不要写魔法数字**。
- **`SeriesTheme.swift`** — `MotorsportSeries.brandColor` + `brandGradient`（F1 红 `#E10600` / MotoGP 橙 `#FF6B00` / WSBK 绿 `#009F4D` / FE 青 `#00C8C4`）+ 全局非系列色 `BrandPalette`（`appAccent` 紫 `#7C4DFF`、`aiGradient`、四个 `EventStatus` 状态色）。**用品牌色而不是新建颜色**——加新系列同步加 case。

## 入口与生命周期

- **`PoleApp.swift`**：`@main`，`sharedModelContainer` 注入 8 个 `@Model`（init 失败 fallback in-memory，标 `containerInitFailed`，不闪退）。`scenePhase` 切到 `.active` 时调 `WidgetSnapshotBuilder.refresh()` 刷主屏 widget JSON。
- **`ContentView.swift`**：5 Tab（赛车 / 积分榜 / AI / 关注 / 设置），用 iOS 26 系统 `TabView` + `.tabBarMinimizeBehavior(.onScrollDown)`（系统 Liquid Glass tab bar 滚动收缩）。首次启动若通知权限 `notDetermined` 自动弹一次系统授权（用户可拒）。切到 AI tab 通过 `NotificationCenter` post `.resetChatToStarter` 重置会话。Live Activity / 灵动岛点击触发 `OpenRaceDetailIntent` post `.openRaceDetail`，ContentView 切到赛车 tab + 跳详情。

## Widget Extension（`PoleWidgets/`）

代码已写好，**Extension target 尚未在 Xcode 项目中添加**。Mac 端需手动一次性接入（详见 `PoleWidgets/SETUP.md`）：
1. File → New → Target → Widget Extension（**勾 Include Live Activity**），Product Name `PoleWidgets`
2. 删 Xcode 模板 .swift（保留仓库版 `PoleWidgetsBundle.swift`）
3. 把 `PoleWidgets/` 下文件挂到 PoleWidgets target（NextRace 主屏 widget + Live Activity widget）
4. **跨 target 双勾 Target Membership**（主 app + PoleWidgets）：`Pole/Shared/*`（`AppGroup` / `WidgetSnapshot` / `WidgetSnapshotStore` / `SeriesBrand`）+ `Features/LiveActivity/RaceLiveActivityAttributes.swift` + `Sports/Intents/AppIntents.swift` + `Sports/Intents/RaceAppEntity.swift`
5. 两个 target 都加 App Group capability `group.com.tiebowen.Pole`
6. 主 app 已有 `INFOPLIST_KEY_NSSupportsLiveActivities = YES`

主屏 widget 提供 small / medium / large + accessoryRectangular / Circular / Inline 6 种尺寸。

## 安全 / 密钥

- **DeepSeek API Key** 二级查找：`Info.plist[DSAPIKey]`（推荐 release 路径，xcconfig 通过 `$(DS_API_KEY)` 注入，不入仓库）→ 环境变量 `DS_API_KEY`（本地开发推荐，Xcode scheme env vars，user-specific 自带 gitignore via `xcuserdata/`）。**绝不**在源码硬编码 fallback——commit 进库 / binary reverse 都会泄露。具体本地配置见 `docs/api-key-setup.md`。生产必须改走自有代理服务把 key 留服务端。
- 其他赛事数据源均免认证。

## 新增赛车系列：实际 ≥10 处改动

> 早期想法是"只在 `MotorsportSeries` 加 case"，**实际不是**。完整 13 条改动清单：

1. `Domain/Motorsport/MotorsportSeries.swift` — 加 case + `displayName` / `shortName`
2. `Domain/Motorsport/AnyMotorsportRound.swift` — 加 case + 6 个 switch 分支
3. `Theme/SeriesTheme.swift` — 加 `brandColor` + `brandGradient` case
4. `Sports/Motorsport/<NewSeries>/` — 整套 client actor + Models + DTO
5. `Features/<NewSeries>/` — RoundListView + RoundDetailView + SessionResultsView + ViewModel
6. `Features/Motorsport/MotorsportListView.Filter` enum 加 case + segmented picker 分支
7. `Features/Motorsport/MotorsportTimelineView.swift` — `async-let` 多拉一个，`row(for:)` switch 加 case
8. `Features/Standings/StandingsView` — `switch series` 加分支 + `<NewSeries>StandingsContent`
9. `Domain/Localization.swift` — race name mapping 函数
10. `Domain/MotorsportNames.swift` 风格 — driver / team mapping 函数
11. AI 工具（5 个）：`FindRound` / `GetSessionResults` / `GetStandings` / `GetDriverHistory` / `AddToCalendar` — 参数 enum 加 series id + 实现分支
12. `ChatViewModel.systemPrompt` — 中英 prompt 列表加新系列名
13. `PoleApp.swift` — 如果新系列加了 SwiftData `@Model`，进 `Schema(...)` 数组

## 用户与协作上下文

用户铁博文是字节员工，本机已配置 `bytedcli`（CLI + Skill + MCP）和 `lark-cli`。涉及字节内部研发流程（MR / Codebase / Feishu / TCE / RDS / APM 等）时优先走 `bytedcli`；本仓库是个人 iOS app，与字节内部基建无直接耦合，但 commit 作者署名是 "ByteDance"。
