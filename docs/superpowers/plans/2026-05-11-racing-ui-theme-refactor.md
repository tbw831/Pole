# Racing UI Theme Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Pole iOS app 当前的 "AI 助手 / 豆包风" 视觉(iOS 蓝、圆润字体、柔和 24px 圆角)改造为 "非常有赛车风格"(沥青黑 + F1 红 accent、SF 工业字 + SF Mono 数字、棋盘格 / 起跑灯 / 系列色条 / 速度线 4 装饰元素、默认 Dark)。

**Architecture:** Token-first → 页面分批的 5 Phase 顺序改造。Phase 1 重写 `DS` namespace(色/圆角/字/动/影)+ 接入 Light/Dark 切换;Phase 2 加 4 个新装饰组件 + 升级 `dsXxx` modifier;Phase 3 按 tab 顺序迁移 5 个主页;Phase 4 批量改造 13 个详情页改造点;Phase 5 动效 / 触觉打磨。每 Phase 独立 commit / 独立 revert。

**Tech Stack:** SwiftUI / iOS 26.2 / Swift 5.0 / `UIColor` dynamic color API(双模)/ Liquid Glass `glassEffect` / Swift Testing(现有 ViewModel 测试不受影响)/ SwiftUI `#Preview` 做视觉验收。

**参考文档**: spec 在 `docs/superpowers/specs/2026-05-11-racing-ui-theme-design.md`,附录 A 含现状代码点位扫描结果。

---

## File Structure(全 plan 涉及文件)

### Create(新增 3 个文件)
- `Pole/Domain/AppearanceMode.swift` — `AppearanceMode` enum + `AppearanceStore` ObservableObject
- `Pole/Theme/RacingComponents.swift` — `SeriesTopAccent` / `CheckerStripe` / `StartLightGrid` / `SpeedLinesOverlay` 4 个装饰组件 + `.speedLines()` modifier

### Modify(主要 ~25 个文件)
- `Pole/Theme/DesignSystem.swift` — Palette / Radius / Font / Motion / Shadow 全量重写;新加 `dsHeroBanner` / `dsRacingButton` / `dsLiveBadge` 等 modifier
- `Pole/Theme/SeriesTheme.swift` — `BrandPalette.aiGradient` 实现替换为 `racingGradient`
- `Pole/PoleApp.swift` — 注入 `preferredColorScheme`
- `Pole/Features/Settings/SettingsView.swift` — 新增"外观" + "Greeting 模式" + "减少装饰" 三 toggle / picker
- `Pole/Features/Chat/ChatView.swift` — Greeting hero / 流式光标 / send 按钮 / 用户气泡 / fab 改色,`lightbulb.fill` 替换
- `Pole/Features/Chat/TriviaCard.swift` — `dsHeroBanner` 包装 + icon 替换
- `Pole/Features/Chat/ChatViewModel.swift` — 加 `greetingMode` (racing / friendly)
- `Pole/Features/Standings/StandingsView.swift` — 排行 row 字体 / 数字 mono / Top 3 强调 / section header
- `Pole/Features/Motorsport/MotorsportTimelineView.swift` — Timeline 月份 header / Empty state
- `Pole/Features/Motorsport/MotorsportListView.swift` — Segmented picker 色
- `Pole/Features/Common/MotorsportCard.swift` — 加 `seriesAccent` 顶条
- `Pole/Features/Common/StatusBadge.swift` — `.live` 用 `dsLiveBadge`
- `Pole/Features/Common/WeatherCard.swift` — 圆角 16→12
- `Pole/Features/Common/GlassHeroHeader.swift` — 加 `speedLines` 参数
- `Pole/Features/Follow/FollowFeedView.swift` — 列表 row seriesAccent / Empty state
- `Pole/Features/F1/RaceListView.swift` — `MotorsportCard` 传 `seriesAccent`
- `Pole/Features/F1/RaceDetailView.swift` — Hero + StartLightGrid + sessions + RaceRecap
- `Pole/Features/F1/F1DriverDetailView.swift` — 编号大字 / 历史 row mono
- `Pole/Features/MotoGP/MotoGPRoundListView.swift` — 同 RaceListView
- `Pole/Features/MotoGP/MotoGPRoundDetailView.swift` — 同 RaceDetailView 模式
- `Pole/Features/MotoGP/MotoGPRiderDetailView.swift` — 同 F1DriverDetailView
- `Pole/Features/WSBK/WSBKRoundListView.swift`, `WSBKRoundDetailView.swift`, `WSSPRiderDetailView.swift` — 同上
- `Pole/Features/FE/FERoundListView.swift`, `FERoundDetailView.swift`, `FEDriverDetailView.swift` — 同上
- `Pole/Features/News/TeamDetailView.swift` — `dsHeroBanner` + 动态 `SeriesTopAccent`

### Test
不增加 unit test(视觉改造)。每个组件用 SwiftUI `#Preview` 验收 Light + Dark + Dynamic Type Large。现有 `PoleTests/` Swift Testing 套件不动。

---

## Phase 1 — DS Token + Light/Dark 切换接入

**目标**:`DS` namespace 全量翻译为赛车语言 + Light/Dark 切换能用。

### Task 1: 创建 AppearanceMode + AppearanceStore

**Files:**
- Create: `Pole/Domain/AppearanceMode.swift`

- [ ] **Step 1: 创建文件**

```swift
import SwiftUI

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
            self.current = .dark   // 首次启动默认 Dark
        }
    }
}
```

- [ ] **Step 2: 把文件加入 Xcode project**

Xcode 中拖 `Pole/Domain/AppearanceMode.swift` 加入 Pole target,确保 Target Membership 勾选 Pole(不勾 PoleWidgets)。Mac 端执行:
```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pole/Domain/AppearanceMode.swift Pole.xcodeproj
git commit -m "feat(theme): add AppearanceMode + AppearanceStore"
```

---

### Task 2: PoleApp 注入 preferredColorScheme

**Files:**
- Modify: `Pole/PoleApp.swift`

- [ ] **Step 1: 加 @StateObject + .preferredColorScheme**

在 `PoleApp` 结构体内加 `@StateObject private var appearance = AppearanceStore.shared`,在 `WindowGroup { ContentView() ... }` 链上加 `.preferredColorScheme(appearance.current.colorScheme)`:

```swift
@main
struct PoleApp: App {
    @StateObject private var appearance = AppearanceStore.shared
    // ... 现有 sharedModelContainer ...

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearance.current.colorScheme)
                .modelContainer(sharedModelContainer)
        }
    }
}
```

- [ ] **Step 2: Build 验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 模拟器启动,验证默认 Dark**

```bash
xcrun simctl boot 'iPhone 16 Pro' 2>/dev/null || true
open -a Simulator
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /tmp/Pole-derived run
```
Expected: App 启动后显示为 Dark 模式(背景深色)

- [ ] **Step 4: Commit**

```bash
git add Pole/PoleApp.swift
git commit -m "feat(theme): inject preferredColorScheme via AppearanceStore"
```

---

### Task 3: Settings 加"外观" picker(验证 Light/Dark 切换链路)

**Files:**
- Modify: `Pole/Features/Settings/SettingsView.swift`

- [ ] **Step 1: 读现有 SettingsView 结构**

```bash
sed -n '1,50p' /Users/bytedance/project/Pole/Pole/Features/Settings/SettingsView.swift
```
Expected: 看清 View 结构(可能是 `Form` 或 `List`),找 section 插入位置

- [ ] **Step 2: 加 @StateObject + Section**

在 SettingsView body 加 `@StateObject private var appearance = AppearanceStore.shared`,插入一个新 Section 在 List 顶部:

```swift
Section {
    SegmentedPillPicker(
        selection: $appearance.current,
        items: AppearanceMode.allCases
    ) { mode in
        Text(mode.displayLabel)
    }
    .padding(.vertical, DS.Spacing.xs)
} header: {
    Text(L10n.t(zh: "外观", en: "Appearance"))
}
```

- [ ] **Step 3: Build + 启动模拟器验证切换**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```
然后手动:启动 app → 设置 tab → 切 Light → 验证整 app 转 Light,切 Dark 转回 Dark,切跟系统跟随系统切换。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/Settings/SettingsView.swift
git commit -m "feat(settings): add Appearance segmented picker"
```

---

### Task 4: DS.Palette 重写 — 加 racing/tarmac/decorOnSurface,删 primary 系列

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:42-83`

- [ ] **Step 1: 替换 DS.Palette 整 enum body**

把 `Pole/Theme/DesignSystem.swift` 的 `public enum Palette { ... }` 整段(L42-83)替换为:

```swift
public enum Palette {
    // ===== Racing 红系: 双模通用 =====
    public static let racingRed     = Color(red: 0.882, green: 0.024, blue: 0)
    public static let racingRedSoft = Color(red: 1.000, green: 0.122, blue: 0.102)
    public static let racingRedDeep = Color(red: 0.612, green: 0.020, blue: 0)
    public static let racingRedFaint = racingRed.opacity(0.10)

    public static let racingGradient = LinearGradient(
        colors: [racingRedDeep, racingRed, racingRedSoft],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    public static let racingGradientStrong = LinearGradient(
        colors: [racingRedDeep, racingRed],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // ===== 向后兼容 alias(让 14 处 .primary 引用直接编译通过,无需逐个改 call site)=====
    public static let primary      = racingRed
    public static let primarySoft  = racingRedSoft
    public static let primaryDeep  = racingRedDeep
    public static let primaryFaint = racingRedFaint
    public static let aiGradient   = racingGradient
    public static let aiGradientStrong = racingGradientStrong

    // ===== Tarmac 中性: UIColor dynamic 双模 =====
    public static let tarmacBg = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1)
            : UIColor.systemBackground
    })

    public static let tarmacFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1)
            : UIColor.secondarySystemBackground
    })

    public static let tarmacCard = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.137, green: 0.137, blue: 0.153, alpha: 1)
            : UIColor.tertiarySystemBackground
    })

    public static let tarmacHairline = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.180, green: 0.180, blue: 0.200, alpha: 1)
            : UIColor.separator
    })

    public static let decorOnSurface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.06)
    })

    // ===== 状态色(Dark 下加饱和)=====
    public static let live      = Color(red: 1.000, green: 0.176, blue: 0.176)
    public static let upcoming  = Color(red: 0.302, green: 0.659, blue: 1.000)
    public static let finished  = Color(.systemGray)
    public static let postponed = Color.orange

    // ===== AI 消息气泡(双模 dynamic)=====
    public static var aiBubbleFill: Color { tarmacCard }
    public static var aiBubbleStroke: Color { tarmacHairline }
    public static var toolCardFill: Color { tarmacCard }
    public static var inputFill: Color { tarmacFill }
}
```

**关键**:保留 `primary` / `primarySoft` 等 alias 是为了让 14 处 ChatView call site 编译通过,实际值已变成 racingRed。后续 Phase 3.5 改 ChatView 时可以选择是否 rename。

- [ ] **Step 2: Build 验证(应该 0 改 ChatView call site 就能编译通过)**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -30
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 启动 app,视觉确认主 CTA 变红**

模拟器跑 app,Settings 中"外观" picker 选中态应为红色;ChatView 输入框 send 按钮应该是红渐变(虽然 ChatView 还没改);MotorsportListView 的 segmented picker 选中态应该也是红渐变。

- [ ] **Step 4: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): rewrite DS.Palette to racing red + tarmac neutral scale

- racingRed/Soft/Deep/Faint + racingGradient as the primary brand color
- tarmacBg/Fill/Card/Hairline as Dark-first neutral scale (dynamic with Light fallback)
- decorOnSurface for CheckerStripe / SpeedLines default
- Backward-compatible aliases (primary, aiGradient, etc.) keep existing
  ChatView call sites compiling; values now resolve to racing red.
- live status color saturation boosted for Dark mode visibility"
```

---

### Task 5: DS.Radius 收窄

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:28-38`

- [ ] **Step 1: 替换 DS.Radius enum**

```swift
public enum Radius {
    public static let sm: CGFloat = 4     // 旧 8
    public static let md: CGFloat = 8     // 旧 12
    public static let lg: CGFloat = 12    // 旧 16
    public static let xl: CGFloat = 16    // 旧 20
    public static let xxl: CGFloat = 20   // 旧 24
    public static let bubble: CGFloat = 14  // 旧 20
    public static let pill: CGFloat = 18    // 旧 22
}
```

- [ ] **Step 2: Build + 视觉验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。模拟器启动后所有圆角元素(气泡、卡片、segmented picker)应该明显比之前 sharp。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): narrow DS.Radius by ~30% for industrial precision feel"
```

---

### Task 6: DS.Font 去 rounded + 新增数字 mono 三档

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:87-100`

- [ ] **Step 1: 替换 DS.Font enum**

```swift
public enum Font {
    public static let bubble = SwiftUI.Font.system(.footnote)
    public static let bubbleBold = SwiftUI.Font.system(.footnote, weight: .semibold)
    public static let timestamp = SwiftUI.Font.caption2
    public static let toolLabel = SwiftUI.Font.caption.weight(.semibold)
    public static let toolPreview = SwiftUI.Font.caption2

    // ===== 大标题: 去 rounded, 加 Heavy weight =====
    public static let heroDisplay = SwiftUI.Font.system(.largeTitle, weight: .heavy)
    public static let heroTitle = SwiftUI.Font.system(.title2, weight: .bold)
    public static let heroSubtitle = SwiftUI.Font.footnote

    // ===== 赛事数字 SF Mono =====
    public static let numberLarge = SwiftUI.Font.system(size: 32, weight: .heavy, design: .default).monospacedDigit()
    public static let numberMid = SwiftUI.Font.system(size: 20, weight: .semibold, design: .monospaced)
    public static let numberSmall = SwiftUI.Font.system(size: 14, weight: .medium, design: .monospaced)
}
```

- [ ] **Step 2: Build + 视觉验证 — heroTitle 旧 call site 大字应不再 rounded**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。ChatView Greeting 大字 "早上好,Pole" 应该从 rounded 变成 default SF。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): drop rounded design, add heavy weight + SF Mono number tiers

- heroDisplay/heroTitle: SF default (not rounded), bumped weight to Heavy/Bold
- numberLarge/Mid/Small: SF Mono variants for racing telemetry numbers"
```

---

### Task 7: DS.Motion 加 raceEntry / countdown / speedLine

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:117-128`

- [ ] **Step 1: 在 DS.Motion enum 末尾加 3 个新静态属性**

```swift
public enum Motion {
    public static let bubbleEntry: Animation = .spring(response: 0.35, dampingFraction: 0.78)
    public static let layout: Animation = .easeOut(duration: 0.2)
    public static let press: Animation = .spring(response: 0.18, dampingFraction: 0.7)
    public static let cursorBlink: Animation = .easeInOut(duration: 0.6).repeatForever(autoreverses: true)

    // ===== 新增 =====
    public static let raceEntry: Animation = .spring(response: 0.28, dampingFraction: 0.7)
    public static let countdown: Animation = .easeIn(duration: 0.4)
    public static let speedLine: Animation = .linear(duration: 1.2).repeatForever(autoreverses: false)
}
```

- [ ] **Step 2: Build 验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): add raceEntry / countdown / speedLine motion presets"
```

---

### Task 8: DS.Shadow 加 racingGlow / carbonInset

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:104-115`

- [ ] **Step 1: 在 DS.Shadow enum 末尾加新 ShadowStyle 静态属性**

```swift
public enum Shadow {
    public static let bubble = ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    public static let card   = ShadowStyle(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    public static let aiHero = ShadowStyle(color: Palette.racingRed.opacity(0.35), radius: 20, x: 0, y: 6)

    // ===== 新增 =====
    public static let racingGlow = ShadowStyle(color: Palette.racingRed.opacity(0.55), radius: 16, x: 0, y: 4)
    public static let carbonInset = ShadowStyle(color: .black.opacity(0.5), radius: 2, x: 0, y: -1)

    public struct ShadowStyle: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }
}
```

注意:`aiHero` 已用 `Palette.primary` (现在 alias 到 `racingRed`),改为显式 `Palette.racingRed`,语义更清晰。

- [ ] **Step 2: Build 验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): add racingGlow / carbonInset shadow presets"
```

---

### Task 9: SeriesTheme.BrandPalette.aiGradient 替换为 racing 红渐变(防止双重定义不一致)

**Files:**
- Modify: `Pole/Theme/SeriesTheme.swift:44-49`

- [ ] **Step 1: 把 BrandPalette.aiGradient 显式改用 DS.Palette.racingGradient**

```swift
// hero CTA 渐变 — 红到亮红(现统一走 DS.Palette.racingGradient 避免重复定义)
public static let aiGradient = DS.Palette.racingGradient
```

- [ ] **Step 2: Build + 视觉验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。ChatView fab、send 按钮等已经显示红渐变。

- [ ] **Step 3: Commit + Phase 1 整体收尾**

```bash
git add Pole/Theme/SeriesTheme.swift
git commit -m "feat(theme): unify BrandPalette.aiGradient with DS.Palette.racingGradient"
```

**Phase 1 出口验收**:模拟器启动 app → 默认 Dark → Settings 切 Light/系统都即时生效 → 所有原 .primary 引用呈现 racingRed → 旧业务页 layout 不变。

---

## Phase 2 — 装饰组件 + DS Modifier 升级

**目标**:4 个新装饰组件 + 7 个 dsXxx modifier 升级 / 新增。

### Task 10: 创建 SeriesTopAccent 组件

**Files:**
- Create: `Pole/Theme/RacingComponents.swift`

- [ ] **Step 1: 创建文件,只放 SeriesTopAccent**

```swift
import SwiftUI

// MARK: - SeriesTopAccent
//
// 卡片顶部 3px 系列品牌色条 + 右端拖尾渐变到透明(赛旗末端语义)。
// 用法: 在 dsListCard / MotorsportCard / driver / team 卡片顶部叠加。

public struct SeriesTopAccent: View {
    let series: MotorsportSeries
    var height: CGFloat = 3

    public init(series: MotorsportSeries, height: CGFloat = 3) {
        self.series = series
        self.height = height
    }

    public var body: some View {
        LinearGradient(
            colors: [series.brandColor, series.brandColor.opacity(0.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("SeriesTopAccent · all series") {
    VStack(spacing: 8) {
        SeriesTopAccent(series: .f1)
        SeriesTopAccent(series: .motogp)
        SeriesTopAccent(series: .wssp)
        SeriesTopAccent(series: .fe)
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}
```

- [ ] **Step 2: 加入 Xcode + Build**

Xcode 拖入文件,Target Membership = Pole。
```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Xcode #Preview 应渲染 4 条系列色条(红/橙/绿/青)+ 右端拖尾。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/RacingComponents.swift Pole.xcodeproj
git commit -m "feat(theme): add SeriesTopAccent decorative component"
```

---

### Task 11: 加 CheckerStripe 组件

**Files:**
- Modify: `Pole/Theme/RacingComponents.swift`(在文件末尾追加)

- [ ] **Step 1: 追加 CheckerStripe**

```swift
// MARK: - CheckerStripe
//
// 黑白(双模色差感知)棋盘格。
// Layout: horizontal(底部一条) / vertical(右侧一条) / fill(满铺背景纹理)
// trait-aware: Dark 用 white@opacity, Light 用 black@opacity 在透明背景上画格

public struct CheckerStripe: View {
    public enum Layout { case horizontal, vertical, fill }

    let layout: Layout
    var cellSize: CGFloat
    var opacity: Double

    @Environment(\.colorScheme) private var colorScheme

    public init(_ layout: Layout, cellSize: CGFloat = 6, opacity: Double = 1.0) {
        self.layout = layout
        self.cellSize = cellSize
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { context, size in
            let color = (colorScheme == .dark ? Color.white : Color.black).opacity(opacity)
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))
            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c).isMultiple(of: 2) {
                        let rect = CGRect(x: CGFloat(c) * cellSize,
                                          y: CGFloat(r) * cellSize,
                                          width: cellSize,
                                          height: cellSize)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .frame(maxWidth: layout == .vertical ? cellSize * 2 : .infinity,
               maxHeight: layout == .horizontal ? cellSize * 2 : .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("CheckerStripe · variants") {
    VStack(spacing: 16) {
        CheckerStripe(.horizontal)
            .frame(height: 12)
        CheckerStripe(.vertical)
            .frame(width: 12, height: 60)
        CheckerStripe(.fill, opacity: 0.06)
            .frame(width: 200, height: 100)
            .background(DS.Palette.tarmacBg)
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}
```

- [ ] **Step 2: Build + Preview 验证 4 个尺寸 + Light/Dark 都正常**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Xcode #Preview 渲染 horizontal/vertical/fill 三种,Dark 下白色格,Light 下黑色格。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/RacingComponents.swift
git commit -m "feat(theme): add CheckerStripe (trait-aware Canvas-drawn flag pattern)"
```

---

### Task 12: 加 StartLightGrid 组件

**Files:**
- Modify: `Pole/Theme/RacingComponents.swift`(追加)

- [ ] **Step 1: 追加 StartLightGrid**

```swift
// MARK: - StartLightGrid
//
// F1 起跑灯阵列 — 5 个红圆灯。
// .countdown(litCount: 0..5): 递进点亮,模拟 5-1 倒计时
// .lightsOut: 全灭,模拟起步瞬间
// .idle: 全灭,无动画(Empty state 用)

public struct StartLightGrid: View {
    public enum Mode: Equatable {
        case countdown(litCount: Int)
        case lightsOut
        case idle
    }

    let mode: Mode
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(mode: Mode, size: CGFloat = 14) {
        self.mode = mode
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.5) {
            ForEach(0..<5, id: \.self) { idx in
                Circle()
                    .fill(isLit(idx) ? DS.Palette.racingRed : DS.Palette.tarmacHairline)
                    .frame(width: size, height: size)
                    .shadow(
                        color: isLit(idx) ? DS.Palette.racingRed.opacity(0.6) : .clear,
                        radius: size * 0.4
                    )
                    .animation(reduceMotion ? nil : DS.Motion.countdown, value: mode)
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private func isLit(_ idx: Int) -> Bool {
        switch mode {
        case .idle, .lightsOut: return false
        case .countdown(let litCount): return idx < litCount
        }
    }

    private var accessibilityText: String {
        switch mode {
        case .idle: return L10n.t(zh: "起跑灯待机", en: "Start lights idle")
        case .lightsOut: return L10n.t(zh: "起跑灯熄灭, 比赛已开始", en: "Lights out, race started")
        case .countdown(let n): return L10n.t(zh: "起跑倒计时 \(n) 灯", en: "Countdown, \(n) lights lit")
        }
    }
}

#Preview("StartLightGrid · all modes") {
    VStack(spacing: 24) {
        StartLightGrid(mode: .idle)
        StartLightGrid(mode: .countdown(litCount: 1))
        StartLightGrid(mode: .countdown(litCount: 3))
        StartLightGrid(mode: .countdown(litCount: 5))
        StartLightGrid(mode: .lightsOut)
    }
    .padding(32)
    .background(DS.Palette.tarmacBg)
}
```

- [ ] **Step 2: Build + Preview 验证 5 种 mode 渲染正确**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Preview 显示 5 个 mode:全灭 / 1 亮 / 3 亮 / 5 亮 / 起步全灭。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/RacingComponents.swift
git commit -m "feat(theme): add StartLightGrid (F1 5-light countdown indicator)"
```

---

### Task 13: 加 SpeedLinesOverlay + `.speedLines()` modifier

**Files:**
- Modify: `Pole/Theme/RacingComponents.swift`(追加)

- [ ] **Step 1: 追加 SpeedLinesOverlay + modifier**

```swift
// MARK: - SpeedLinesOverlay
//
// 45° 半透明斜线装饰。
// 默认在容器右下 1/3 区铺 4-6 条斜线,alpha 0.06(Dark)/0.04(Light)。
// animated: true 时配 speedLine motion 滚动。

public struct SpeedLinesOverlay: ViewModifier {
    var color: Color
    var animated: Bool

    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    Canvas { context, size in
                        let stripeWidth: CGFloat = 1.5
                        let gap: CGFloat = 14
                        let angle: Double = -45 * .pi / 180
                        let total = size.width + size.height
                        var x: CGFloat = -size.height + (animated && !reduceMotion ? phase : 0)
                        while x < total {
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                            path = path.strokedPath(.init(lineWidth: stripeWidth))
                            context.fill(path, with: .color(color))
                            x += gap
                        }
                        _ = angle
                    }
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                guard animated && !reduceMotion else { return }
                withAnimation(DS.Motion.speedLine) { phase = 14 }
            }
    }
}

public extension View {
    /// 在容器上叠加 45° 速度线装饰,默认色 decorOnSurface(双模 alpha 不同)。
    func speedLines(color: Color = DS.Palette.decorOnSurface, animated: Bool = false) -> some View {
        modifier(SpeedLinesOverlay(color: color, animated: animated))
    }
}

#Preview("SpeedLinesOverlay") {
    VStack(spacing: 16) {
        RoundedRectangle(cornerRadius: 12)
            .fill(DS.Palette.tarmacCard)
            .frame(height: 80)
            .speedLines()
            .overlay(Text("Static").foregroundStyle(.secondary))

        RoundedRectangle(cornerRadius: 12)
            .fill(DS.Palette.tarmacCard)
            .frame(height: 80)
            .speedLines(animated: true)
            .overlay(Text("Animated").foregroundStyle(.secondary))
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}
```

- [ ] **Step 2: Build + Preview 验证斜线渲染**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Preview 静态版有斜线,动态版斜线缓慢左→右滚动(reduceMotion 关闭时静止)。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/RacingComponents.swift
git commit -m "feat(theme): add SpeedLinesOverlay + .speedLines() modifier"
```

---

### Task 14: dsListCard 加 seriesAccent 参数(向后兼容)

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:217-230`

- [ ] **Step 1: 替换 dsListCard modifier signature**

把原 `func dsListCard() -> some View` (L217 左右)替换为:

```swift
/// 通用 list row 卡片包装。
/// - seriesAccent: 传系列后顶部加 3px SeriesTopAccent 色条;nil 时纯净卡片(向后兼容)。
func dsListCard(seriesAccent: MotorsportSeries? = nil) -> some View {
    VStack(spacing: 0) {
        if let series = seriesAccent {
            SeriesTopAccent(series: series)
        }
        self
            .padding(.horizontal, DS.Spacing.lg - 2)
            .padding(.vertical, DS.Spacing.md)
    }
    .background(
        DS.Palette.tarmacFill,
        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
    )
    .overlay(
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Palette.tarmacHairline, lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
}
```

- [ ] **Step 2: Build — StandingsView 9 处 `.dsListCard()` 不传参,旧行为(`seriesAccent: nil`)**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。StandingsView 排行 row 视觉不变(还没传 seriesAccent),底色从旧 secondarySystemBackground 改为 tarmacFill(Dark 下 #18181B)。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): dsListCard accepts optional seriesAccent + uses tarmac scale"
```

---

### Task 15: dsAIBubble / dsToolCard / dsGlassPill / dsDetailList fallback 改色到 tarmac

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:143-213`(各 modifier 内 fallback 路径)

- [ ] **Step 1: 替换 dsAIBubble 的 else 分支(L150-160)**

把原 fallback:
```swift
} else {
    self
        .background(DS.Palette.aiBubbleFill, ...)
        .overlay(... strokeBorder(DS.Palette.aiBubbleStroke ...))
        .shadow(...)
}
```
改为(因 aiBubbleFill/Stroke 已 dynamic 走 tarmac,逻辑维持,但加 carbonInset shadow):

实际上 Task 4 已经把 `aiBubbleFill` / `aiBubbleStroke` 改为 dynamic tarmac,fallback 不需要逻辑改动 — 跳过 dsAIBubble。**实际需要改的只有 dsListCard(Task 14 完成)和 dsDetailList 底色:**

替换 `dsDetailList()` (L207-213):
```swift
func dsDetailList() -> some View {
    self
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Palette.tarmacBg)
        .listSectionSpacing(DS.Spacing.md)
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 视觉确认 — 任意详情页(如 MotorsportTimelineView 进入 F1 比赛)Dark 下背景应该是沥青黑而不是系统 black**

启动模拟器,进入某场比赛详情页。Dark 模式下背景为 `#0E0E10` tarmacBg。

- [ ] **Step 4: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): dsDetailList uses tarmacBg for tarmac-paddock background"
```

---

### Task 16: 加 dsHeroBanner modifier

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift`(在 dsListCard 后追加)

- [ ] **Step 1: 追加 dsHeroBanner**

```swift
/// hero 大卡片(Settings header / RoundDetail / TriviaCard 等):
/// tarmacBg 底 + speedLines 装饰 + 可选顶部 SeriesTopAccent 色条。
func dsHeroBanner(seriesAccent: MotorsportSeries? = nil) -> some View {
    VStack(spacing: 0) {
        if let series = seriesAccent {
            SeriesTopAccent(series: series)
        }
        self
            .padding(DS.Spacing.lg)
    }
    .background(
        DS.Palette.tarmacBg,
        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
    )
    .overlay(
        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
            .strokeBorder(DS.Palette.tarmacHairline, lineWidth: 0.5)
    )
    .speedLines()
    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
}
```

- [ ] **Step 2: Build + 写一个 Preview 验证**

在 DesignSystem.swift 末尾(或 RacingComponents.swift 内)加:
```swift
#Preview("dsHeroBanner") {
    VStack(spacing: 16) {
        Text("POLE · 赛车追踪")
            .font(DS.Font.heroDisplay)
            .foregroundStyle(.white)
            .dsHeroBanner()

        Text("hero with series")
            .font(DS.Font.heroTitle)
            .foregroundStyle(.white)
            .dsHeroBanner(seriesAccent: .f1)
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}
```

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Preview 显示沥青底 + 速度线 + (第二个有红色顶条)的 hero。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): add dsHeroBanner modifier (tarmac + speedLines + opt SeriesTopAccent)"
```

---

### Task 17: 加 dsRacingButton ButtonStyle

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift`(在 modifier 区追加 + 新建 struct)

- [ ] **Step 1: 在 DesignSystem.swift 末尾加 DSRacingButtonStyle struct**

```swift
// MARK: - dsRacingButton ButtonStyle

public struct DSRacingButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.heroSubtitle.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md - 2)
            .background(
                DS.Palette.racingGradient,
                in: RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
            )
            .shadow(
                color: DS.Shadow.racingGlow.color,
                radius: DS.Shadow.racingGlow.radius,
                x: DS.Shadow.racingGlow.x,
                y: DS.Shadow.racingGlow.y
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DS.Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { HapticFeedback.lightImpact() }
            }
    }
}

public extension ButtonStyle where Self == DSRacingButtonStyle {
    static var dsRacingButton: DSRacingButtonStyle { .init() }
}

#Preview("dsRacingButton") {
    VStack(spacing: 16) {
        Button("发送") { }.buttonStyle(.dsRacingButton)
        Button("去赛车 tab 发现") { }.buttonStyle(.dsRacingButton)
    }
    .padding()
    .background(DS.Palette.tarmacBg)
}
```

- [ ] **Step 2: Build + Preview**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Preview 显示红渐变按钮 + glow,按下时缩 0.97。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): add DSRacingButtonStyle (.dsRacingButton) ButtonStyle"
```

---

### Task 18: 加 dsLiveBadge modifier + 集成到 StatusBadge

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift`(modifier 追加)
- Modify: `Pole/Features/Common/StatusBadge.swift`

- [ ] **Step 1: 在 DesignSystem.swift 加 dsLiveBadge**

```swift
/// `StatusBadge.live` 专用 — 红底脉冲 + 右拖尾棋盘格。
func dsLiveBadge() -> some View {
    HStack(spacing: 4) {
        self
        CheckerStripe(.horizontal, cellSize: 3)
            .frame(width: 8, height: 6)
    }
    .padding(.horizontal, DS.Spacing.sm)
    .padding(.vertical, DS.Spacing.xxs)
    .background(
        DS.Palette.live.opacity(0.18),
        in: Capsule()
    )
    .overlay(
        Capsule().strokeBorder(DS.Palette.live.opacity(0.6), lineWidth: 0.8)
    )
    .foregroundStyle(DS.Palette.live)
}
```

- [ ] **Step 2: 改 StatusBadge.swift 的 .live case 用 dsLiveBadge**

读现有 StatusBadge.swift 找 `.live` 分支:
```bash
sed -n '1,80p' /Users/bytedance/project/Pole/Pole/Features/Common/StatusBadge.swift
```

在 `.live` 分支(或对应 view rendering)外层应用 `.dsLiveBadge()`,而不是原 capsule + foregroundStyle。具体代码取决于现有结构,核心是把 `Text("Live")` 或脉冲点 wrap 进 `dsLiveBadge()` 替代旧 Capsule + bg。

例如(若现状是 `Text("Live").padding(...).background(Color.red.opacity(0.2), in: Capsule())`):
```swift
case .live:
    HStack(spacing: 4) {
        Circle().fill(DS.Palette.live).frame(width: 6, height: 6)
            .scaleEffect(animating ? 1.0 : 0.7)
            .opacity(animating ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: animating)
        Text(status.displayLabel).font(.caption.weight(.semibold))
    }
    .dsLiveBadge()
```

(完整修改取决于 StatusBadge.swift 现有代码;step 完成后跑 build 验证.)

- [ ] **Step 3: Build + 在 MotorsportListView 中找一场 live 比赛(如不存在,手动 mock currentStatus 测试 Preview)验证视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Pole/Theme/DesignSystem.swift Pole/Features/Common/StatusBadge.swift
git commit -m "feat(theme): add dsLiveBadge with checker tail and integrate into StatusBadge.live"
```

---

### Task 19: AIAvatar 渐变切换 + 维持 steeringwheel icon

**Files:**
- Modify: `Pole/Theme/DesignSystem.swift:281-302`(AIAvatar struct)

- [ ] **Step 1: 把 `Circle().fill(DS.Palette.aiGradient)` 显式改用 `racingGradient`**

实际上 `aiGradient` 现在已经 alias 到 `racingGradient`,**视觉已变化**。但语义上换名更清晰。把 AIAvatar body 内:

```swift
Circle()
    .fill(DS.Palette.aiGradient)
```
改为:
```swift
Circle()
    .fill(DS.Palette.racingGradient)
```

shadow 颜色 `DS.Palette.primary.opacity(...)` 改为:
```swift
.shadow(color: DS.Palette.racingRed.opacity(size == .large ? 0.4 : 0.25),
        radius: size == .large ? 20 : 6, y: size == .large ? 6 : 2)
```

- [ ] **Step 2: Build + 视觉验证 ChatView Greeting hero**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。AI tab Greeting 大头像应该红渐变。

- [ ] **Step 3: Commit**

```bash
git add Pole/Theme/DesignSystem.swift
git commit -m "feat(theme): AIAvatar uses explicit racingGradient (semantic clarity)"
```

**Phase 2 出口验收**:
- `RacingComponents.swift` 4 个组件 #Preview Light + Dark 通过
- `dsHeroBanner` / `dsRacingButton` / `dsLiveBadge` 3 个新 modifier #Preview 通过
- `StatusBadge.live` 视觉(脉冲 + 棋盘格拖尾)生效
- 旧业务页面 layout 0 改动

---

## Phase 3 — 5 Tab 主页迁移

按顺序 3.1 → 3.5,每 tab 独立 commit。

### Task 20: Tab 5 设置 — Header banner + CheckerStripe + 版本号 SF Mono

**Files:**
- Modify: `Pole/Features/Settings/SettingsView.swift`

- [ ] **Step 1: 读 SettingsView 当前结构 + 找版本号 + about 区位置**

```bash
sed -n '1,140p' /Users/bytedance/project/Pole/Pole/Features/Settings/SettingsView.swift
```

- [ ] **Step 2: 在 List 顶部插入 hero banner**

```swift
// 在 Form / List body 顶部, 先于"外观" Section 加 banner
Section {
    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
        Text("POLE")
            .font(DS.Font.heroDisplay)
            .foregroundStyle(.white)
            .tracking(2)
        Text(L10n.t(zh: "赛车追踪", en: "Race tracker"))
            .font(DS.Font.numberSmall)
            .foregroundStyle(.white.opacity(0.7))
        CheckerStripe(.horizontal, cellSize: 4)
            .frame(height: 6)
            .padding(.top, DS.Spacing.xs)
    }
    .dsHeroBanner()
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())
}
```

- [ ] **Step 3: 把版本号字号改 numberSmall SF Mono**

找 `Text("v1.0.0")` 或类似(可能在"About" 或类似 Section),包装为:
```swift
Text("v1.0.0 · BUILD 2026.05.11")
    .font(DS.Font.numberSmall)
    .foregroundStyle(.secondary)
```

- [ ] **Step 4: Build + 模拟器视觉验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED + Settings tab 顶部有 POLE hero banner + 棋盘格 + 版本号 SF Mono

- [ ] **Step 5: Commit**

```bash
git add Pole/Features/Settings/SettingsView.swift
git commit -m "feat(settings): hero banner with CheckerStripe + SF Mono build info"
```

---

### Task 21: Settings 加 Greeting 模式 + 减少装饰 双 toggle

**Files:**
- Modify: `Pole/Features/Settings/SettingsView.swift`

- [ ] **Step 1: 加 @AppStorage 两 boolean**

在 SettingsView struct 内:
```swift
@AppStorage("greetingMode") private var greetingModeRaw: String = "racing"
@AppStorage("reducedDecor") private var reducedDecor: Bool = false
```

- [ ] **Step 2: 加 Section "AI 助手"**

```swift
Section(L10n.t(zh: "AI 助手", en: "AI Assistant")) {
    Picker(L10n.t(zh: "Greeting 风格", en: "Greeting style"),
           selection: $greetingModeRaw) {
        Text(L10n.t(zh: "赛车 telemetry", en: "Racing telemetry")).tag("racing")
        Text(L10n.t(zh: "友好对话", en: "Friendly")).tag("friendly")
    }
}
```

- [ ] **Step 3: 加 Section "视觉装饰"**

```swift
Section(L10n.t(zh: "视觉装饰", en: "Visual Decoration")) {
    Toggle(L10n.t(zh: "减少装饰", en: "Reduce decoration"),
           isOn: $reducedDecor)
}
```

- [ ] **Step 4: Build + 视觉验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Settings tab 有 3 个 toggle/picker(外观 / Greeting / 装饰)。

- [ ] **Step 5: Commit**

```bash
git add Pole/Features/Settings/SettingsView.swift
git commit -m "feat(settings): add greetingMode (racing/friendly) + reducedDecor toggles"
```

---

### Task 22: Tab 1 赛车 — MotorsportCard 加 seriesAccent 顶条

**Files:**
- Modify: `Pole/Features/Common/MotorsportCard.swift`

- [ ] **Step 1: 在 MotorsportCard struct 内,把内容包装 + 顶部加 SeriesTopAccent**

```swift
// 原 body 主结构外面包 VStack(spacing: 0):
public var body: some View {
    VStack(spacing: 0) {
        SeriesTopAccent(series: series)
        // ... 原 body 内容
    }
    // ... 原 background / shadow 等保留
}
```

注意:`series` 已是 init 参数,直接用即可。

- [ ] **Step 2: Build + 视觉验证 4 系列 RoundListView 卡片**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。F1/MotoGP/WSBK/FE 各 list view 中 MotorsportCard 顶部有红/橙/绿/青色条。

- [ ] **Step 3: Commit**

```bash
git add Pole/Features/Common/MotorsportCard.swift
git commit -m "feat(motorsport): MotorsportCard adds SeriesTopAccent top bar"
```

---

### Task 23: Tab 1 赛车 — Timeline 月份 header 大字 + 红竖条

**Files:**
- Modify: `Pole/Features/Motorsport/MotorsportTimelineView.swift`

- [ ] **Step 1: 找 Timeline 月份 section header**

```bash
grep -n "MAY\|月份\|month\|Month" /Users/bytedance/project/Pole/Pole/Features/Motorsport/MotorsportTimelineView.swift
```

- [ ] **Step 2: 替换 header View**

把月份 Text 包装为:
```swift
HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
    Rectangle()
        .fill(DS.Palette.racingRed)
        .frame(width: 3, height: 22)
    Text(monthString.uppercased())
        .font(DS.Font.heroTitle)
        .foregroundStyle(.primary)
        .tracking(1.2)
    Spacer()
}
.padding(.vertical, DS.Spacing.sm)
```

- [ ] **Step 3: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Timeline 月份 header 全大写 heavy 字 + 左侧红竖条。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/Motorsport/MotorsportTimelineView.swift
git commit -m "feat(timeline): month header gets racing-red bar and Bold tracking title"
```

---

### Task 24: Tab 1 赛车 — Empty state 加 StartLightGrid

**Files:**
- Modify: `Pole/Features/Motorsport/MotorsportTimelineView.swift`(empty state branch)

- [ ] **Step 1: 找 empty state 渲染分支**

```bash
grep -n "Empty\|empty\|本月无赛事\|no rounds" /Users/bytedance/project/Pole/Pole/Features/Motorsport/MotorsportTimelineView.swift
```

- [ ] **Step 2: 替换 empty view**

```swift
VStack(spacing: DS.Spacing.lg) {
    StartLightGrid(mode: .idle, size: 16)
    Text(L10n.t(zh: "本月无赛事", en: "No rounds this month"))
        .font(DS.Font.heroSubtitle)
        .foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity, minHeight: 180)
.padding()
.background(
    CheckerStripe(.fill, opacity: 0.04)
)
```

- [ ] **Step 3: Build + 视觉 — Hub 上选个无赛事月份**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。空状态显示 5 灯灭 + 文字 + 极淡棋盘格背景。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/Motorsport/MotorsportTimelineView.swift
git commit -m "feat(timeline): empty state shows idle StartLightGrid on CheckerStripe bg"
```

---

### Task 25: Tab 4 关注 — 列表 row seriesAccent + Empty state CTA

**Files:**
- Modify: `Pole/Features/Follow/FollowFeedView.swift`

- [ ] **Step 1: 读现状定位 row 和 empty state**

```bash
sed -n '1,80p' /Users/bytedance/project/Pole/Pole/Features/Follow/FollowFeedView.swift
```

- [ ] **Step 2: 关注 row 用 dsListCard 传 seriesAccent**

找当前 row View(可能是 `HStack { ... }` 或类似),在它外面应用 `.dsListCard(seriesAccent: target.series)`,移除老的手动 background。

- [ ] **Step 3: 加 Notification.Name 扩展(跨 tab 切换通知)**

参考项目现有 `.resetChatToStarter` / `.openRaceDetail` 模式,在 `Pole/Sports/Intents/AppIntents.swift` 或者新建 `Pole/Domain/Notifications.swift` 加:

```swift
public extension Notification.Name {
    static let navigateToMotorsportTab = Notification.Name("navigateToMotorsportTab")
}
```

(若已有 Notifications.swift / similar 集中放 Notification.Name 文件,加在那里;否则就放 `AppIntents.swift` 与其他 Name 并列。)

- [ ] **Step 4: ContentView 监听切 tab**

`Pole/ContentView.swift` 中找 TabView,加 `.onReceive` 监听:

```swift
TabView(selection: $selectedTab) { /* ... */ }
.onReceive(NotificationCenter.default.publisher(for: .navigateToMotorsportTab)) { _ in
    selectedTab = .motorsport
}
```

(`selectedTab` 与 `.motorsport` 的实际名字按 ContentView 既有 `AppTab` enum 命名调整。)

- [ ] **Step 5: Empty state 实现**

```swift
VStack(spacing: DS.Spacing.lg) {
    StartLightGrid(mode: .idle, size: 14)
    Text(L10n.t(zh: "尚未关注任何车手 / 车队", en: "No followed athletes or teams"))
        .font(DS.Font.heroSubtitle)
        .foregroundStyle(.secondary)
    Button(L10n.t(zh: "去赛车 tab 发现", en: "Discover in Race tab")) {
        NotificationCenter.default.post(name: .navigateToMotorsportTab, object: nil)
    }
    .buttonStyle(.dsRacingButton)
}
```

- [ ] **Step 6: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Follow tab 列表行有系列色条,空状态有起跑灯 + 红 CTA,点 CTA 切到赛车 tab。

- [ ] **Step 7: Commit**

```bash
git add Pole/Features/Follow/FollowFeedView.swift Pole/ContentView.swift Pole/Sports/Intents/AppIntents.swift
git commit -m "feat(follow): seriesAccent row + StartLightGrid empty state with racing CTA, cross-tab routing"
```

---

### Task 26: Tab 2 积分榜 — 排行 row 数字 mono + Top 3 强调

**Files:**
- Modify: `Pole/Features/Standings/StandingsView.swift`(L100-700 各 Row struct)

- [ ] **Step 1: 找排行 row struct(F1DriverStandingRow / MotoGPRiderRow / ...)** ,定位名次 / 积分字段

```bash
grep -n "struct.*Row\|standing.position\|standing.points" /Users/bytedance/project/Pole/Pole/Features/Standings/StandingsView.swift | head -30
```

- [ ] **Step 2: 给每个 Row 的名次和积分字段加 numberMid 和 monospacedDigit**

例如 F1DriverStandingRow body:
```swift
HStack(spacing: DS.Spacing.md) {
    Text("P\(standing.position)")
        .font(DS.Font.numberMid.weight(.heavy))
        .foregroundStyle(positionColor(standing.position))
        .frame(width: 38, alignment: .leading)
    VStack(alignment: .leading, spacing: 2) {
        Text(driverName)
            .font(DS.Font.heroTitle)
    }
    Spacer()
    Text("\(standing.points)")
        .font(DS.Font.numberLarge)
        .monospacedDigit()
}
```

`positionColor`:
```swift
private func positionColor(_ p: Int) -> Color {
    p == 1 ? DS.Palette.racingRed : .primary
}
```

- [ ] **Step 3: Top 3 行强调:P1 整行 racingRedFaint 底 + leading 红条**

把 dsListCard 内容加一 leading bar:
```swift
HStack(spacing: 0) {
    if standing.position == 1 {
        Rectangle().fill(DS.Palette.racingRed).frame(width: 3)
    } else if standing.position <= 3 {
        Rectangle().fill(DS.Palette.tarmacHairline).frame(width: 3)
    }
    // ... row 内容 ...
}
.background(standing.position == 1 ? DS.Palette.racingRedFaint : Color.clear)
```

- [ ] **Step 4: 4 系列 9 个 Row struct 都同样改造**(MotoGPRiderRow / MotoGPTeamRow / MotoGPConstructorRow / WSSPRiderRow / WSSPBuilderRow / FEDriverRow / FETeamRow / F1DriverStandingRow / F1ConstructorStandingRow)

参照 Step 2-3 模板逐个改。

- [ ] **Step 5: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。9 个 Row 全部数字 mono 对齐 + P1 红条 + racingRedFaint 底色。

- [ ] **Step 6: Commit**

```bash
git add Pole/Features/Standings/StandingsView.swift
git commit -m "feat(standings): rows use numberMid mono + P1 emphasis + 4-series unified"
```

---

### Task 27: Tab 2 积分榜 — section header 全大写 Heavy + 棋盘格装饰

**Files:**
- Modify: `Pole/Features/Standings/StandingsView.swift`(SegmentedPillPicker 周边)

- [ ] **Step 1: 找 "DRIVERS / TEAMS" / "RIDERS / CONSTRUCTORS" section header 位置**

```bash
grep -n "drivers\|riders\|constructors\|teams" /Users/bytedance/project/Pole/Pole/Features/Standings/StandingsView.swift | head -20
```

- [ ] **Step 2: 把 section header 替换为带棋盘格装饰版本**

每个 Standings 子 view(F1StandingsContent / MotoGPStandings / WSBKStandings / FEStandings)的 picker 后加:
```swift
HStack {
    Text(tab.displayLabel.uppercased())
        .font(DS.Font.toolLabel)
        .tracking(1.0)
        .foregroundStyle(.secondary)
    CheckerStripe(.horizontal, cellSize: 4, opacity: 0.5)
        .frame(width: 24, height: 6)
    Spacer()
}
.padding(.horizontal)
.padding(.top, DS.Spacing.sm)
```

- [ ] **Step 3: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。每个 series 的 standings 在 picker 下方有 "DRIVERS" 全大写 Heavy + 棋盘格小装饰条。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/Standings/StandingsView.swift
git commit -m "feat(standings): uppercase section labels + CheckerStripe decoration"
```

---

### Task 28: Tab 3 AI — ChatViewModel 加 greetingMode + Greeting hero racing/friendly 切换

**Files:**
- Modify: `Pole/Features/Chat/ChatViewModel.swift`
- Modify: `Pole/Features/Chat/ChatView.swift`(Greeting hero 渲染)

- [ ] **Step 1: 在 ChatViewModel 加 greetingMode 状态**

```swift
@AppStorage("greetingMode") private var greetingModeRaw: String = "racing"

var greetingHeaderTitle: String {
    L10n.t(zh: "早上好,Pole", en: "Hey, Pole")
}

var greetingHeaderSubtitle: String {
    switch greetingModeRaw {
    case "racing":
        let dateStr = Date().formatted(.dateTime.year().month().day())
        return "READY · DRS ENABLED · \(dateStr)"
    default:
        return L10n.t(zh: "今天想聊点什么", en: "What's on your mind today")
    }
}
```

- [ ] **Step 2: 改 ChatView Greeting hero 渲染**

找 Greeting hero 位置(包含 "早上好"的 View),改为:
```swift
VStack(spacing: DS.Spacing.lg) {
    AIAvatar(size: .large)
    Text(viewModel.greetingHeaderTitle)
        .font(DS.Font.heroDisplay)
        .foregroundStyle(.white)
    Text(viewModel.greetingHeaderSubtitle)
        .font(DS.Font.numberSmall)
        .foregroundStyle(.white.opacity(0.7))
}
.frame(maxWidth: .infinity)
.padding(.vertical, DS.Spacing.xl)
```

- [ ] **Step 3: Build + 视觉两种模式切换**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。AI tab Greeting 默认显示 "READY · DRS ENABLED · 2026年5月11日";Settings → Greeting 风格 = 友好后,显示"今天想聊点什么"。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/Chat/ChatViewModel.swift Pole/Features/Chat/ChatView.swift
git commit -m "feat(chat): racing telemetry greeting hero (toggle to friendly)"
```

---

### Task 29: Tab 3 AI — TriviaCard 用 dsHeroBanner + lightbulb → pit note icon

**Files:**
- Modify: `Pole/Features/Chat/TriviaCard.swift`

- [ ] **Step 1: 读 TriviaCard 现状**

```bash
sed -n '1,80p' /Users/bytedance/project/Pole/Pole/Features/Chat/TriviaCard.swift
```

- [ ] **Step 2: 包装外层 + 替换 icon**

把整个 TriviaCard body 外层应用 `.dsHeroBanner()`,把 `Image(systemName: "lightbulb.fill")` 改为 `Image(systemName: "flag.checkered.2.crossed")`,标题文字改 `"📋 PIT NOTE · 冷知识"`(双语对应 `"📋 PIT NOTE · Trivia"`)。

- [ ] **Step 3: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。AI tab 首页 TriviaCard 显示沥青底 + 速度线 + 顶部红条 + PIT NOTE 标题 + 赛旗 icon。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/Chat/TriviaCard.swift
git commit -m "feat(chat): TriviaCard becomes Pit Note hero with checkered flag icon"
```

---

### Task 30: Tab 3 AI — Send 按钮用 dsRacingButton + 流式光标已自动跟随(无需改)

**Files:**
- Modify: `Pole/Features/Chat/ChatView.swift`(L600 附近 send 按钮)

- [ ] **Step 1: 找 send 按钮渲染**

```bash
grep -n "send\|Send\|发送" /Users/bytedance/project/Pole/Pole/Features/Chat/ChatView.swift | head -15
```

- [ ] **Step 2: 把 send 按钮的 buttonStyle 切到 dsRacingButton**

例如(找现有 send Button 渲染):
```swift
Button {
    viewModel.send()
} label: {
    Image(systemName: "arrow.up")
}
.buttonStyle(.dsRacingButton)
.disabled(!canSend)
```

注意:原 send 按钮可能用 `.buttonStyle(.plain)` 或 custom style。改为 `.dsRacingButton` 同时移除自定义 background。

- [ ] **Step 3: 流式光标 ▍ 已经走 `DS.Palette.primary`(现 alias 到 racingRed),无需改**

但为语义清晰,显式改 `StreamingCursor` 内 `foregroundStyle(DS.Palette.primary)` 为 `racingRed`。在 `Pole/Theme/DesignSystem.swift:432`(StreamingCursor struct body 内):
```swift
.foregroundStyle(DS.Palette.racingRed)
```

- [ ] **Step 4: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。AI tab send 按钮红渐变 + glow + 按下震动 + 流式光标红色。

- [ ] **Step 5: Commit**

```bash
git add Pole/Features/Chat/ChatView.swift Pole/Theme/DesignSystem.swift
git commit -m "feat(chat): send button uses dsRacingButton; StreamingCursor explicit racingRed"
```

**Phase 3 出口验收**:5 个 tab 主页视觉转赛车;每 tab commit 独立可 revert;layout 测试 iPhone 16 Pro / iPhone SE3 / Dynamic Type AX1 都正常。

---

## Phase 4 — 详情页迁移(13 改造点,批量 4 task)

### Task 31: 4 系列 RoundDetailView — Hero + StartLightGrid + speedLines + session 行

**Files:**
- Modify: `Pole/Features/F1/RaceDetailView.swift`
- Modify: `Pole/Features/MotoGP/MotoGPRoundDetailView.swift`
- Modify: `Pole/Features/WSBK/WSBKRoundDetailView.swift`
- Modify: `Pole/Features/FE/FERoundDetailView.swift`
- Modify: `Pole/Features/Common/GlassHeroHeader.swift`

- [ ] **Step 1: GlassHeroHeader 加 speedLines 可选 + SeriesTopAccent 可选**

```swift
public struct GlassHeroHeader: View {
    let series: MotorsportSeries
    let title: String
    // ... 已有参数
    var enableSpeedLines: Bool = false   // 默认 off

    public var body: some View {
        VStack(spacing: 0) {
            SeriesTopAccent(series: series)
            // ... 原 hero 内容
        }
        .modifier(SpeedLinesOverlay(color: DS.Palette.decorOnSurface,
                                    animated: false))
        // 已有 background / glass effect 等
    }
}
```

注意:`speedLines` 默认 on(因为是 hero,Phase 4 全开启),具体实现根据现有 GlassHeroHeader 结构调整。

- [ ] **Step 2: StartLightGrid 倒计时 helper**

在 `Pole/Theme/RacingComponents.swift` 加 helper:
```swift
public extension StartLightGrid {
    /// 根据距离开赛分钟数返回合适 mode。
    static func mode(forMinutesUntilStart minutes: Int) -> Mode {
        if minutes > 10 { return .idle }
        if minutes > 5  { return .countdown(litCount: 1) }
        if minutes > 1  { return .countdown(litCount: 3) }
        if minutes > 0  { return .countdown(litCount: 5) }
        return .lightsOut
    }
}
```

- [ ] **Step 3: 4 系列 RoundDetailView 加 StartLightGrid 倒计时区**

对每个 RoundDetailView,在 hero 区下方(如果 status == .upcoming 且距开赛 < 10min):
```swift
if round.currentStatus == .upcoming,
   let raceStart = round.mainRace?.startTime,
   case let minutes = max(0, Int(raceStart.timeIntervalSinceNow / 60)),
   minutes <= 10 {
    HStack {
        Spacer()
        StartLightGrid(mode: .mode(forMinutesUntilStart: minutes), size: 16)
        Spacer()
    }
    .padding(.vertical, DS.Spacing.lg)
    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
        // SwiftUI 自动重渲染(view body 是 computed property,依赖 Date()/timeIntervalSinceNow)
    }
}
```

- [ ] **Step 4: session 行 dsToolCard + 时间 numberSmall mono + session 名 Heavy**

找各 RoundDetailView 的 session list row(显示 FP1/Q/Sprint/Race 的位置),包装:
```swift
HStack {
    Text(session.name.uppercased())
        .font(DS.Font.heroSubtitle.weight(.heavy))
        .tracking(0.5)
    Spacer()
    Text(session.startTime, format: .dateTime.hour().minute())
        .font(DS.Font.numberSmall)
        .foregroundStyle(.secondary)
}
.dsToolCard()
.padding(.horizontal)
```

- [ ] **Step 5: RaceRecapSection 外层 dsHeroBanner**

找 `RaceRecapSection` 调用,在外层加:
```swift
RaceRecapSection(...)
    .dsHeroBanner(seriesAccent: round.series)
```

- [ ] **Step 6: 4 系列 Build + 视觉 — 各进一场比赛详情**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。每个 RoundDetailView hero 有速度线 + 顶部色条;session 行赛车感;RaceRecap 沥青 banner。

- [ ] **Step 7: Commit**

```bash
git add Pole/Features/F1/RaceDetailView.swift Pole/Features/MotoGP/MotoGPRoundDetailView.swift Pole/Features/WSBK/WSBKRoundDetailView.swift Pole/Features/FE/FERoundDetailView.swift Pole/Features/Common/GlassHeroHeader.swift Pole/Theme/RacingComponents.swift
git commit -m "feat(detail): RoundDetail hero gets speedLines + SeriesTopAccent + countdown lights, sessions go dsToolCard with mono time"
```

---

### Task 32: 4 系列 DriverDetailView — 编号大字 + 历史 row mono

**Files:**
- Modify: `Pole/Features/F1/F1DriverDetailView.swift`
- Modify: `Pole/Features/MotoGP/MotoGPRiderDetailView.swift`
- Modify: `Pole/Features/WSBK/WSSPRiderDetailView.swift`
- Modify: `Pole/Features/FE/FEDriverDetailView.swift`

- [ ] **Step 1: 在 hero 头像下方加车手编号大字**

每个 DriverDetailView hero 区:
```swift
VStack(spacing: DS.Spacing.xs) {
    AsyncImage(...)  // 已有头像
    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
        Text("#\(driver.number)")
            .font(DS.Font.numberLarge)
            .foregroundStyle(series.brandColor)
        Text(driver.flag + " " + (driver.birthPlace ?? ""))
            .font(DS.Font.numberSmall)
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: 历史成绩 row 字段用 numberMid mono**

找历史成绩 List/Section:
```swift
HStack {
    Text("R\(record.round)").font(DS.Font.numberSmall).foregroundStyle(.secondary)
    Text(record.race).font(DS.Font.bubble)
    Spacer()
    Text("P\(record.position)").font(DS.Font.numberMid.weight(.semibold))
    Text("+\(record.points)").font(DS.Font.numberMid).foregroundStyle(.secondary)
}
```

- [ ] **Step 3: Build + 视觉 4 系列 driver detail**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。各车手详情有大字编号 + 历史 row 数字 mono 对齐。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/F1/F1DriverDetailView.swift Pole/Features/MotoGP/MotoGPRiderDetailView.swift Pole/Features/WSBK/WSSPRiderDetailView.swift Pole/Features/FE/FEDriverDetailView.swift
git commit -m "feat(detail): driver detail hero shows large number + mono history rows"
```

---

### Task 33: 4 系列 SessionResultsView — P1 racingRedFaint + 圈速 mono

**Files:**
- 文件取决于实际 SessionResults 组件位置,可能在各系列 RoundDetailView 内或独立文件。
- Modify: 各系列 SessionResults 渲染处

- [ ] **Step 1: 找 SessionResults row 实现**

```bash
grep -rn "SessionResultsView\|session.results\|SessionResultRow" /Users/bytedance/project/Pole/Pole/Features/ | head -15
```

- [ ] **Step 2: row 改造**

```swift
HStack(spacing: DS.Spacing.md) {
    Text("P\(result.position)")
        .font(DS.Font.numberMid.weight(.heavy))
        .foregroundStyle(result.position == 1 ? DS.Palette.racingRed : .primary)
        .frame(width: 36, alignment: .leading)
    Text(result.driver.name).font(DS.Font.heroSubtitle)
    Spacer()
    Text(result.time).font(DS.Font.numberMid)
        .foregroundStyle(.secondary)
}
.padding(.horizontal, DS.Spacing.md)
.padding(.vertical, DS.Spacing.sm)
.background(result.position == 1 ? DS.Palette.racingRedFaint : Color.clear)
```

- [ ] **Step 3: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。Race 比赛结果 P1 行红底,圈速 mono 三位小数对齐。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/F1/RaceDetailView.swift Pole/Features/MotoGP/MotoGPRoundDetailView.swift Pole/Features/WSBK/WSBKRoundDetailView.swift Pole/Features/FE/FERoundDetailView.swift
git commit -m "feat(detail): SessionResults P1 racingRedFaint highlight + mono lap times"
```

---

### Task 34: TeamDetailView — dsHeroBanner + 动态 SeriesTopAccent + 4 系列 team 验证

**Files:**
- Modify: `Pole/Features/News/TeamDetailView.swift`

- [ ] **Step 1: 找 TeamDetailView hero 区**

```bash
sed -n '1,60p' /Users/bytedance/project/Pole/Pole/Features/News/TeamDetailView.swift
```

- [ ] **Step 2: hero 区改造**

```swift
VStack(spacing: DS.Spacing.lg) {
    AsyncImage(url: team.logoURL) { image in
        image.resizable().scaledToFit()
    } placeholder: {
        Image(systemName: "person.3.fill")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: 80, maxHeight: 80)
    Text(team.name)
        .font(DS.Font.heroTitle)
}
.frame(maxWidth: .infinity)
.dsHeroBanner(seriesAccent: team.series)   // 动态系列色顶条
```

- [ ] **Step 3: Build + 视觉 — 进 F1 / MotoGP / WSBK / FE 各 1 个 team detail**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED。各系列 team detail hero 显示对应品牌色条 + 沥青底 + speedLines。

- [ ] **Step 4: Commit**

```bash
git add Pole/Features/News/TeamDetailView.swift
git commit -m "feat(detail): TeamDetailView hero gets dsHeroBanner with dynamic SeriesTopAccent"
```

**Phase 4 出口验收**:13 改造点全部覆盖;StartLightGrid 倒计时 60s Timer 通过 Instruments / 模拟器 Battery 测量功耗在可接受范围;每个详情页 commit 独立。

---

## Phase 5 — 动效 / 触觉打磨(可选,~0.5 工作日)

### Task 35: Tab 切换 haptic + raceEntry motion

**Files:**
- Modify: `Pole/ContentView.swift`(TabView selection change hook)
- Modify: `Pole/Features/F1/RaceDetailView.swift`(及其他 RoundDetail)

- [ ] **Step 1: ContentView tab 切换 lightImpact**

```swift
TabView(selection: $selectedTab) {
    // ...
}
.onChange(of: selectedTab) { _, _ in
    HapticFeedback.lightImpact()
}
```

- [ ] **Step 2: RoundDetail hero 入场 raceEntry**

GlassHeroHeader 内主 layer:
```swift
.transition(.opacity.combined(with: .scale(scale: 0.96)))
.animation(DS.Motion.raceEntry, value: round.id)
```

- [ ] **Step 3: Build + 视觉**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add Pole/ContentView.swift Pole/Features/Common/GlassHeroHeader.swift
git commit -m "feat(motion): tab switch haptic + raceEntry hero scale-in"
```

---

### Task 36: live 卡片 speedLines animated + reducedDecor toggle 接入

**Files:**
- Modify: `Pole/Features/Common/MotorsportCard.swift`
- Modify: `Pole/Theme/RacingComponents.swift`(SpeedLinesOverlay 接 reducedDecor)

- [ ] **Step 1: SpeedLinesOverlay 读 @AppStorage("reducedDecor")**

```swift
public struct SpeedLinesOverlay: ViewModifier {
    var color: Color
    var animated: Bool
    @AppStorage("reducedDecor") private var reducedDecor: Bool = false
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        if reducedDecor {
            return AnyView(content)  // 完全跳过装饰
        }
        return AnyView(
            content.overlay { /* 已有 Canvas */ }
        )
    }
}
```

注意:CheckerStripe / StartLightGrid 也接 `reducedDecor` 用类似条件 — 但 `StartLightGrid` 是状态指示,不算装饰,**不接**。`CheckerStripe(.fill)` 满铺装饰接 reducedDecor。

- [ ] **Step 2: MotorsportCard 在 isLive 时启用 animated speedLines**

```swift
.modifier(SpeedLinesOverlay(color: DS.Palette.live.opacity(0.15),
                            animated: isLive))
```

- [ ] **Step 3: Build + 视觉 — 找一场 live(或 mock) + 切 reducedDecor 验证**

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add Pole/Theme/RacingComponents.swift Pole/Features/Common/MotorsportCard.swift
git commit -m "feat(motion): live cards animate speedLines; reducedDecor toggle honored"
```

**Phase 5 出口验收**:切 Tab 有触觉;Live 卡片速度线动;Settings → 减少装饰 关闭后所有 SpeedLines / CheckerStripe.fill 装饰全消失;Reduce Motion 系统开关同样停所有动效。

---

## 全计划出口验收(对应 spec §8)

逐项 review spec §8 中 5 Phase × 各出口 checklist。如下:

- [ ] **Phase 1**: 默认 Dark / Settings 三态切换 OK / 主 CTA 全红 / 旧 layout 0 改动 / `DS.Palette.primary` alias 兼容
- [ ] **Phase 2**: 4 组件 + 3 modifier #Preview 通过 / StatusBadge.live 棋盘格脉冲 / 旧 layout 0 改动
- [ ] **Phase 3**: 5 tab 视觉转赛车 / 每 tab 独立 commit / Greeting 风格 toggle / 装饰开关有效
- [ ] **Phase 4**: 13 改造点全部覆盖(参 spec 附录 B 13 行 table)/ StartLightGrid 倒计时 60s 不耗电
- [ ] **Phase 5**: Tab 触觉 / live speedLines 动效 / reducedDecor toggle 起作用 / Reduce Motion 系统设置兼容

---

## 自审 checklist(plan 完成后即跑,无需用户参与)

- [ ] **Spec coverage**: spec §3-7 每一条都映射到 1+ task(Section 3 → Task 4-9 / Section 4 → Task 10-19 / Section 5 → Task 20-30 / Section 6 → Task 1-3 / Section 7 Phase 划分 = plan 的 Phase 划分)
- [ ] **Placeholder scan**: 无 "TBD" / "TODO" / "实现 above"
- [ ] **Type consistency**: `AppearanceMode` / `racingRed` / `tarmacBg` / `dsHeroBanner` / `dsRacingButton` / `dsLiveBadge` / `SeriesTopAccent` / `CheckerStripe` / `StartLightGrid` / `SpeedLinesOverlay` 跨任务命名一致
- [ ] **Step concreteness**: 每个 code-changing step 有完整 code block,无"类似 Task N"省略

---

End of plan. **下一步**:选择执行方式 — Subagent-Driven(推荐,fresh subagent per task)或 Inline Execution(本会话内 batched)。
