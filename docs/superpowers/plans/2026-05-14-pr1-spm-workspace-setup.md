# PR1 (Phase 0) — SPM Workspace + PoleSharedKit + PoleDesignSystem + AppRouter + AppEnv Skeleton

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-05-14-architecture-refactor-design.md`

**Goal:** 把 Pole 从单 `.xcodeproj` 迁成 SPM workspace 结构,拆出 2 个 Swift Package (`PoleSharedKit` + `PoleDesignSystem`),引入 `AppRouter` + `AppEnv` 骨架,把 `AppearanceStore` 迁成 `@Observable`。

**Architecture:** 顶层 `PoleApp.xcworkspace` 包 `Pole.xcodeproj` + `Packages/` 子目录。`Pole/Shared/` 4 个文件 + `Pole/Theme/` 3 个文件分别移入两个 package,代码 `public` 化。`AppRouter` 集中管 5 个 Tab 的导航 path,深链走 `router.deeplink(to:)`。`AppEnv` 是 `@Observable` 的全局环境对象,本 PR 只装 `appearance` + `router`,后续 PR 增量加 service。

**Tech Stack:** Swift 5.0 + SwiftUI + SwiftData + iOS 26.2 + Xcode 26+ + Swift Package Manager

**Known constraints:**
- `PoleWidgets` target **未在 pbxproj 中**(只是 source 文件夹存在)。本 PR 完成判定**不包括** widget build,只验主 app + tests。Widget 跨包引用留到真正 wire extension target 时再做。
- 当前 Pole.xcodeproj 内有 inner `.xcworkspace`(Xcode 自动建的),本 PR 在 repo 顶层新建独立的 `PoleApp.xcworkspace`,**用户以后必须打开顶层的**,不能再点 .xcodeproj。
- 单元测试当前是 placeholder (`PoleTests.swift`),不强求测试覆盖。

**Risk level:** 高(跨 target / project 结构改动,失败要全 revert)

---

## File Structure

### Files Created

```
PoleApp.xcworkspace/                                  # 新建,顶层 workspace
  contents.xcworkspacedata                           # 引 Pole.xcodeproj + Packages/

Packages/
  PoleSharedKit/
    Package.swift                                     # SPM manifest
    Sources/PoleSharedKit/
      AppGroup.swift                                  # 从 Pole/Shared/ 移过来
      SeriesBrand.swift                               # 同上
      WidgetSnapshot.swift                            # 同上
      WidgetSnapshotStore.swift                       # 同上
      Router/AppRouter.swift                          # 新建
      Env/AppEnv.swift                                # 新建(skeleton)

  PoleDesignSystem/
    Package.swift                                     # SPM manifest
    Sources/PoleDesignSystem/
      DesignSystem.swift                              # 从 Pole/Theme/ 移
      SeriesTheme.swift                               # 同上
      RacingComponents.swift                          # 同上
```

### Files Deleted (移动后留空)

```
Pole/Shared/AppGroup.swift                            # 已搬走
Pole/Shared/SeriesBrand.swift                         # 已搬走
Pole/Shared/WidgetSnapshot.swift                      # 已搬走
Pole/Shared/WidgetSnapshotStore.swift                 # 已搬走
Pole/Theme/DesignSystem.swift                         # 已搬走
Pole/Theme/SeriesTheme.swift                          # 已搬走
Pole/Theme/RacingComponents.swift                     # 已搬走
```

### Files Modified

```
Pole.xcodeproj/project.pbxproj                       # 加 SPM 依赖 + 删除被搬走文件的引用
Pole/PoleApp.swift                                    # import PoleSharedKit/PoleDesignSystem;
                                                      # 用 AppEnv;@StateObject → @Environment
Pole/Domain/AppearanceMode.swift                      # ObservableObject → @Observable
Pole/ContentView.swift                                # 用 router.selectedTab + router 的 NavigationStack paths
Pole/Features/Settings/AppearanceModePicker.swift     # 如有 → 适配新 AppearanceStore
其他凡 import 过 DS 或 Pole/Shared 内容的文件                # ~30 处加 import 语句
```

---

## Pre-flight: 备份和约定

- [ ] **Step 0.1: 起一个 backup tag(出大事时可回滚)**

```bash
git tag pre-pr1-backup
git push origin pre-pr1-backup
```

Expected: tag pushed successfully

- [ ] **Step 0.2: 验证当前 main 是干净的**

```bash
git status
```

Expected: `working tree clean`

如果不干净就 `git stash` 或 commit。**不要带 dirty state 开始这个 PR**。

- [ ] **Step 0.3: 起 PR 分支**

```bash
git checkout -b pr1/spm-workspace-setup
```

Expected: switched to new branch

---

## Part A: 创建 SPM Workspace 结构骨架

### Task 1: 新建顶层 PoleApp.xcworkspace

**Files:**
- Create: `PoleApp.xcworkspace/contents.xcworkspacedata`

- [ ] **Step A1.1: 创建 workspace 目录和 contents 文件**

```bash
mkdir -p PoleApp.xcworkspace
```

写入 `PoleApp.xcworkspace/contents.xcworkspacedata`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
  <FileRef location = "group:Pole.xcodeproj"></FileRef>
  <Group location = "container:Packages" name = "Packages">
  </Group>
</Workspace>
```

(Group 节点为空是 OK 的,Xcode 会在添加 packages 后自动填充。)

- [ ] **Step A1.2: 用 Xcode 打开 PoleApp.xcworkspace 一次,验证识别**

```bash
open PoleApp.xcworkspace
```

Expected: Xcode 在左侧 Navigator 看到 `Pole`(project)和 `Packages`(group)。如果看不到 Packages group 也 OK(还没 package 加入)。

**关闭 Xcode**(不需要保存任何东西)。

### Task 2: 创建 Packages 目录

- [ ] **Step A2.1: 建 Packages 文件夹**

```bash
mkdir -p Packages
```

---

## Part B: 创建 PoleSharedKit Package

### Task 3: 新建 PoleSharedKit Package.swift

**Files:**
- Create: `Packages/PoleSharedKit/Package.swift`
- Create: `Packages/PoleSharedKit/Sources/PoleSharedKit/.gitkeep` (临时占位)

- [ ] **Step B3.1: 建目录结构**

```bash
mkdir -p Packages/PoleSharedKit/Sources/PoleSharedKit
mkdir -p Packages/PoleSharedKit/Tests/PoleSharedKitTests
touch Packages/PoleSharedKit/Sources/PoleSharedKit/.gitkeep
```

- [ ] **Step B3.2: 写 Package.swift**

写入 `Packages/PoleSharedKit/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleSharedKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PoleSharedKit", targets: ["PoleSharedKit"]),
    ],
    targets: [
        .target(name: "PoleSharedKit"),
        .testTarget(name: "PoleSharedKitTests", dependencies: ["PoleSharedKit"]),
    ]
)
```

**Note:** 用 `iOS(.v17)` 而不是 `.v26`,因为 SPM 还没认 26;真实部署目标由主 app target 决定,package 跟随。

- [ ] **Step B3.3: 写一个 placeholder Swift 文件(让 package build 通过)**

写入 `Packages/PoleSharedKit/Sources/PoleSharedKit/Placeholder.swift`:

```swift
// 临时占位,Task 5 起会替换成真实文件
// (Swift Package 不能没有任何 .swift 文件)
internal enum _PoleSharedKitPlaceholder {}
```

删除 `.gitkeep`:

```bash
rm Packages/PoleSharedKit/Sources/PoleSharedKit/.gitkeep
```

- [ ] **Step B3.4: 验 package 单独可 build**

```bash
cd Packages/PoleSharedKit && swift build && cd ../..
```

Expected: `Build complete!`,无 error/warning

### Task 4: 把 PoleSharedKit 加进 Xcode workspace + main app target dependency

- [ ] **Step B4.1: 打开 PoleApp.xcworkspace,加 package**

```bash
open PoleApp.xcworkspace
```

在 Xcode 中:
1. File → Add Package Dependencies → Add Local…
2. 选 `Packages/PoleSharedKit`
3. Add to Project: `Pole` (主 app target)
4. Click Add Package

**确认:** Xcode 左侧 Navigator → `Packages` group 下应该出现 `PoleSharedKit`

- [ ] **Step B4.2: 在主 app target 的 Frameworks/Libraries 加 PoleSharedKit**

Xcode → Pole target → General → Frameworks, Libraries, and Embedded Content → "+" → 选 `PoleSharedKit` library

(SPM 包通常自动加,但**显式确认一遍**保险)

- [ ] **Step B4.3: cmd-B 验证 workspace 整体 build 通过**

Xcode 中 `Cmd-B`,Expected: Build Succeeded

如失败:回到 step B3.4 看 package 是否单独 build 过。如果 package 自己 build 过、workspace build 不过,通常是 Xcode 没拉 package — File → Packages → Reset Package Caches。

- [ ] **Step B4.4: commit checkpoint 1**

```bash
git add PoleApp.xcworkspace Packages/PoleSharedKit Pole.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(workspace): add PoleApp.xcworkspace + empty PoleSharedKit package

Phase 0 PR1 (Part A+B): scaffold SPM workspace structure with empty
PoleSharedKit package as a placeholder. Verifies SPM tooling resolves
and Xcode picks up the package dependency.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Part C: 把 Pole/Shared 内容搬进 PoleSharedKit

### Task 5: 把 AppGroup.swift 搬过去 + public 化

**Files:**
- Modify (move): `Pole/Shared/AppGroup.swift` → `Packages/PoleSharedKit/Sources/PoleSharedKit/AppGroup.swift`

- [ ] **Step C5.1: 物理移动文件**

```bash
git mv Pole/Shared/AppGroup.swift Packages/PoleSharedKit/Sources/PoleSharedKit/AppGroup.swift
```

(`git mv` 保留 history,比 `mv` 好)

- [ ] **Step C5.2: 验证文件已经是 public**

```bash
grep "public" Packages/PoleSharedKit/Sources/PoleSharedKit/AppGroup.swift
```

Expected: 看到 `public enum AppGroup`, `public static let identifier`, `public static var containerURL`, `public static var snapshotURL`

(从原文件复制,文件内容已经全是 public,不用改)

- [ ] **Step C5.3: 从 Xcode project 删 old reference**

打开 `PoleApp.xcworkspace`,在左侧 Pole project 的 `Shared` group 里找到 `AppGroup.swift`,**右键 → Delete → Remove Reference**(不要 Move to Trash,文件已经在 Packages 下了)

如果 Xcode pbxproj 没自动清,验证:

```bash
grep "AppGroup.swift" Pole.xcodeproj/project.pbxproj
```

Expected: 只在 `// AppGroup.swift in Sources` 上下文(实际可能没匹配),不应有 `path = Shared/AppGroup.swift` 的 file reference

- [ ] **Step C5.4: 找所有用了 AppGroup 的地方加 import**

```bash
grep -rln "AppGroup\." Pole --include="*.swift"
```

Expected: ~3-5 个文件(`WidgetSnapshotStore.swift` 等会引用,但这些也即将迁走)

对每个 caller 文件(不在 Pole/Shared/ 下、不会很快也搬走的),在 import 区加:

```swift
import PoleSharedKit
```

**实际操作**:跑下面命令找出**主 app 内**仍引用 AppGroup 的文件:

```bash
grep -rln "AppGroup\." Pole --include="*.swift" | grep -v "Pole/Shared/"
```

对每个文件用 Edit 工具加 `import PoleSharedKit`。

- [ ] **Step C5.5: build 验证**

Xcode `Cmd-B`,Expected: Build Succeeded

如失败:常见错误 `Cannot find type 'AppGroup' in scope` → 没加 import;或 `'public' modifier cannot be used` → 文件里旧的 `public` 删掉了 — 检查 step C5.2

### Task 6: 把 SeriesBrand.swift 搬过去

- [ ] **Step C6.1: 移动 + 确认 public 标记**

```bash
git mv Pole/Shared/SeriesBrand.swift Packages/PoleSharedKit/Sources/PoleSharedKit/SeriesBrand.swift
```

- [ ] **Step C6.2: Xcode 删 old reference**

同 C5.3 操作。

- [ ] **Step C6.3: 找所有用 SeriesBrand 的地方加 import**

```bash
grep -rln "SeriesBrand\." Pole --include="*.swift" | grep -v "Pole/Shared/"
```

逐个加 `import PoleSharedKit`(如果已经因为 AppGroup 加过了,不再加)

- [ ] **Step C6.4: build 验证**

`Cmd-B`,Expected: Build Succeeded

### Task 7: 搬 WidgetSnapshot.swift

- [ ] **Step C7.1**

```bash
git mv Pole/Shared/WidgetSnapshot.swift Packages/PoleSharedKit/Sources/PoleSharedKit/WidgetSnapshot.swift
```

- [ ] **Step C7.2: 删 Xcode reference,加 import**

```bash
grep -rln "WidgetSnapshot\|widget_snapshot" Pole --include="*.swift" | grep -v "Pole/Shared/"
```

加 `import PoleSharedKit`

- [ ] **Step C7.3: build 验证**

`Cmd-B`,Expected: Build Succeeded

### Task 8: 搬 WidgetSnapshotStore.swift

- [ ] **Step C8.1**

```bash
git mv Pole/Shared/WidgetSnapshotStore.swift Packages/PoleSharedKit/Sources/PoleSharedKit/WidgetSnapshotStore.swift
```

WidgetSnapshotStore 已经 `import Foundation`,内部用了 AppGroup。**因为现在和 AppGroup 同一个 module,不需要 `import PoleSharedKit`**。

- [ ] **Step C8.2: 删 Xcode reference,加 import**

```bash
grep -rln "WidgetSnapshotStore\|WidgetSnapshotBuilder" Pole --include="*.swift" | grep -v "Pole/Shared/"
```

加 `import PoleSharedKit` 到 caller(如 `Pole/PoleApp.swift`, `Pole/Features/Widget/WidgetSnapshotBuilder.swift` 等)

- [ ] **Step C8.3: build 验证**

`Cmd-B`,Expected: Build Succeeded

### Task 9: 删除 Pole/Shared/ 空目录 + 删除 placeholder

- [ ] **Step C9.1: 验证 Pole/Shared/ 已空**

```bash
ls Pole/Shared/
```

Expected: 空目录(或只剩 .DS_Store)

- [ ] **Step C9.2: 删空目录**

```bash
rmdir Pole/Shared 2>/dev/null || rm -rf Pole/Shared
```

- [ ] **Step C9.3: 在 Xcode 中删除 Shared group**

Xcode 左侧 Pole project → `Shared` group 现在应该是空的 → 右键 → Delete → Remove Reference

- [ ] **Step C9.4: 删除 PoleSharedKit 内的 Placeholder.swift**

```bash
rm Packages/PoleSharedKit/Sources/PoleSharedKit/Placeholder.swift
```

(现在有 4 个真实文件,不需要 placeholder)

- [ ] **Step C9.5: build 验证 + commit checkpoint 2**

`Cmd-B`,Expected: Build Succeeded

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(shared): migrate Pole/Shared/* into PoleSharedKit package

- AppGroup, SeriesBrand, WidgetSnapshot, WidgetSnapshotStore moved
- ~5-10 caller files updated with `import PoleSharedKit`
- Pole/Shared/ directory removed

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Part D: 创建 PoleDesignSystem Package + 搬 Pole/Theme

### Task 10: 新建 PoleDesignSystem Package.swift

**Files:**
- Create: `Packages/PoleDesignSystem/Package.swift`
- Create: `Packages/PoleDesignSystem/Sources/PoleDesignSystem/Placeholder.swift`

- [ ] **Step D10.1: 建目录结构**

```bash
mkdir -p Packages/PoleDesignSystem/Sources/PoleDesignSystem
mkdir -p Packages/PoleDesignSystem/Tests/PoleDesignSystemTests
```

- [ ] **Step D10.2: 写 Package.swift**

写入 `Packages/PoleDesignSystem/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PoleDesignSystem",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PoleDesignSystem", targets: ["PoleDesignSystem"]),
    ],
    dependencies: [
        .package(path: "../PoleSharedKit"),
    ],
    targets: [
        .target(
            name: "PoleDesignSystem",
            dependencies: ["PoleSharedKit"]
        ),
        .testTarget(
            name: "PoleDesignSystemTests",
            dependencies: ["PoleDesignSystem"]
        ),
    ]
)
```

(DesignSystem 引用 `SeriesBrand`(在 PoleSharedKit 内),所以这个 package 要依赖 PoleSharedKit)

- [ ] **Step D10.3: Placeholder**

写入 `Packages/PoleDesignSystem/Sources/PoleDesignSystem/Placeholder.swift`:

```swift
internal enum _PoleDesignSystemPlaceholder {}
```

- [ ] **Step D10.4: 验 package 可 build**

```bash
cd Packages/PoleDesignSystem && swift build && cd ../..
```

Expected: Build complete!

- [ ] **Step D10.5: 在 Xcode workspace 加 PoleDesignSystem**

打开 `PoleApp.xcworkspace`:
1. File → Add Package Dependencies → Add Local…
2. 选 `Packages/PoleDesignSystem`
3. Add to Project: `Pole`
4. Click Add Package

Xcode → Pole target → General → Frameworks → "+" → `PoleDesignSystem`

- [ ] **Step D10.6: build 验证**

`Cmd-B`,Expected: Build Succeeded

### Task 11: 搬 DesignSystem.swift

**Files:**
- Move: `Pole/Theme/DesignSystem.swift` → `Packages/PoleDesignSystem/Sources/PoleDesignSystem/DesignSystem.swift`

- [ ] **Step D11.1: 物理移动**

```bash
git mv Pole/Theme/DesignSystem.swift Packages/PoleDesignSystem/Sources/PoleDesignSystem/DesignSystem.swift
```

- [ ] **Step D11.2: 把文件内所有顶级声明改 public**

打开 `Packages/PoleDesignSystem/Sources/PoleDesignSystem/DesignSystem.swift`,**用 Edit 工具**逐个把以下声明从 `enum` / `struct` / `func` 改成 `public enum` / `public struct` / `public func`:

- `enum DS` → `public enum DS`
- 嵌套类型 `DS.Spacing` / `DS.Radius` / `DS.Palette` / `DS.Font` / `DS.Shadow` / `DS.Motion` → 都加 `public`
- 各静态属性如 `static let sm: CGFloat = 4` → `public static let sm: CGFloat = 4`
- `extension View` 内的 modifier 如 `func dsAIBubble() -> some View` → `public func dsAIBubble() -> some View`
- 顶级 struct/class 如 `SegmentedPillPicker` / `AIAvatar` / `StreamingCursor` → 加 `public` + init 也得 `public init`

**重要细节:**
- 如果某个类型只 internal 用(比如某个 private helper),保持 internal
- `init()` 自动 internal — 任何 `public struct` 都要显式写 `public init(...)`
- SwiftUI `body` 必须是 `public var body`

- [ ] **Step D11.3: package 单独 build 验证**

```bash
cd Packages/PoleDesignSystem && swift build 2>&1 | head -50 && cd ../..
```

Expected: Build complete!

如有 error,通常是:
- `'public' attribute cannot apply to private member` — 嵌套层级问题
- `cannot use 'private' in public type` — 改成 internal 或 public

- [ ] **Step D11.4: Xcode 删 old reference**

Xcode 左侧 Pole/Theme group 找 `DesignSystem.swift` → 右键 → Delete → Remove Reference

- [ ] **Step D11.5: 找所有用了 DS namespace 或 SegmentedPillPicker 等的地方加 import**

```bash
grep -rln "DS\.\|SegmentedPillPicker\|AIAvatar\|StreamingCursor\|dsAIBubble\|dsToolCard\|dsDetailList\|dsListCard\|dsHeroBanner\|dsRacingButton\|dsLiveBadge" Pole --include="*.swift" | grep -v "Pole/Theme/"
```

预估 **40-60 个文件**。逐个加 `import PoleDesignSystem`(用 Edit,加在 `import SwiftUI` 后面)

**批量处理建议:** 如果文件多,可以用 sed,但要小心 — 优先 Edit 工具(防误改)

- [ ] **Step D11.6: build 验证**

`Cmd-B`,Expected: Build Succeeded

(这一步最容易遇到大量 `Cannot find 'DS' in scope` 错误,挨个补 import。**Xcode 的 Fix-it 不能用**,因为 SourceKit-LSP 还没识别新 module,要 cli build 才是真相。)

### Task 12: 搬 SeriesTheme.swift

- [ ] **Step D12.1**

```bash
git mv Pole/Theme/SeriesTheme.swift Packages/PoleDesignSystem/Sources/PoleDesignSystem/SeriesTheme.swift
```

- [ ] **Step D12.2: public 化**

`SeriesTheme.swift` 内:
- `extension MotorsportSeries` 内 `var brandColor: Color` / `var brandGradient` → 加 `public`
- `enum BrandPalette` → `public enum BrandPalette`,各 `static let` → `public static let`

**注意 MotorsportSeries:** 该 enum 在 `Pole/Domain/Motorsport/MotorsportSeries.swift`,**还没搬包**(留到 PR2 拆 PoleDomain)。所以 `SeriesTheme.swift` 内 `extension MotorsportSeries` 必须**先能看到 MotorsportSeries**。当前主 app target 内的 MotorsportSeries 不在任何 package — `PoleDesignSystem` 看不到它。

**解决:**
- 临时方案:在 `Packages/PoleDesignSystem/Sources/PoleDesignSystem/SeriesTheme.swift` 顶部加注释 `// Note: depends on MotorsportSeries from main app — will move to PoleDomain in PR2`
- 不行,Swift 包看不到主 app 内的类型,**这步必须等 PoleDomain 拆完再做** OR 临时把 `MotorsportSeries` enum 复制一份到 PoleSharedKit
- **决策:** 不搬 `SeriesTheme.swift`,留在主 app target 里直到 PR2 拆 PoleDomain

撤销:

```bash
git mv Packages/PoleDesignSystem/Sources/PoleDesignSystem/SeriesTheme.swift Pole/Theme/SeriesTheme.swift
```

- [ ] **Step D12.3: 跳过 D12.2 的搬运,继续走**

`SeriesTheme.swift` 留在 `Pole/Theme/`,本 PR 不动。**写注释到 spec 提醒 PR2 搬。**

更新 spec(本 PR commit 一起):打开 `docs/superpowers/specs/2026-05-14-architecture-refactor-design.md`,在 Section 10.2 "已知坑点" 末尾加一条:

```markdown
- `Pole/Theme/SeriesTheme.swift` 因为 extends `MotorsportSeries`(还在 main app)
  暂留在 `Pole/Theme/`,PR2 拆 `PoleDomain` 时一起搬到 `PoleDesignSystem`
```

### Task 13: 搬 RacingComponents.swift

- [ ] **Step D13.1**

```bash
git mv Pole/Theme/RacingComponents.swift Packages/PoleDesignSystem/Sources/PoleDesignSystem/RacingComponents.swift
```

- [ ] **Step D13.2: public 化**

打开文件,把 4 个顶级 struct 改成 `public struct`,各 init 改 `public init(...)`,各 body 改 `public var body`:
- `SeriesTopAccent`
- `CheckerStripe`
- `StartLightGrid` (含 `.mode(forMinutesUntilStart:)` static method,也要 public)
- `SpeedLinesOverlay`

**注意 SeriesTopAccent 是否需要 MotorsportSeries:** 如果它的 init 接 `series: MotorsportSeries`,**同 D12 问题**,需要再撤销。

**检查:**

```bash
grep -n "MotorsportSeries\|series:" Packages/PoleDesignSystem/Sources/PoleDesignSystem/RacingComponents.swift
```

如果用了 MotorsportSeries,**撤销搬运**,留主 app target,放到 PR2 一起搬。

如果没用(应该没用,SeriesTopAccent 接的是 `Color`),继续。

- [ ] **Step D13.3: package build 验证**

```bash
cd Packages/PoleDesignSystem && swift build && cd ../..
```

- [ ] **Step D13.4: Xcode 删 old reference + find/import**

```bash
grep -rln "SeriesTopAccent\|CheckerStripe\|StartLightGrid\|SpeedLinesOverlay" Pole --include="*.swift" | grep -v "Pole/Theme/"
```

逐个加 `import PoleDesignSystem`(已加过的不重复)

- [ ] **Step D13.5: build 验证**

`Cmd-B`,Expected: Build Succeeded

### Task 14: 删 Placeholder + commit checkpoint 3

- [ ] **Step D14.1**

```bash
rm Packages/PoleDesignSystem/Sources/PoleDesignSystem/Placeholder.swift
```

`Cmd-B`,Expected: Build Succeeded

- [ ] **Step D14.2: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(theme): migrate DesignSystem + RacingComponents into PoleDesignSystem

- DesignSystem.swift, RacingComponents.swift moved to package
- SeriesTheme.swift remains in main app (extends MotorsportSeries; will
  move in PR2 alongside PoleDomain)
- ~40-60 caller files updated with `import PoleDesignSystem`

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Part E: 引入 AppRouter

### Task 15: 创建 AppRouter

**Files:**
- Create: `Packages/PoleSharedKit/Sources/PoleSharedKit/Router/AppRouter.swift`

- [ ] **Step E15.1: 建 Router 目录**

```bash
mkdir -p Packages/PoleSharedKit/Sources/PoleSharedKit/Router
```

- [ ] **Step E15.2: 写 AppRouter.swift**

写入 `Packages/PoleSharedKit/Sources/PoleSharedKit/Router/AppRouter.swift`:

```swift
import SwiftUI

/// 集中管理 5 个 Tab 的 navigation path 与跨 Tab 深链。
/// 用作 `@Environment(AppEnv.self)` 中的 router 字段。
@MainActor
@Observable
public final class AppRouter {

    /// Tab 标识。值与 ContentView 中 segment picker 的顺序一致。
    public enum Tab: Hashable, CaseIterable, Sendable {
        case motorsport
        case standings
        case chat
        case follow
        case settings
    }

    /// 详情页 destination。每个 Tab 的 NavigationStack(path:) 用这个类型。
    /// 注意:RoundDetail 需要 `AnyMotorsportRound`,该类型本 PR 不动(仍在 main app);
    /// 因为 PoleSharedKit 看不到它,Destination case 暂时用 `(series:roundId:)` 间接表示。
    /// PR2 拆 PoleDomain 后再改回 `AnyMotorsportRound`。
    public enum Destination: Hashable, Sendable {
        case roundDetail(series: String, roundId: String)
        case driverDetail(series: String, driverId: String)
        case teamDetail(series: String, teamId: String)
    }

    public var selectedTab: Tab = .motorsport
    public var motorsportPath: [Destination] = []
    public var standingsPath: [Destination] = []
    public var chatPath: [Destination] = []
    public var followPath: [Destination] = []
    public var settingsPath: [Destination] = []

    public init() {}

    /// 跳转入口:任意 Live Activity / Notification / Spotlight / AppIntent 触发深链都走这里。
    /// 内部根据 destination 类型路由到对应 Tab 的 stack。
    public func deeplink(to destination: Destination) {
        switch destination {
        case .roundDetail:
            selectedTab = .motorsport
            motorsportPath.append(destination)
        case .driverDetail, .teamDetail:
            selectedTab = .standings
            standingsPath.append(destination)
        }
    }

    /// 清空指定 Tab 的 stack(回到该 Tab 的 root)
    public func popToRoot(_ tab: Tab) {
        switch tab {
        case .motorsport: motorsportPath.removeAll()
        case .standings:  standingsPath.removeAll()
        case .chat:       chatPath.removeAll()
        case .follow:     followPath.removeAll()
        case .settings:   settingsPath.removeAll()
        }
    }
}
```

- [ ] **Step E15.3: package 单独 build 验证**

```bash
cd Packages/PoleSharedKit && swift build && cd ../..
```

Expected: Build complete!

### Task 16: 把 ContentView 改成用 AppRouter 管 path(但不删 NotificationCenter,留并行)

**Files:**
- Modify: `Pole/ContentView.swift`

- [ ] **Step E16.1: 读 ContentView 当前实现**

```bash
wc -l Pole/ContentView.swift
```

预估 100-200 行。先 Read 完整看清。

- [ ] **Step E16.2: 加 import + 接管 selectedTab + 5 个 NavigationStack(path:)**

**这一步的修改面较大,**需要根据 ContentView 实际代码结构改。核心改动:

1. 顶部加 `import PoleSharedKit`
2. 把 `@State private var selectedTab: Tab = .motorsport`(如果存在)删掉,改为读 `@Environment(AppEnv.self) var env`(下个 Task 才有 AppEnv,**这一步先不接 env**,临时持一份 `@State var router = AppRouter()`,后面 step E18.x 改 environment)
3. 每个 Tab 的 NavigationStack 改成 `NavigationStack(path: $router.motorsportPath) { ... }`(因 5 个 Tab,5 个 stack)
4. 给每个 Tab View 的 `.navigationDestination(for: AppRouter.Destination.self) { destination in ... }`,内部 switch 三个 case 跳到 detail view
5. 保留旧的 NotificationCenter `.onReceive(.openRaceDetail)`,在 closure 内同时 post 新 router(走 router.deeplink),验证后下一 PR 删 NotificationCenter

具体编辑由实施 agent 根据 ContentView 当前结构落地。**关键约束:不删 NotificationCenter,新旧路径并存,**这样如果 router 路径有问题,旧路径还能 deeplink 兜底。

- [ ] **Step E16.3: build + 手测 5 个 Tab 切换正常**

`Cmd-B` + Run on Simulator

测试清单:
- 5 个 Tab 都能点中切换 ✓
- 进任一 round detail,返回 root,再进另一个 round,正常 ✓
- 切到别的 Tab 再切回来,navigation stack 保留 ✓
- 测试 deeplink:杀 app,从主屏 widget 点关注的下场比赛,跳到详情 ✓
- 测试 deeplink:发个通知触发 .openRaceDetail,跳详情 ✓

- [ ] **Step E16.4: commit checkpoint 4**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(router): introduce AppRouter for centralized navigation

- AppRouter @Observable holds selectedTab + per-tab navigation path
- ContentView migrated to use router for 5 NavigationStack(path:) bindings
- Existing NotificationCenter deeplink path retained in parallel
  (will be removed in PR3 once router is verified)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Part F: 引入 AppEnv + 迁 AppearanceStore 到 @Observable

### Task 17: 把 AppearanceStore 从 ObservableObject 改成 @Observable

**Files:**
- Modify: `Pole/Domain/AppearanceMode.swift`

- [ ] **Step F17.1: Read 当前实现**

```bash
cat Pole/Domain/AppearanceMode.swift
```

期望看到 `public final class AppearanceStore: ObservableObject` + `@Published var current: AppearanceMode`。

- [ ] **Step F17.2: Edit 文件**

把:

```swift
public final class AppearanceStore: ObservableObject {
    @Published public var current: AppearanceMode = ...
    ...
}
```

改成:

```swift
@MainActor
@Observable
public final class AppearanceStore {
    public var current: AppearanceMode = ...
    ...
}
```

(把 `ObservableObject` 改 `@Observable` + 加 `@MainActor` + 删所有 `@Published`)

- [ ] **Step F17.3: 找 caller 改 property wrapper**

```bash
grep -rln "@StateObject.*AppearanceStore\|@ObservedObject.*AppearanceStore\|@EnvironmentObject.*AppearanceStore" Pole --include="*.swift"
```

对每个 caller:
- `@StateObject private var appearance = AppearanceStore.shared` → 暂保留(下个 step 改 environment)
- `@ObservedObject var appearance: AppearanceStore` → 改 `@Bindable var appearance: AppearanceStore`(如果可 mutate)或直接 `let appearance: AppearanceStore`(如果只读)
- `.environmentObject(AppearanceStore.shared)` → 改 `.environment(AppearanceStore.shared)`(去掉 Object 后缀)

- [ ] **Step F17.4: build 验证**

`Cmd-B`,Expected: Build Succeeded

如失败:
- `'Property wrappers are not yet supported'` → @Observable 与 @Published 不兼容,确认所有 @Published 已删
- `Cannot find type 'AppearanceStore' in scope` → import 缺失

### Task 18: 创建 AppEnv

**Files:**
- Create: `Packages/PoleSharedKit/Sources/PoleSharedKit/Env/AppEnv.swift`

- [ ] **Step F18.1: 建 Env 目录**

```bash
mkdir -p Packages/PoleSharedKit/Sources/PoleSharedKit/Env
```

- [ ] **Step F18.2: 写 AppEnv.swift(只装 router 字段,appearance 留下 PR 加)**

写入 `Packages/PoleSharedKit/Sources/PoleSharedKit/Env/AppEnv.swift`:

```swift
import SwiftUI

/// 全局应用环境对象 — 通过 `@Environment(AppEnv.self)` 注入到所有 SwiftUI View。
///
/// 本 PR 只暴露 `router`。后续 PR 增量加 `appearance` / `follow` / `motorsport` /
/// `llm` / `knowledge` / 其他全局服务。
@MainActor
@Observable
public final class AppEnv {
    public let router: AppRouter

    public init(router: AppRouter = AppRouter()) {
        self.router = router
    }

    /// 标准 bootstrap 入口,主 app `@main` 调用一次。
    public static func bootstrap() -> AppEnv {
        AppEnv()
    }
}
```

(注意:**不放 `appearance: AppearanceStore` 字段**,因为 AppearanceStore 在 main app 的 `Pole/Domain/AppearanceMode.swift`,PoleSharedKit 看不到。等 PR2 把 Domain 拆出来后再加。本 PR 主 app 直接用 `@Environment(AppearanceStore.self)` + `.environment(AppearanceStore.shared)`。)

- [ ] **Step F18.3: package build 验证**

```bash
cd Packages/PoleSharedKit && swift build && cd ../..
```

Expected: Build complete!

### Task 19: 在 PoleApp.swift 接入 AppEnv

**Files:**
- Modify: `Pole/PoleApp.swift`

- [ ] **Step F19.1: 修改 PoleApp.swift**

打开 `Pole/PoleApp.swift`,加 import:

```swift
import SwiftUI
import SwiftData
import PoleSharedKit                              // 新增
```

把 `@StateObject private var appearance = AppearanceStore.shared` 删掉,改成:

```swift
@State private var env = AppEnv.bootstrap()
@State private var appearance = AppearanceStore.shared
```

把 body 改成:

```swift
var body: some Scene {
    WindowGroup {
        ContentView()
            .preferredColorScheme(appearance.current.colorScheme)
            .environment(env)
            .environment(appearance)                          // 新增
            .task {
                WidgetSnapshotBuilder.refresh()
                await KnowledgeImporter.importIfNeeded(
                    context: Self.sharedModelContainer.mainContext
                )
            }
    }
    .modelContainer(Self.sharedModelContainer)
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active {
            WidgetSnapshotBuilder.refresh()
        }
    }
}
```

- [ ] **Step F19.2: 修改 ContentView.swift 替换临时 @State router 为 env.router**

ContentView Step E16.2 临时持的 `@State var router = AppRouter()` 改成:

```swift
@Environment(AppEnv.self) private var env
private var router: AppRouter { env.router }
```

(`router` 不需要可变,所以 computed property 即可)

- [ ] **Step F19.3: 把所有 `@StateObject ... AppearanceStore.shared` 用法改成 `@Environment(AppearanceStore.self) var appearance`**

```bash
grep -rln "@StateObject.*AppearanceStore" Pole --include="*.swift"
```

逐个改。注意 `AppearanceStore.shared` 不再需要单例语法 — environment 已经分发了同一实例。

- [ ] **Step F19.4: build + 手测**

`Cmd-B`,Run on Simulator。测试:
- 5 个 Tab 切换正常 ✓
- 切到 Settings,改 Appearance(Light/Dark/Auto),整个 app 立即反应(色彩变) ✓
- 杀 app 重开,Appearance 保留 ✓
- Deeplink 测试同 Task 16 ✓

- [ ] **Step F19.5: commit checkpoint 5**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(env): introduce AppEnv and migrate AppearanceStore to @Observable

- AppEnv (@Observable in PoleSharedKit) holds AppRouter; injected via
  .environment(env) in PoleApp.swift
- AppearanceStore: ObservableObject → @Observable + @MainActor
- All @StateObject/@ObservedObject usages migrated to @Environment

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Part G: 完成判定

### Task 20: Cold build verification

- [ ] **Step G20.1: 清 DerivedData**

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Pole-*
```

- [ ] **Step G20.2: cold build 主 app**

```bash
xcodebuild -workspace PoleApp.xcworkspace -scheme Pole \
  -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`

(用 generic/platform 而不是具体 iPhone,本地没有指定 simulator 也能 build)

- [ ] **Step G20.3: 跑现有 test bundle(确保没破坏)**

```bash
xcodebuild -workspace PoleApp.xcworkspace -scheme Pole \
  -destination 'platform=iOS Simulator,name=iPhone 15' test 2>&1 | tail -50
```

Expected: Test Succeeded(或 0 tests run — 当前 PoleTests 是 placeholder)

如失败原因是测试本身:
- 看是否是测试中 import 缺失(新 module 没 import) → 加 `@testable import PoleSharedKit / @testable import PoleDesignSystem`

### Task 21: Manual happy path

- [ ] **Step G21.1: 在 Simulator 跑通完整流程**

打开 `PoleApp.xcworkspace`,Run on iPhone 15 Pro Simulator,验证:

1. App 启动 → 进入 motorsport tab ✓
2. 切 5 个 Tab 都正常显示 ✓
3. 进 round detail(任一系列) ✓
4. 返回 + 切到 standings → 进 driver detail ✓
5. AI Tab → 发一条简单消息(`你好`) → 正常回复 ✓
6. Follow Tab → 关注/取关 → 持久化 ✓
7. Settings Tab → 改 Appearance → 立即生效 + 重启保留 ✓

任意一项失败:
- 截图 + 报告 issue
- 视严重度决定是 fix 还是 revert

### Task 22: Final commit + tag

- [ ] **Step G22.1: 确认 git status 干净**

```bash
git status
```

Expected: `nothing to commit, working tree clean`

- [ ] **Step G22.2: 推 branch**

```bash
git push -u origin pr1/spm-workspace-setup
```

- [ ] **Step G22.3: 起 PR(交给用户)**

输出给用户:

> PR1 已推上 `pr1/spm-workspace-setup`。请到 GitHub 起 PR。
> 完成判定全过:cold build / tests / manual happy path 全 pass。
>
> PR1 落地后我会写 PR2(拆 `PoleDomain` + `PoleMotorsportKit`)的 plan。

---

## 回滚 Plan(如果中途失败)

如果在任何 commit checkpoint 之后发现严重问题:

```bash
# 回到上一个 checkpoint
git reset --hard HEAD~1

# 或回到 PR 开始前
git reset --hard pre-pr1-backup
```

如果已经 push 但还没 merge:

```bash
# 强推回滚(只对 PR branch 安全,不要在 main 上做)
git push --force origin pr1/spm-workspace-setup
```

---

## 风险与已知坑

| 风险 | 触发 | 应对 |
|---|---|---|
| Xcode 添加本地 package 失败(File → Add Package → Add Local 不响应) | macOS 偶发 | 关 Xcode,删 `~/Library/Developer/Xcode/DerivedData/Pole-*` 和 `~/Library/Caches/org.swift.swiftpm`,重开 |
| `Cannot find type 'X' in scope`(types now in package) | 漏 import | grep 找所有 caller,补 `import PoleSharedKit` / `import PoleDesignSystem` |
| `'public' modifier cannot be applied to private member` | 嵌套 access level 不对 | 沿着 type 树看清 outer 是不是 public,内部不能更 public |
| SourceKit-LSP 全红 | 已知,DerivedData 翻新 | 不要相信 IDE,用 `xcodebuild` cli 看 ground truth |
| Widget 路径 import 报错 | 不该发生 | widget extension target 不在 pbxproj,Pole/Widgets/ 的 source 不被编译 |
| AppearanceStore 迁 @Observable 后 UI 不更新 | 没改 @Bindable | 检查 caller property wrapper,有些 ObservedObject 要改 Bindable |

---

## Spec Mapping

本 plan 实现的 spec 章节:
- Section 2.1 拓扑 → Task 1, 3, 10(workspace + 2 个 package)
- Section 2.2 决策 → 全过程遵守(public 化、SeriesTheme/RacingComponents 暂留主 app 决策见 Task 12)
- Section 4.2 AppRouter → Task 15, 16
- Section 4.1 AppEnv 骨架 → Task 18, 19
- Section 10.2 PR1 风险细节 → Task 0(backup) + Task 22(回滚说明)

**本 PR 不实现的 spec 内容(留后续 PR):**
- Section 3.1 `MotorsportSeriesService` protocol → PR2-3
- Section 3.3 `LoadingViewModel` → PR2
- Section 5 全部性能优化 → PR6
- Section 6 PoleError + Logger → PR2
- Section 7 翻译完整性 → PR7
- Section 8 测试基础设施 → PR7
