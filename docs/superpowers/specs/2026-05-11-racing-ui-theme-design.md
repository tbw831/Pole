# Racing UI Theme Refactor — Pole iOS App

> Spec date: 2026-05-11
> Owner: tiebowen
> Status: Draft (pending user review)
> Skill flow: `superpowers:brainstorming` → `superpowers:writing-plans` (next)

---

## 1. 目标与背景

把 Pole iOS app 当前的 "AI 助手 / 豆包风" 视觉(iOS 蓝主调 `#007AFF`、`.system(rounded)` 圆润字体、24px 柔和圆角、`sparkles` 渐变球头像、淡描边白卡片)改造为 **"非常有赛车风格"**。

约束:在保持 iOS 26 Liquid Glass 现代感与 HIG 兼容的前提下,传递赛车 paddock 视觉语言——**沥青深底 + F1 红 accent + 工业 SF 字体 + 棋盘格 / 起跑灯 / 系列色条 / 速度线装饰元素 + 默认 Dark**。

不在范围内:Widget extension 视觉 / LiveActivity / 灵动岛 / 系统通知 banner / Safari in-app view / 自定义字体引入 / Light 模式专属装饰雕琢。

## 2. 已确认的方向决策(brainstorming 输出)

| 维度 | 决策 | 备注 |
|---|---|---|
| 改造激进度 | 中量(约 60% 改动量) | 保留 Liquid Glass 与 HIG,跳过激进 paddock 沉浸 |
| 全局主色 | 黑 + 红双主 | 背景 `#0E0E10` 沥青黑 + accent F1 红 `#E10600` |
| Light/Dark | Dark 默认 + Settings 可切 Light/跟系统 | 不跟随系统首次启动 |
| 字体策略 | SF + weight/mono 巧用 | 不引入自定义字体,数字用 SF Mono |
| 装饰元素 | 4 项全部引入 | 卡片顶部系列色条 / 棋盘格 / 起跑灯阵 / Diagonal speed lines |
| 执行路径 | Token first → 页面分批 | 5 个 Phase 独立 commit / 独立可 revert |

## 3. 视觉 Token 重写(`DS` namespace)

底层 token 一次性翻译为赛车语言,影响全 app。

### 3.1 Palette(色板)

```text
// 旧 → 新 (主要替换)
DS.Palette.primary       #007AFF iOS 蓝         →  racingRed       #E10600
DS.Palette.primarySoft   #5099FF                →  racingRedSoft   #FF1F1A
DS.Palette.primaryDeep   #0058B0                →  racingRedDeep   #9C0500
DS.Palette.primaryFaint  primary @10%           →  racingRedFaint  racingRed @10%
DS.Palette.aiGradient    blue→bluesoft          →  racingGradient  racingRedDeep → racingRed → racingRedSoft (斜 45°)

// 新增"沥青"中性色阶(Dark 模式背景层级)
tarmacBg       Dark #0E0E10  /  Light .systemBackground            (主背景)
tarmacFill     Dark #18181B  /  Light .secondarySystemBackground   (二级填充)
tarmacCard     Dark #232327  /  Light .tertiarySystemBackground    (卡片填充)
tarmacHairline Dark #2E2E33  /  Light .separator                   (描边)

// 装饰元素表面色(双模 alpha 不同)
decorOnSurface Dark white@0.08  /  Light black@0.06                 (CheckerStripe / SpeedLines 默认色)

// 状态色(Dark 下加饱和)
live           #FF2D2D    (上调饱和,黑底跳出)
upcoming       #4DA8FF    (蓝紫,Dark 下舒适)
finished       #6E6E73    (灰)
postponed      #FF9F0A    (橙)
```

实现:`tarmac*` 与 `decorOnSurface` 用 `Color(uiColor: UIColor { trait in ... })` dynamic API,**不需要手动监听 colorScheme 变化**。

### 3.2 Radius(圆角)

整体收窄约 30%,保留圆角(不切硬角)避免 HIG 违和,但视觉从"圆润 AI"转向"工业精密"。

```text
sm:   8  → 4
md:  12  → 8
lg:  16  → 12
xl:  20  → 16
xxl: 24  → 20
bubble: 20 → 14
pill:   22 → 18
```

### 3.3 Font

去 `design: .rounded`,加大 weight 跨度,新增赛事数字 mono 三档。

```swift
// 旧
heroTitle = .title3, design: .rounded, weight: .bold

// 新
heroDisplay    = .largeTitle, design: .default, weight: .heavy, tracking: -0.5
heroTitle      = .title2,     design: .default, weight: .bold
heroSubtitle   = .footnote   (维持)

// 新增"赛事数字"专用 (.monospacedDigit / design: .monospaced)
numberLarge    = .system(size: 32, weight: .heavy).monospacedDigit()
numberMid      = .system(size: 20, weight: .semibold, design: .monospaced)
numberSmall    = .system(size: 14, weight: .medium, design: .monospaced)

// bubble / timestamp / toolLabel 沿用(不动 AI 气泡现有阅读体验)
```

### 3.4 Motion

```swift
// 现有 bubbleEntry / layout / press / cursorBlink 保留
// 新增
raceEntry  = .spring(response: 0.28, dampingFraction: 0.7)  // 比 bubbleEntry 快,关键状态入场
countdown  = .easeIn(duration: 0.4)                         // 起跑灯递进感
speedLine  = .linear(duration: 1.2).repeatForever           // diagonal stripes 滚动
```

### 3.5 Shadow

```swift
// 现有 bubble / card / aiHero 保留
// 新增
racingGlow  = (color: racingRed @55%, radius: 16, x: 0, y: 4)    // 主 CTA / live hero
carbonInset = (color: black @50%,     radius: 2,  x: 0, y: -1)   // 内阴影,模拟刻在沥青上
```

---

## 4. 核心装饰组件 + DS Modifier 升级

### 4.1 4 个新 SwiftUI 组件(新文件 `Pole/Theme/RacingComponents.swift`)

```swift
// 1. SeriesTopAccent — 卡片顶部品牌色条
struct SeriesTopAccent: View {
    let series: MotorsportSeries
    var height: CGFloat = 3
    // Rectangle().fill(series.brandColor).frame(height: 3)
    // + 右端 4px 渐变到透明 (赛旗末端拖尾)
}

// 2. CheckerStripe — 黑白棋盘格
struct CheckerStripe: View {
    enum Layout { case horizontal, vertical, fill }
    let layout: Layout
    var cellSize: CGFloat = 6
    var opacity: Double = 1.0
    // Canvas 实现,trait-aware (Dark 白格, Light 黑格)
}

// 3. StartLightGrid — F1 起跑灯阵列
struct StartLightGrid: View {
    enum Mode {
        case countdown(litCount: Int)   // 0..5 红灯递进点亮
        case lightsOut                  // 全灭 (起步)
        case idle                       // 全灭无动画
    }
    let mode: Mode
    var size: CGFloat = 14   // 单个灯直径
    // 配 raceEntry/countdown motion
}

// 4. SpeedLinesOverlay — 45° 斜线装饰
struct SpeedLinesOverlay: ViewModifier {
    var color: Color = DS.Palette.decorOnSurface
    var animated: Bool = false
}
extension View {
    func speedLines(color: Color = DS.Palette.decorOnSurface, animated: Bool = false) -> some View
}
```

**承载位**:
- `SeriesTopAccent` → 每个 round / driver / team / list row 顶部
- `CheckerStripe` → 完赛 badge / Onboarding hero / Settings header / Empty state
- `StartLightGrid` → RoundDetailView 比赛即将开始 hero / Empty state
- `SpeedLinesOverlay` → Hero header / live 状态卡片 / loading

### 4.2 dsXxx modifier 升级(`Pole/Theme/DesignSystem.swift`)

| modifier | 旧 | 新 |
|---|---|---|
| `dsAIBubble()` | Liquid Glass / `.secondarySystemBackground` | 维持,fallback 改 `tarmacCard` + `tarmacHairline` 描边 |
| `dsGlassPill()` | Liquid Glass / ultraThinMaterial | 维持,stroke 改 `racingRedFaint`(选中)/`tarmacHairline`(默认) |
| `dsToolCard()` | Liquid Glass / `.tertiarySystemBackground` | 维持,fallback `tarmacCard` + `carbonInset` |
| `dsListCard()` | `.secondarySystemBackground` + white@8% 描边 | `tarmacFill` + `tarmacHairline` + 新增 `seriesAccent:` 可选参数 |
| `dsDetailList()` | insetGrouped + 透明 | 维持,底色改 `tarmacBg` |
| **新** `dsHeroBanner()` | — | 大 hero 包装: `tarmacBg` + `speedLines` overlay + 12px radius + 可选 `SeriesTopAccent` |
| **新** `dsRacingButton` ButtonStyle | — | `racingGradient` + Heavy 白字 + `racingGlow` + pressed 0.97 scale + lightImpact |
| **新** `dsLiveBadge()` | — | `StatusBadge.live` 内部用:棋盘格右拖尾 + live 色脉冲呼吸 |

### 4.3 `dsListCard` 签名变更

```swift
// 旧
func dsListCard() -> some View

// 新 (向后兼容: nil 默认保持纯净卡片)
func dsListCard(seriesAccent: MotorsportSeries? = nil) -> some View
//   nil      → 纯净 (Standings 排行行有自己的 leading bar,传 nil)
//   .f1 等   → 顶部加 SeriesTopAccent
```

### 4.4 AIAvatar 渐变切换

`AIAvatar` 内部 `Circle().fill(DS.Palette.aiGradient)` 改为 `racingGradient`。图标维持 `steeringwheel`。语义从"AI 助手"转向"主驾驶座"。

---

## 5. 页面迁移清单

### 5.1 Tab 1 赛车(`MotorsportListView` + `MotorsportTimelineView`)

| 改造点 | 怎么做 |
|---|---|
| Segmented picker | `SegmentedPillPicker` 选中态从 `aiGradient` 改为所选系列 `brandGradient`("全部" 走 `racingGradient`) |
| `MotorsportCard` 列表 row | `dsListCard(seriesAccent: round.series)` 顶部 3px 系列色条;状态 badge 用新 `dsLiveBadge()` |
| Timeline 月份 header | `heroTitle` Heavy + tracking + 左侧 4px `racingRed` 短竖条 |
| Empty state | `CheckerStripe(.fill, opacity: 0.04)` 满铺极淡背景 + `StartLightGrid(.idle)` 居中 |
| 下拉刷新 chip | `dsGlassPill()`,加载文字 `numberSmall` SF Mono |

### 5.2 Tab 2 积分榜(`StandingsView`)

| 改造点 | 怎么做 |
|---|---|
| 系列 picker | 同 5.1,选中走当前系列品牌色 |
| 排行 row | 3 段: `P1` (`numberMid` Heavy) / 车手名 (`heroTitle` Bold) / 积分 (`numberLarge` Heavy 末尾对齐) |
| Top 3 强调 | P1: leading 3px `racingRed` 竖条 + `racingRedFaint` 背景;P2/P3: 仅 leading `tarmacHairline` 竖条 |
| Section header "DRIVERS / TEAMS" | 全大写 Heavy + tracking +1.0 + 底部 1px `tarmacHairline` + 右侧 8px `CheckerStripe(.horizontal, cellSize: 4)` |
| 数字列 | 全部 `numberMid.monospacedDigit()`,位数对齐(关键质感细节) |

### 5.3 Tab 3 AI(`ChatView`)

> 原则:气泡 / 输入框核心交互不动,周边装饰转赛车感。

| 改造点 | 怎么做 |
|---|---|
| Greeting hero | "早上好,Pole" → `heroDisplay` Heavy;副标题改 `numberSmall` SF Mono 风(`READY · DRS ENABLED · 2026/05/11`);`AIAvatar(.large)` 渐变换 `racingGradient` |
| TriviaCard | `dsHeroBanner()` 包装(内含 speedLines + 顶部 SeriesTopAccent);标题改"📋 PIT NOTE · 冷知识" |
| AI 消息气泡 | `dsAIBubble()` Liquid Glass 不动 |
| Tool step card | `dsToolCard()` 升级后自带 carbonInset;`BreathingDot` 色改 `racingRed` |
| 用户消息气泡 | `racingRedFaint` 底 + `racingRed` 文字 |
| 输入框 send 按钮 | `.buttonStyle(.dsRacingButton)` (`racingGradient` + `racingGlow` + lightImpact) |
| 流式光标 `▍` | 颜色从 primary 蓝改 `racingRed` |
| 滚动到底 fab | `racingGradient` + `racingGlow` |
| **Greeting 模式 toggle** | `ChatViewModel.greetingMode` boolean,Settings 加 toggle 退回 friendly("早上好,我是 Pole") |

### 5.4 Tab 4 关注(`FollowFeedView`)

| 改造点 | 怎么做 |
|---|---|
| Filter pill (车手/车队/赛事) | 同 segmented picker,选中态 `racingRed` |
| 关注项 row | `dsListCard(seriesAccent: target.series)` 色条;头像/logo 加 `tarmacHairline` 1px 描边圆 |
| Empty state | `StartLightGrid(.idle)` + "尚未关注任何车手/车队" + CTA `dsRacingButton` "去赛车 tab 发现" |

### 5.5 Tab 5 设置(`SettingsView`)

| 改造点 | 怎么做 |
|---|---|
| Header banner | `dsHeroBanner()` "POLE · 赛车追踪" Heavy + 底部 `CheckerStripe(.horizontal)` 8px 装饰条 + 右侧 speedLines |
| Settings row | `dsListCard()` 不传 `seriesAccent`;Toggle tint 改 `racingRed` |
| **新增** "外观" section | Light / Dark / 跟系统 三选一 `SegmentedPillPicker`(Section 6 承载位) |
| **新增** "减少装饰" toggle(可选) | `@AppStorage("reducedDecor")` 控制 CheckerStripe / SpeedLines / StartLightGrid 全套装饰 |
| **新增** "Greeting 模式" toggle | racing / friendly 二选一,默认 racing |
| About 区 | 版本号 `numberSmall` SF Mono "v1.0.0 · BUILD 2026.05.11";作者签名末尾加 6px `CheckerStripe` |

### 5.6 详情页(`RoundDetailView` / `DriverDetailView` / `SessionResultsView` / `TeamDetailView`)

4 系列 × 3 详情页(RoundDetail / DriverDetail / SessionResults)+ 1 通用 TeamDetailView = **13 个改造点**(同步做,避免漏改)。

| 页面 | 关键改造点 |
|---|---|
| RoundDetailView | `GlassHeroHeader` 升级:`SpeedLinesOverlay` + 顶部 `SeriesTopAccent` + 即将开始(剩 < 10min)显示 `StartLightGrid(.countdown(...))`;session 行 `dsToolCard`,时间 `numberSmall` SF Mono,session 名 "FP1/Q/SPRINT/RACE" 全大写 Heavy;`WeatherCard` 维持极简;`RaceRecapSection` 外框 `dsHeroBanner` |
| DriverDetailView | hero 头像下方加车手编号大字 `numberLarge` Heavy;国旗 + 出生地小字 SF Mono;历史成绩表格 row 用 `numberMid` 对齐 |
| SessionResultsView | 名次 P1/P2/P3 `numberMid` Heavy;圈速时间 `numberMid` SF Mono(3 位小数完整);P1 行 `racingRedFaint` 底 |
| TeamDetailView | 车队 logo 区 `dsHeroBanner()` + `SeriesTopAccent` |

#### StartLightGrid 倒计时简化策略

避免高频 Timer 耗电,按"距开赛分钟数"映射 5 灯静态状态:

```
距 > 10min  → idle (灯灭)
5min < 剩余 < 10min  → litCount = 1
1min < 剩余 < 5min   → litCount = 3
剩余 < 1min          → litCount = 5 (全亮)
已开赛              → lightsOut (全灭, "灯已熄起跑")
```

View `.onReceive(Timer.publish(every: 60))` 每 60s 重计算 — 1Hz 对电量可控。

### 5.7 通用 Card 组件升级

- `StatusBadge.live` → `dsLiveBadge`(棋盘格右拖尾 + 脉冲呼吸)
- `WeatherCard` 圆角 16 → 12
- `WikipediaSummarySection` → Dark 下底色改 `tarmacCard`
- `GlassHeroHeader` → 加 `speedLines` overlay 参数,默认 off
- `SeriesGradientBar` → 已存在,不动

### 5.8 不改造的范围(明确划出去)

- LiveActivity / 灵动岛(系统 widget 模板,保持现状)
- 通知 banner(系统接管)
- Safari in-app web view(`SafariView`)
- 表情符号、SF Symbol 图标库(仅替换 sparkles → steeringwheel 这种已有改动,不批量换)

---

## 6. Light/Dark 切换实现

### 6.1 `AppearanceMode` + `AppearanceStore`(新文件 `Pole/Domain/AppearanceMode.swift`)

```swift
public enum AppearanceMode: String, CaseIterable, Sendable {
    case dark    // 默认
    case light
    case system

    public var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .dark:   return L10n.t(zh: "深色", en: "Dark")
        case .light:  return L10n.t(zh: "浅色", en: "Light")
        case .system: return L10n.t(zh: "跟随系统", en: "System")
        }
    }
}

@MainActor
public final class AppearanceStore: ObservableObject {
    public static let shared = AppearanceStore()
    private let key = "appearanceMode"

    @Published public var current: AppearanceMode {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: key) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let mode = AppearanceMode(rawValue: raw) {
            self.current = mode
        } else {
            self.current = .dark   // 首次启动默认 Dark(不跟系统)
        }
    }
}
```

App Group 同步:Widget extension 不读 appearance(自动跟系统),不写共享。用普通 `UserDefaults.standard`。

### 6.2 `PoleApp` 注入

```swift
@main
struct PoleApp: App {
    @StateObject private var appearance = AppearanceStore.shared
    // ... 现有 sharedModelContainer

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.current.colorScheme)
                .modelContainer(sharedModelContainer)
        }
    }
}
```

### 6.3 `SettingsView` "外观" section

```swift
Section {
    SegmentedPillPicker(
        selection: $appearance.current,
        items: AppearanceMode.allCases
    ) { mode in
        Text(mode.displayLabel)
    }
} header: {
    HStack {
        Text(L10n.t(zh: "外观", en: "Appearance"))
        Spacer()
        CheckerStripe(.horizontal, cellSize: 4, opacity: 0.5)
            .frame(width: 16, height: 6)
    }
}
.environmentObject(AppearanceStore.shared)
```

### 6.4 Light 模式视觉降级原则(明确接受的代价)

| 元素 | Dark | Light |
|---|---|---|
| 主背景 | `tarmacBg` #0E0E10 | `.systemBackground` 白 |
| 卡片填充 | `tarmacFill` #18181B | `.secondarySystemBackground` |
| 描边 | `tarmacHairline` #2E2E33 | `.separator` |
| `racingRed` accent | #E10600 | #E10600(双模通用) |
| `SpeedLinesOverlay` | `white@0.06` | `black@0.04` |
| `CheckerStripe` | 白 vs 黑 | 浅灰 vs 白 |
| `StartLightGrid` 红灯 | racingRed + racingGlow | racingRed(减弱 glow) |
| `SeriesTopAccent` | `brandColor` | `brandColorAccessible`(已存在 AA 兼容版) |
| Liquid Glass | regular(深底自适应) | regular(浅底自适应) |

赛车感主要来自不依赖深底色就能传达的元素:`SeriesTopAccent` 色条 + `StartLightGrid` + 数字 SF Mono。Light 模式不再补 Light 专属装饰雕琢。

---

## 7. Phase 划分 + 风险预案

5 个 Phase,每个独立 commit / 独立可验证 / 独立可 revert。

### Phase 1 — DS Token 重写 + Light/Dark 接入(~1d)

| 产出文件 | 改动 |
|---|---|
| `Pole/Theme/DesignSystem.swift` | Palette/Radius/Font/Motion/Shadow 全量更新(Section 3) |
| `Pole/Theme/SeriesTheme.swift` | `aiGradient` 实现替换为 `racingGradient`,语义改名 |
| `Pole/Domain/AppearanceMode.swift`(新) | enum + `AppearanceStore.shared` |
| `Pole/PoleApp.swift` | `@StateObject appearance` + `.preferredColorScheme(...)` |
| `Pole/Features/Settings/SettingsView.swift` | 加 "外观" segmented picker(承载位) |

**验收**:启动默认 Dark / Settings 切 Light/系统即时生效 / 主 CTA 全变红 / 旧业务页 layout 不变但配色更赛车

**风险**:`DS.Palette.primary` 蓝色直接消失,全 app `.primary` 引用一律变红(目标即此,无回滚成本)。Liquid Glass `.tint(...)` 自动跟上

**回滚**:单 commit revert

### Phase 2 — 装饰组件 + dsXxx modifier 升级(~1d)

| 产出文件 | 改动 |
|---|---|
| `Pole/Theme/RacingComponents.swift`(新) | `SeriesTopAccent` / `CheckerStripe` / `StartLightGrid` / `SpeedLinesOverlay`(Section 4) |
| `Pole/Theme/DesignSystem.swift` | `dsAIBubble` / `dsToolCard` / `dsListCard` fallback 改色;新加 `dsHeroBanner` / `dsRacingButton` / `dsLiveBadge` |
| `Pole/Features/Common/StatusBadge.swift` | `.live` case 接入 `dsLiveBadge` |

**验收**:每个新组件 SwiftUI `#Preview` Light/Dark + Dynamic Type Large/AX1 都正常;旧业务页 layout 不变(`dsListCard()` 不传参与旧版一致)

**风险**:`dsAIBubble` Liquid Glass fallback(iOS 25)路径色彩变化;但项目目标 iOS 26.2,iOS 25 fallback 仅兜底无强验证义务

**回滚**:revert `RacingComponents.swift` + revert DS.swift 新 modifier 块

### Phase 3 — 5 Tab 主页迁移(~2.5d,每 tab 一个 commit)

| 顺序 | tab | 工作量 | 验收点 |
|---|---|---|---|
| 3.1 | Tab 5 设置 | 0.3d | Header banner + CheckerStripe + 版本号 SF Mono → 先验证 token 落地 |
| 3.2 | Tab 1 赛车 | 0.7d | 卡片色条 + Timeline 月份大字 + Empty state `StartLightGrid` — **首屏赛车感**这步定调 |
| 3.3 | Tab 4 关注 | 0.4d | 列表色条 + Empty state |
| 3.4 | Tab 2 积分榜 | 0.5d | 数字 SF Mono 对齐 + P1 racingRedFaint + section header 棋盘格 |
| 3.5 | Tab 3 AI | 0.6d | Greeting hero 转赛车 telemetry + TriviaCard `dsHeroBanner` + 流式光标改红;`greetingMode` toggle 留 |

**风险**:Tab 3.5 ChatView 赛车 telemetry 风(`READY · DRS ENABLED`)可能不被接受 → `greetingMode` toggle 兜底;大字 Heavy weight 撑高 timeline header 需 layout 测试

**回滚**:单 tab 独立 commit,某个 tab 不喜欢 revert 那一个

### Phase 4 — 详情页迁移(~2d,4 系列 × 详情页一起做避免漏改)

13 个改造点(参附录 B 完整 checklist):4 系列 × 3 件套(RoundDetail / DriverDetail / SessionResults)+ 通用 TeamDetailView × 1。

**风险**:漏改某一系列某一页 → 改造前对 13 点 checklist 逐个勾;`StartLightGrid` 倒计时按 60s Timer 重算(简化策略见 5.6)

**回滚**:单页面单 commit

### Phase 5 — 动效/触觉打磨(可选,~0.5d)

- 切 Tab 加 `HapticFeedback.lightImpact()`
- `raceEntry` motion 应用到 RoundDetailView hero 入场
- `SpeedLinesOverlay(animated: true)` 在 live 卡片
- `racingGlow` shadow 在 `dsRacingButton` 按下时强化
- 全部走 `@AppStorage("reducedDecor")` 全局 toggle 默认 off,Settings 可关闭整套装饰

### 风险预案总览

| 类型 | 缓解 |
|---|---|
| 风格不喜欢 | 每 Phase 独立 commit / revert 5 分钟 |
| AI tab 语言转 racing 用户不接受 | `ChatViewModel.greetingMode` toggle |
| 装饰元素视觉过载 | `@AppStorage("reducedDecor")` toggle 关闭整套装饰 |
| Light 模式赛车感弱 | 文档明确接受的代价,不补 Light 专属装饰 |
| Dynamic Type AX1 layout 破 | 每页面 AX1 跑一遍,Heavy + tracking 必要时 `.minimumScaleFactor(0.85)` |
| Widget 视觉不一致 | Widget 不在范围,后续 Phase 6 单独同步 |

### 测试策略

视觉改造无 unit test 价值,**4 步验证**:
1. 每组件/页面写完跑 `#Preview` (Light + Dark + Dynamic Type Large)
2. 模拟器跑 iPhone 14 Pro / 16 Pro / SE3(最小屏)
3. Settings → Accessibility → Reduce Motion 验证动效降级
4. Settings 内即时切 Dark/Light 看过渡

现有 `PoleTests` Swift Testing 套件不受影响(ViewModel/Domain layer 不动)。

### 总时间预估

Phase 1 + 2 + 3 + 4 + 5 ≈ **6-7 工作日**(单人,含视觉自验)。Phase 5 可推迟到全量上线后做。

---

## 8. 验收 Checklist(per Phase 出口标准)

### Phase 1 出口
- [ ] 启动 app 默认 Dark 模式
- [ ] Settings → 外观 picker 三态可切,即时生效
- [ ] 所有原 `.primary` / `.tint` 色变为 racingRed
- [ ] 现有页面 layout 0 改动(仅配色变化)
- [ ] `DS.Palette` 旧 `primary` 引用全部编译通过(rename 或 typealias 兜底)

### Phase 2 出口
- [ ] `SeriesTopAccent` / `CheckerStripe` / `StartLightGrid` / `SpeedLinesOverlay` 4 组件 Preview 通过
- [ ] `dsHeroBanner` / `dsRacingButton` / `dsLiveBadge` Preview 通过
- [ ] `StatusBadge.live` 视觉验证(棋盘格拖尾 + 脉冲)
- [ ] 旧业务页 layout 0 改动

### Phase 3 出口(每 tab 独立 commit 验)
- [ ] Tab 1: MotorsportCard 顶部色条可见;Timeline 月份 header Heavy 字 + 红竖条;Empty state 起跑灯
- [ ] Tab 2: P1 行 racingRedFaint 底 + leading 红条;数字列对齐
- [ ] Tab 3: Greeting `heroDisplay` + SF Mono 副标题;输入框 send 按钮 `dsRacingButton`
- [ ] Tab 4: 列表 row 系列色条
- [ ] Tab 5: Header banner + 外观 picker + Greeting 模式 toggle + 减少装饰 toggle

### Phase 4 出口(13 改造点 checklist)
- [ ] F1/MotoGP/WSBK/FE × RoundDetailView 4 个
- [ ] F1/MotoGP/WSBK/FE × DriverDetailView 4 个
- [ ] F1/MotoGP/WSBK/FE × SessionResultsView 4 个
- [ ] TeamDetailView × 1(通用)+ 加测 F1 / MotoGP / WSBK / FE 4 个不同 team
- [ ] StartLightGrid 倒计时按 60s Timer 不耗电(Instruments 验证)

### Phase 5 出口
- [ ] 切 Tab 触觉反馈生效
- [ ] live 状态卡片 SpeedLines 动起来
- [ ] `dsRacingButton` 按下 racingGlow 强化
- [ ] Reduce Motion 开启时动效全停
- [ ] `reducedDecor` toggle 关闭装饰元素生效

---

## 附录 A — 现状代码点位扫描(Phase 1 落地参考)

> 由 3 个并行 `Explore` agent 扫描产出,补充实际 file:line 引用清单。
> 占位,agent 完成后增补。

### A.1 `DS` namespace + `BrandPalette` token 使用点位

按 token 分组,列实际改造影响。

**`DS.Palette.primary`(14 处 — 集中在 ChatView)** → Phase 1 改 DS 定义为 racingRed,所有引用自动跟上
- `ChatView.swift`: L459 / 461 / 519 / 538 / 760 / 863 / 883 / 939 / 969 / 979 / 1452 / 1462(11 处 foregroundStyle / fill / stroke / background)
- `StateViews.swift`: L36 / 93(empty state button 背景)

**`DS.Palette.primaryFaint`(4 处,全 ChatView)** → 自动跟 primary 切换
- `ChatView.swift`: L457 / 543 / 938 / 1449

**`DS.Palette.aiGradient`(3 处,全 ChatView)** → Phase 1 实现替换为 `racingGradient`
- `ChatView.swift`: L542(segmented 选中)/ L1055(AIAvatar)/ L1465(滚动到底 fab)

**`DS.Palette.live`(3 处)+ `BrandPalette.liveRed`(3 处)** → live 红双模通用,不变
- ChatView × 3 + MotorsportCard L53 / 65 / 81(Liquid Glass tint + shadow + stroke)

**`DS.Radius.md / pill / bubble`(共 9 处)** → Phase 1 收窄定义后**自动跟上,无需改 ChatView 逻辑**
- ChatView: L1405 / 1449 / 1451(md)/ L516 / 518(pill)/ L1058-1120(bubble 4 处)

**`DS.Motion.layout / press / bubbleEntry`(9 处)** → 沿用,Phase 4-5 新增 `raceEntry / countdown / speedLine` 使用点
- ChatView × 7 + StandingsView × 1

**`DS.Shadow.bubble`(1 处)** + **`DS.Spacing.*`(19+ 处)** → 不动

**改造启示**:
- `DS.Palette.primary` 14 处全部需 racingRed 切换 — 但 ChatView 占 11 处,**Phase 1 改 DS 定义即可,不需逐个改 ChatView call site**
- ChatView 是 token 使用最密集的文件,Phase 3.5 改造时重点验证视觉协调性
- StandingsView 是 token 使用第二密集(spacing/motion/dsListCard)

### A.2 `dsXxx` modifier + Card 组件使用点位

| 模板 | 计数 | 位置摘要 |
|---|---|---|
| `.dsToolCard()` | 1 | ChatView:816(tool step card) |
| `.dsListCard()` | 9 | **全部 StandingsView** (4 系列 × Driver/Team/Constructor row) |
| `.dsGlassPill()` | 1 | MotorsportTimelineView:134(refresh chip) |
| `.dsDetailList()` | 11 | 8 个详情页 + ChatHistoryView + SimpleDriverProfileView + TeamDetailView |
| `MotorsportCard` | 6 | 4 系列 RoundListView + Timeline + FE 多用一次 |
| `StatusBadge` | 7 | 4 系列 RoundListView + Timeline + GlassHeroHeader + FE 多用一次 |
| `WeatherCard` | 4 | 4 系列 RoundDetailView |
| `SegmentedPillPicker` | 6 | 5 处 StandingsView + 1 处 FERoundDetailView |
| `BreathingDot` | 2 | ChatView × 2(均用 `DS.Palette.primary`) |
| `AIAvatar` | 1 | ChatView:1078 |
| `StreamingCursor` | 1 | ChatView:1087 |

**改造启示**:
- `dsListCard()` 9 处全在 StandingsView → Phase 3.4 改 StandingsView 时**不传 `seriesAccent`**(积分榜已按 series picker 过滤,row 内部 series 同一系列,加色条信息冗余)
- `dsDetailList()` 11 处自动跟 Phase 1 改色,无需逐个改
- `MotorsportCard` 6 处 → Phase 2 内部加 `seriesAccent` 默认 nil 保持兼容;Phase 3.2 由调用方传系列(`.f1/.motogp/.wssp/.fe`)
- `StatusBadge` 7 处 → Phase 2 改 `.live` case 内部即可,所有 call site 自动跟上
- `WeatherCard` 4 处 → 圆角 16→12 改组件内部即可
- `SegmentedPillPicker` 6 处 → 内部把 `aiGradient` 替换为 `racingGradient`(默认),Phase 3.1-3.4 各 picker 通过参数覆盖为当前系列 `brandGradient`
- `AIAvatar` / `StreamingCursor` / `BreathingDot` 各 1-2 处(全 ChatView)→ 组件内部改

### A.3 SF Symbol + Liquid Glass + `.tint` 使用点位

**SF Symbol 现状**(主要):
| Symbol | 用法 | 改造决策 |
|---|---|---|
| `steeringwheel` | DesignSystem.swift:293 AIAvatar | 已赛车 icon,保留 |
| `flag.checkered.2.crossed` | CircuitHighlightSection:42 | 已赛车 icon,保留 |
| `lightbulb.fill` | TriviaCard:28 | **AI 助手风,Phase 3.5 替换为 racing icon**(候选: `flag.checkered.2.crossed` / `note.text` / `wrench.and.screwdriver.fill` — pit note 语义) |
| `chevron.down` × 5, `arrow.triangle.2.circlepath` × 5, `checkmark` × 3, 等 | 中性 icon | 不动 |

**`.glassEffect(...)` call sites(2 处)**:
- `ChatView.swift:1462` — fab `.regular.tint(DS.Palette.primary.opacity(0.35))` → Phase 1 自动跟 primary→racingRed → 红 glow
- `MotorsportCard.swift:52-53` — live 状态 `.regular.tint(BrandPalette.liveRed.opacity(0.35))` → 不变

**`.tint(...)` call sites(18 处)**:
- 14 处使用 `series.brandColor` → 已品牌色 driven,不动
- ChatHistoryView:129 `.tint(.red)` → 已红
- GlassHeroHeader:95 `.tint(.white)` ProgressView 默认 → 不动
- SimpleDriverProfileView:27 `.tint(series.brandColor)` → 不动

**改造启示**:
- SF Symbol / Liquid Glass / tint 使用面**相对干净**
- 唯一明显的"AI 助手风"icon `lightbulb.fill` 在 TriviaCard,Phase 3.5 一并替换
- Phase 1 DS 改色后,fab 的 Liquid Glass tint 自动跟到 racingRed,无需 ChatView 改动

---

## 附录 B — 详情页 13 改造点 checklist(Phase 4)

`TeamDetailView` 是通用单文件(`Pole/Features/News/TeamDetailView.swift`),按 `team.series` 渲染对应品牌色 — **文件改 1 次,但需在 4 系列 team 数据上各跑一次视觉验证**。

| # | 系列 | 实际文件 | 关键改动 |
|---|---|---|---|
| 1 | F1 | RaceDetailView.swift(F1 命名) | hero speedLines + SeriesTopAccent + StartLightGrid 倒计时;session 行 dsToolCard;RaceRecap dsHeroBanner |
| 2 | F1 | F1DriverDetailView.swift | 编号大字 numberLarge;历史 row numberMid mono |
| 3 | F1 | (F1 SessionResultsView 内 component) | P1 racingRedFaint 行;圈速 numberMid mono |
| 4 | MotoGP | MotoGPRoundDetailView.swift | 同 #1,SeriesTopAccent(.motogp) |
| 5 | MotoGP | MotoGPRiderDetailView.swift | 同 #2 |
| 6 | MotoGP | (MotoGP SessionResults) | 同 #3 |
| 7 | WSBK | WSBKRoundDetailView.swift | 同 #1,SeriesTopAccent(.wssp) |
| 8 | WSBK | WSSPRiderDetailView.swift | 同 #2 |
| 9 | WSBK | (WSBK SessionResults) | 同 #3 |
| 10 | FE | FERoundDetailView.swift | 同 #1,SeriesTopAccent(.fe) |
| 11 | FE | FEDriverDetailView.swift | 同 #2 |
| 12 | FE | (FE SessionResults) | 同 #3 |
| 13 | 通用 | News/TeamDetailView.swift | dsHeroBanner + SeriesTopAccent(按 team.series 动态);4 系列 team 各跑一次视觉验证 |

---

## 附录 C — 后续 (out of scope, 未来 Phase)

- Phase 6: Widget extension 视觉与主 app 同步(主屏 widget 6 尺寸 + LiveActivity)
- Phase 7: 灵动岛视觉细化
- Phase 8: Onboarding 流程引入(配 StartLightGrid 倒计时入场)
- Phase 9: AI 生成插画:4 系列各一张 onboarding hero image + 4 张 empty state 插画
- Phase 10: 自定义字体引入评估(Saira Condensed OFL,工业感增强)

---

End of spec. Next step: `superpowers:writing-plans` after user approval.
