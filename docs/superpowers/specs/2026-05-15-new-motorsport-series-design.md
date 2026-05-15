# 新增赛车系列(Moto2 / Moto3 / SBK / WEC)+ 中文翻译 Spec

**Status**: Draft — awaiting user review
**Date**: 2026-05-15
**Author**: tiebowen (with Claude Code)
**Branch strategy**: 5 个 PR 顺序合到 `main`(对齐 architecture refactor 节奏)

## 1. 目标与背景

### 1.1 当前状态

Pole 覆盖 4 个赛车系列:F1 / MotoGP / WSSP(WorldSBK 中量级)/ Formula E。架构已完成 10 SPM 包重构,加新系列从 13 步降到 ≤6 步。`Localization.swift` 487 entries,12/12 翻译完整性测试通过。

### 1.2 用户要求

1. 加附加赛车系列:Moto2 / Moto3 / SBK(WSBK 顶级)/ WEC(FIA 世界耐力赛)
2. 中文翻译跟现有 4 系列同等完整
3. **主推仍是现有 4 系列**,新增是附加

### 1.3 设计原则

- **保持主推主导地位**:F1 / MotoGP / WSBK / FE 顶层 picker 不动
- **数据完整性优先**:同 weekend 多 class 一起显示(Moto2/3 跟 MotoGP 同周末)
- **复用 > 新建**:Moto2/Moto3 复用 MotoGPClient(同 Pulselive 后端);SBK 复用 WSBKClient(同 worldsbk.com)
- **翻译复用现有 mapping**:60-70% 车手已在现有 namespace 内

### 1.4 非目标(明确不做)

- ❌ Tier C 其他系列(IndyCar / NASCAR / WRC / DTM / Super GT / GT World Challenge / Nürburgring 24h)
- ❌ MotoE(电动 MotoGP)— MotorsportClass enum 留位但不实施
- ❌ WSSP300(WSBK 入门 class)— 同上
- ❌ Notification fragmenting(MotoGP toggle 不拆 Moto2/Moto3 子开关)
- ❌ Settings 子 class 可见性 toggle(没有自定义 UI)

## 2. 架构改动

### 2.1 新 enum: `MotorsportClass`

PoleDomain 新增类型表示子 class:

```swift
public nonisolated enum MotorsportClass: String, Sendable, Codable {
    // MotoGP 家族
    case motogp
    case moto2
    case moto3
    case motoe          // 留位,本期不实施

    // WSBK 家族
    case sbk            // Superbike 顶级
    case wssp           // World SSP 中量级(现已有)
    case ssp300         // 留位,本期不实施

    // F1 / FE / WEC 不区分 class(单一 class)/ WEC 双 class
    case f1
    case fe
    case wec_hypercar
    case wec_lmgt3

    public var parentSeries: MotorsportSeries {
        switch self {
        case .motogp, .moto2, .moto3, .motoe:                  return .motogp
        case .sbk, .wssp, .ssp300:                             return .wssp
        case .f1:                                              return .f1
        case .fe:                                              return .fe
        case .wec_hypercar, .wec_lmgt3:                        return .wec
        }
    }

    public var displayName: String { ... }      // "MotoGP" / "Moto2" / ...
    public var shortName: String { ... }        // "MotoGP" / "M2" / "M3" / "SBK" / ...
}
```

### 2.2 MotorsportSeries 加 wec

```swift
public nonisolated enum MotorsportSeries: String, ... {
    case f1
    case motogp
    case wssp
    case fe
    case wec            // 🆕 FIA World Endurance Championship
}
```

### 2.3 Session 加 `cls: MotorsportClass?`

```swift
public struct Session: Sendable, Codable, Hashable {
    public let id: String
    public let kind: Kind
    public let cls: MotorsportClass?         // 🆕 nil = 该系列单一 class(F1/FE)
    public let startTime: Date
    public let endTime: Date?
    // ...
}
```

`Session.Kind` 新增 case:
- `.race_2` — 显式 2nd race(SBK 周日下午 / WSSP 周日早上)
- `.superpoleRace` — SBK 周日 10-lap sprint
- `.warmup` — 周日早上 15 分钟

### 2.4 AnyMotorsportRound 加 wec case

```swift
public enum AnyMotorsportRound: Hashable, Sendable, Identifiable {
    case f1(F1Round)
    case motogp(MotoGPRound)        // sessions 含 motogp + moto2 + moto3
    case wssp(WSBKRound)            // sessions 含 sbk + wssp
    case fe(FERound)
    case feWeekend(FEWeekend)
    case wec(WECRound)              // 🆕
}
```

6 个 switch 属性(id / series / weekendStart/End / currentStatus / headline / subheadline)加 wec 分支。

### 2.5 PoleMotorsportKit 改动

| 文件 | 改动 |
|---|---|
| `MotoGP/MotoGPClient.swift` | `fetchSessions(eventId:classes:)` 拉 3 class,合并按时间排 |
| `MotoGP/MotoGPModels.swift` | `MotoGPRound.sessions` 含多 class |
| `WSBK/WSBKClient.swift` | `fetchRiderStandings(class:)` / `fetchEventSessions(class:)` 双 class |
| `WSBK/WSBKModels.swift` | `WSBKRound.sessions` 含 SBK + WSSP |
| `WEC/FIAWECClient.swift`(新) | actor,implements `MotorsportSeriesService` |
| `WEC/WECModels.swift`(新) | WECRound / Driver / Team / RaceResult / Standing |
| `WEC/WECStandings.swift`(新) | 双 class 适配 protocol JSON |
| `MotorsportSeriesService.swift` | FIAWECClient 实现 protocol + Registry case |
| `AnyMotorsportRound.swift` | 加 .wec case + 6 switch 分支 |

### 2.6 PoleDesignSystem 改动

- `SeriesTheme.swift`:`.wec` brandColor + brandGradient(建议:钢蓝/银)

### 2.7 加新系列 checklist 现状

加新 series 改动 ≤6 步:
1. `MotorsportSeries` enum 加 case
2. `MotorsportSeriesService` Registry 加 service
3. `AnyMotorsportRound` 加 case + switch 分支
4. `SeriesTheme` 加 brandColor / brandGradient
5. 5 AI tool params enum 加 case
6. UI(MotorsportListView 顶层 picker + Standings tab)

加新 sub-class 改动:
- `MotorsportClass` 加 case
- host series client 扩展 fetch 方法支持该 class
- Standings 二级 picker 加 entry
- Translation mapping 加

## 3. 数据源细节

### 3.1 Moto2 + Moto3(Pulselive 复用)

**Endpoint**:跟 MotoGP 同 `api.motogp.pulselive.com/motogp/v1/`,关键 path:
- 赛季 events 已有逻辑覆盖
- 单 event 各 class sessions:`/results/season/<seasonId>/events/<eventId>/sessions?categoryid=<MotoGP|Moto2|Moto3>`

**改造方式**:`MotoGPClient.fetchSessions` 改成接受 `classes: [MotorsportClass]` 默认三 class,并发 fetch,合并按 startTime 排序。返回 `[Session]`,每个 session 带 `cls`。

**Cache**:现有 `SeasonCache<[MotoGPRound]>(ttl: 3600)` 自动 cover。

### 3.2 SBK Superbike(WSBKClient 扩展)

**改造**:
- `WSBKClient.fetchRiderStandings(class: MotorsportClass)` 接受 `.sbk` 或 `.wssp`
- `WSBKClient.fetchEventSessions(class:)` 同理
- URL 路径区别:`/standings/sbk` vs `/standings/wssp`,PDF 路径同理
- 现有 PDF 解析逻辑(WSBKClient 已有)复用,只是传不同 URL

**Session.Kind 扩展**:`.race_2` / `.superpoleRace` / `.warmup`

### 3.3 WEC(新 client,fiawec.com)

**数据源探测**(plan 阶段第 1 步):
- 浏览器 devtools 查 fiawec.com 实际 fetch endpoint
- 优先 Path A:JSON endpoint(如 `cms.fiawec.com/api/...`)
- 备选 Path B:HTML scrape(WSBKClient 已有模式)

**数据结构**:

```swift
public struct WECRound: ..., MotorsportEvent {
    public let id: String                    // e.g., "2026-le-mans"
    public let roundNumber: Int              // 1..8
    public let name: String                  // "24 Hours of Le Mans"
    public let officialName: String          // "93e 24 Heures du Mans"
    public let venue: String                 // "Circuit de la Sarthe"
    public let venueCountry: String          // "France"
    public let weekendStart: Date
    public let weekendEnd: Date
    public let raceDurationHours: Double     // 6 / 8 / 10 / 24
    public let sessions: [Session]
}

public struct WECDriverStanding: ... {
    public let position: Int
    public let points: Double
    public let driver: WECDriver
    public let team: String
    public let classification: MotorsportClass    // .wec_hypercar / .wec_lmgt3
}

public struct WECTeamStanding: ... { ... }

public struct WECRaceResult: ... {
    public let overallPosition: Int
    public let classPosition: Int
    public let driver: WECDriver
    public let team: String
    public let classification: MotorsportClass
    public let laps: Int
    public let gap: String                       // "+12.345" or "+2 laps"
}
```

**特殊行为**:race 按时长(6/8/10/24h),非 fixed lap count。Le Mans 24h 是单独 standalone event。

**Cache**:`SeasonCache<[WECRound]>(ttl: 3600)`。

### 3.4 错误处理

- 网络失败 → `PoleError.network(URLError)`
- HTML/JSON 解析失败 → `PoleError.decoding("FIAWECClient.parseHypercarStandings")`
- HTTP 4xx/5xx → `PoleError.http(statusCode:body:)`
- 日志走 `PoleLog.net.error(...)` / `PoleLog.domain.warning(...)`
- WEC scrape 失败 graceful(返 nil / 空数组),不阻断时间线

## 4. UI 改动

### 4.1 MotorsportListView 顶层 picker

```
[全部] [F1] [MotoGP] [WSBK] [FE] [WEC]
```

6 个 picker item,segmented picker 装得下。

### 4.2 RoundDetailView 多 class chronological sessions

**MotoGP / WSBK** RoundDetail 改造:
- Session list 按 startTime 排序合并 3 class(MotoGP)或 2 class(WSBK)
- 每个 session row 加左侧 ~38pt class chip(brand-color)
- Day section header 分 Friday / Saturday / Sunday

```
Saturday
  10:50 · [Moto3] 排位赛
  10:50 · [MotoGP] 排位赛
  11:50 · [Moto2] 排位赛
  15:00 · [MotoGP] 冲刺赛
```

**WECRoundDetailView** 新建:
- 类似 F1RaceDetailView 结构 + 24h/10h/6h 时长 hero
- Race results 内部按 class 分两 section(Hypercar Top 10 / LMGT3 Top 10)

### 4.3 SessionResultsView hero subtitle 显示 class

- "MotoGP · 排位赛 · Bagnaia P1"
- "Moto2 · 排位赛 · ..."
- "SBK · Race 2 · ..."

WEC SessionResults 双 class 分两 list section。

### 4.4 StandingsView 二级 sub-class picker

顶层 segmented 选系列后,有 sub-class 的(MotoGP / WSBK / WEC)显示二级 picker:

```
MotoGP 选中 →  [MotoGP] [Moto2] [Moto3]
                ↓
                车手榜 / 车队榜 / 厂商榜

WSBK 选中  →  [SBK] [WSSP]

WEC 选中   →  [Hypercar] [LMGT3]
```

F1 / FE 没有 sub-class,picker 不显示。

实现:`StandingsView @State private var selectedSubClass: MotorsportClass?`,parent series view 检查决定 fetch 哪个 class。

### 4.5 MotorsportTimelineView

跨系列 timeline 不大变:
- Moto2/Moto3/SBK 数据合并到 host 系列 weekend card(不新增独立卡片)
- WEC 新增独立卡片(类似 F1/MotoGP/WSBK/FE 卡片样式)
- TaskGroup 已 4 个 service 并行,加 WEC = 5 个

### 4.6 Notifications

Settings 加 WEC toggle(5th):
```
[√] F1 通知
[√] MotoGP 通知       (包括 Moto2/Moto3 正赛)
[√] WSBK 通知         (包括 SBK 全部正赛 + SuperPole Race)
[√] Formula E 通知
[√] WEC 耐力赛通知    🆕
```

**通知策略**:
- MotoGP 开关 → MotoGP/Moto2/Moto3 正赛各推 30min 前,qualifying 只推 MotoGP class
- WSBK 开关 → SBK + WSSP 各推 race1/2 + SuperPole(SBK)+ SuperPole Race(SBK)
- WEC 开关 → race start 提前 30min;Le Mans 24h 额外加 start + end 提醒

### 4.7 Follow

- 新车手 / 新车队自动可关注(`FollowedItem.athlete(id:sport:series:)` / `team` 类型)
- 不新增 league follow(MotoGP league = 全 class)
- WSBK league 包含 SBK + WSSP

### 4.8 AI 工具

5 个 AI tool 的 `series` 参数 enum 加 `"wec"`。同时加 optional `class` 二级参数:

```json
"series": {"type": "string", "enum": ["f1", "motogp", "wsbk", "fe", "wec"]},
"class": {"type": "string", "enum": ["motogp", "moto2", "moto3", "sbk", "wssp", "hypercar", "lmgt3"], "optional": true}
```

不传 class 时默认 host 系列顶级 class。

LLM 用例:
- `get_standings(series: "motogp", class: "moto3", kind: "driver")`
- `get_session_results(series: "wec", round: 4, class: "hypercar")`

### 4.9 AppRouter Destination

```swift
public enum Destination: Hashable, Sendable {
    case roundDetail(series: String, roundId: String)
    case driverDetail(series: String, driverId: String, class: String?)  // 🆕 加 class
    case teamDetail(series: String, teamId: String, class: String?)      // 🆕
}
```

Live Activity / AppIntent 深链可指定 class。

## 5. 翻译策略

### 5.1 复用 vs 新增

| 系列 | 车手 | 车队 / 厂队 | 赛道 | 国家 |
|---|---|---|---|---|
| Moto2 / Moto3 | 复用 `.motogp` namespace,新增 ~60 | 复用现有 | 复用 | 复用 |
| SBK | 复用 `.wssp` namespace,新增 ~10 | 复用 6 厂 | 复用 | 复用 |
| WEC | **新增 ~120 名** | **新增 ~15 厂队** | 部分新增(Sebring / Imola / Spa / Le Mans / Fuji / Bahrain) | 复用 |

新增 mapping 总规模:**~150 entries**。Localization.swift 956 → ~1100 行。

### 5.2 数据收集流程

**主力 Path A — 脚本抓 + 人工 review**:
1. 写 Python/Swift script 抓 fiawec.com / motogp.com 2024-2026 全赛季 grid
2. 输出 JSON → 用 LLM 生成中文草稿 → 人工 review
3. 写进 `Localization.swift` 现有 namespace 约定

**翻译约定**:
- 欧美车手:音译全名("塞巴斯蒂安·布埃米")
- 日韩车手:汉字("小林可梦伟")
- 厂队:意译厂家 + 保留英文车队后缀("丰田 Gazoo 赛车","保时捷·彭斯克")
- 客户车队不常见名:保留英文("Akkodis ASP","United Autosports")

### 5.3 完整性测试

扩展 `PoleTests/MotorsportNamesCompletenessTests.swift`:

```swift
@Test func moto2RidersHaveChineseName() { ... }
@Test func moto3RidersHaveChineseName() { ... }
@Test func sbkRidersHaveChineseName() { ... }
@Test func sbkBuildersHaveChineseName() { ... }
@Test func wecHypercarDriversHaveChineseName() { ... }
@Test func wecLMGT3DriversHaveChineseName() { ... }
@Test func wecTeamsHaveChineseName() { ... }
```

新加 ~7 个 test suite,~80 entries 测试。

### 5.4 风险

| 风险 | 缓解 |
|---|---|
| WEC 客户车队赛季中调整频繁 | 翻译表 driver 名独立于 team |
| Le Mans 24h 临时邀请车手不在年度榜 | fallback 显示原文 |
| Moto2/Moto3 替补 ID 跟 MotoGP 共享但未在 mapping | 复用 `.motogp` namespace,逐条加 |
| 翻译"约定俗成"争议 | 取主流圈最常用版本,不提供切换 |

## 6. 实施 Phase

### Phase 1 — Moto2 + Moto3 数据接入(PR1)

**Scope**:
- `MotorsportClass` enum + `Session.cls` 字段
- `MotoGPClient.fetchSessions` 3 class 并发 + 合并
- `MotorsportNames.motoGPRiderShort/Full` 新增 ~60 entries
- `MotorsportNamesCompletenessTests` 加 moto2/moto3 suite

**UI**:
- `MotoGPRoundDetailView` sessions list 加 class chip 前缀
- `SessionResultsView` hero subtitle class 显示
- `StandingsView` MotoGP tab 加二级 sub-picker
- `MotoGPStandingsViewModel` 接受 class 参数

**完成判定**:Simulator 跑通 MotoGP 周末 detail 看到 Moto2/Moto3 sessions + Moto3 standings + 完整性 test 全过

**预估**:~15 文件改 / +500 行

---

### Phase 2 — WSBK Superbike 接入(PR2)

**Scope**:
- `WSBKClient.fetchRiderStandings(class:)` + `fetchEventSessions(class:)` 双 class
- `Session.Kind` 加 `.race_2` / `.superpoleRace` / `.warmup`
- `WSBKRound.sessions` 合并 SBK + WSSP
- `MotorsportNames` 复用 `.wssp` namespace,新增 ~10 SBK 车手

**UI**:同 Phase 1 模式,WSBK detail + Standings 二级 picker

**预估**:~10 文件改 / +250 行

---

### Phase 3a — WEC 数据源 + Client(PR3)

**Scope**:
- 探测 fiawec.com endpoint(devtools 第一步)
- `FIAWECClient` actor 实现 `MotorsportSeriesService`
- `WECModels` / `WECStandings`
- 单独 swift build 通过(无 UI)

**风险**:数据源不稳定,可能 fallback HTML scrape

**预估**:~5 新文件 / +600 行

---

### Phase 3b-d — WEC UI + 翻译 + 周边(PR4)

**Scope**:
- `MotorsportSeries.wec` case + brandColor / brandGradient
- `AnyMotorsportRound.wec` case + 6 switch 分支
- `MotorsportRegistry` + `MotorsportSeriesService` 接入
- `WECRoundDetailView` 全新页面
- `WECStandings` view(双 sub-class picker)
- `MotorsportListView` picker 加 WEC
- `MotorsportTimelineView` TaskGroup 5 task
- `WidgetSnapshotBuilder` 5 系列扫描
- `AppRouter.Destination` driver/team 加 `class:` 参数
- `NotificationScheduler` 加 .wec 支持
- `MotorsportNames.wecDriverFullName` / `wecTeamName` 新增 ~135 entries
- `MotorsportNamesCompletenessTests` 加 wec suite

**预估**:~20 文件改 / +800 行

---

### Phase 4 — AI tool 5 系列 + class 参数(PR5)

**Scope**:
- 5 AI tool `series` enum 加 `"wec"`
- `FindRoundTool` / `GetSessionResultsTool` / `GetStandingsTool` / `GetDriverHistoryTool` 加 optional `class` 参数
- LLM system prompt 加 5 系列名 + class 关键词
- `ChatGreetingProvider.systemPrompt` 中文版更新

**预估**:~5 文件改 / +100 行

---

### PR 路线图

| PR | Phase | 内容 | 风险 | 改动 |
|---:|---|---|---|---:|
| **PR1** | Phase 1 | Moto2 + Moto3 数据 + UI + 翻译 | 中(多 class 渲染) | ~15 文件 / +500 行 |
| **PR2** | Phase 2 | SBK 顶级 class 接入 | 低(复用 Phase 1 模式) | ~10 文件 / +250 行 |
| **PR3** | Phase 3a | FIAWECClient 数据源 | 高(新数据源探测) | ~5 新文件 / +600 行 |
| **PR4** | Phase 3b-d | WEC UI + 翻译 + 周边 | 中 | ~20 文件 / +800 行 |
| **PR5** | Phase 4 | AI tool 5 系列 + class | 低 | ~5 文件 / +100 行 |

**整体**:5 PR / ~55 文件 / ~2250 行新增。1.5-2 周普通推进 / 3-4 天 subagent 并行。

### 完成判定(全 5 PR merge 后)

1. MotorsportListView 5 系列 picker 可切
2. MotoGP weekend detail 显示 MotoGP+Moto2+Moto3 全 session 按时间排序
3. WSBK weekend detail 显示 SBK+WSSP 全 session
4. WEC Le Mans 24h detail 显示 Hypercar+LMGT3 results
5. Standings MotoGP / WSBK / WEC 都有二级 sub-picker
6. LLM 能识别"Moto3"/"勒芒 Hypercar"等术语
7. 翻译完整性测试 ~80 个 entry 全过(现 12 + 新 ~7 个 suite)
8. Notification 5 系列 toggle 各自工作

## 7. 决策日志

| 决策点 | 选择 | Section |
|---|---|---|
| 系列数量 | Tier A 子集(Moto2/Moto3/SBK)+ WEC | Brainstorm Q1+Q3 |
| Moto2/Moto3/SBK UX | 嵌套到 host 系列 weekend,不进顶层 picker | Section 2 |
| WEC UX | 顶层独立 5th case | Section 2 |
| sub-class 表达 | `MotorsportClass` enum + `Session.cls` 字段 | Section 2 |
| 翻译范围 | Path A(脚本 + 人工 review)+ LLM 二三线 | Section 5 |
| 实施 phase | 4 个 phase / 5 个 PR / 顺序合 | Section 6 |
| Notification 子开关 | 不拆,parent series toggle 含全 class race | Section 4.6 |
| 命名约定 | 欧美车手音译全名 / 日韩汉字 / 厂队意译 + 英文车队后缀 | Section 5.2 |

## 8. 不在 scope

- IndyCar / NASCAR / WRC / DTM / Super GT / GT World Challenge / Nürburgring 24h(留 Tier B/C 后续)
- MotoE(留 MotorsportClass 位)
- WSSP300(同)
- Settings 子 class 可见性 toggle
- Notification 子开关 fragment

## 9. 风险总览

| 风险 | 等级 | 缓解 |
|---|---|---|
| fiawec.com 数据源不稳定 / API 改版 | 高 | Phase 3a 第 1 步 devtools 探测,fallback HTML scrape |
| Moto2/Moto3 并发 3 class fetch 增加网络压力 | 中 | SeasonCache actor + task coalescing 已防 |
| WEC 客户车队赛季中变动 | 中 | 翻译表 driver/team 解耦 |
| MotoGP RoundDetail 多 class 视图过厚 | 中 | Day section header 分组,class chip 视觉区分 |
| Standings 二级 picker 影响其他 series 一致性 | 低 | 沿用现有 segmented picker pattern |
| 翻译 LLM 草稿命中率 ~80% | 中 | 主力人工 review,二三线 LLM 兜底 |
