# PoleWidgets 配置(Mac Xcode 端一次性设置)

主屏 Widget(下场比赛)+ Live Activity(灵动岛 / 锁屏)代码已写好,Linux 端无法操作 Xcode,需在 Mac 端走以下步骤一次。

## 1. 添加 Widget Extension target

1. Xcode 打开 `Pole.xcodeproj`
2. **File → New → Target...**
3. 选 **Widget Extension** → Next
4. 配置:
   - Product Name: **`PoleWidgets`**(必须复数,跟现有目录名一致)
   - Bundle Identifier: 自动 = `com.tiebowen.Pole.PoleWidgets`
   - Include Live Activity: **✓ 勾上**
   - Include Configuration Intent: **不勾**
   - Team: 跟主 app 一致
5. Finish → "Activate scheme":选 **No**(不切走主 scheme)

Xcode 会询问是否覆盖已有的 `Info.plist` —— 选**保留现有**(我们的 Info.plist 已配好)。

Xcode 会自动生成几个模板 .swift 文件(`PoleWidgets.swift` / `PoleWidgetsBundle.swift` 等)。

## 2. 删除 Xcode 自动生成的模板 .swift

仓库里 `PoleWidgets/` 已经有正式版本,所以删掉 Xcode 刚生成的模板:
- `PoleWidgets.swift`(空 widget)
- `PoleWidgetsBundle.swift`(模板版本) — 注意:**保留**仓库里同名文件
- `PoleWidgetsLiveActivity.swift`(模板)
- `PoleWidgetsAttributesIntent.swift`(若存在)
- `PoleWidgetsControl.swift`(若存在)

**保留**:`Info.plist` / `PoleWidgets.entitlements` / `Assets.xcassets`。

## 3. 把仓库里 7+ 个 widget 源文件挂进 PoleWidgets target

仓库结构:
```
PoleWidgets/
├── Info.plist
├── PoleWidgetsBundle.swift          ← @main,注册两个 widget
├── RaceLiveActivityWidget.swift       ← 老 Live Activity widget(锁屏 + 灵动岛)
└── NextRace/
    ├── NextRaceProvider.swift         ← TimelineProvider,读 App Group JSON
    ├── NextRaceWidget.swift           ← Widget definition + family 路由
    └── Views/
        ├── SmallView.swift
        ├── MediumView.swift
        ├── LargeView.swift
        ├── AccessoryRectangularView.swift
        ├── AccessoryCircularView.swift
        └── AccessoryInlineView.swift
```

操作:
1. 右键 Project navigator 里的 `PoleWidgets` group → **Add Files to "Pole"...**
2. 选上面 11 个 .swift 文件(可以一次性全选目录)
3. **Target Membership**:**只勾 PoleWidgets**,**不勾 Pole** 主 app

## 4. 跨 target 共享文件 — 双勾 Pole + PoleWidgets

下面这些文件主 app 用、widget 也用,**Target Membership 两边都勾**:

| 文件 | 责任 |
|---|---|
| `Pole/Shared/AppGroup.swift` | App Group ID 常量 + container URL helper |
| `Pole/Shared/WidgetSnapshot.swift` | 主 app 写、widget 读的 Codable DTO |
| `Pole/Shared/WidgetSnapshotStore.swift` | 读写 JSON 工具 |
| `Pole/Shared/SeriesBrand.swift` | 跨 target 系列品牌色查表 |
| `Pole/Features/LiveActivity/RaceLiveActivityAttributes.swift` | Live Activity Attributes + ContentState |
| `Pole/Sports/Intents/AppIntents.swift` | `StopLiveActivityIntent`(灵动岛"停止"按钮)+ `OpenRaceDetailIntent` |
| `Pole/Sports/Intents/RaceAppEntity.swift` | `OpenRaceDetailIntent` 的 Parameter 类型 |

> 操作:Project navigator 选中文件 → 右侧 inspector → **Target Membership** 区域勾上 PoleWidgets。
>
> Xcode 26 fileSystemSynchronizedGroups 仍支持 per-file membership exception,pbxproj 会自动写入。

## 5. 加 App Group capability(两个 target 都要)

App Group identifier:**`group.com.tiebowen.Pole`**

1. **Pole** target → Signing & Capabilities → **+ Capability** → **App Groups** → 列表里 + → 输入 `group.com.tiebowen.Pole`,回车,**勾选**
2. **PoleWidgets** target → Signing & Capabilities → **+ Capability** → **App Groups** → 选刚才那个,**勾选**

确认两个 target 的 .entitlements 文件都包含:
```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.tiebowen.Pole</string></array>
```

## 6. 确认主 app NSSupportsLiveActivities 已加

主 app target → Build Settings → 搜 `INFOPLIST_KEY_NSSupportsLiveActivities` —— pbxproj 已有 `INFOPLIST_KEY_NSSupportsLiveActivities = YES;`,无需改动。

## 7. Build & 测试

```bash
xcodebuild -project Pole.xcodeproj -scheme Pole \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' build
```

预期:整个工程(主 app + PoleWidgets extension)都 build 通过。

### 主屏 Widget 测试(模拟器)
1. Run → 主 app 启动一次让 `WidgetSnapshotBuilder.refresh()` 写 JSON
2. 长按主屏空白 → + → 找 Pole → 加 Small / Medium / Large 各一个
3. 长按锁屏 → 自定义 → 加 accessoryRectangular / accessoryCircular / accessoryInline

### Live Activity 测试(真机推荐)
1. RaceDetailView "开始跟看"按钮触发(weekendStart 在 8 小时窗口内)
2. 锁屏出现卡片;iPhone 14 Pro+ 灵动岛点亮
3. 灵动岛长按展开:左 leading + 右 trailing + center 进度条 + bottom + "停止"按钮
4. 点"停止"或 Settings 里"灵动岛 / 锁屏陪伴"toggle 关 → 立刻消失

## 故障排查

| 症状 | 原因 | 修复 |
|---|---|---|
| `Cannot find 'SeriesBrand' in scope`(widget 端) | Shared/* 没双勾 | step 4 重勾 |
| `Cannot find 'WidgetSnapshot' in scope` | 同上 | 同上 |
| `Cannot find 'RaceLiveActivityAttributes' in scope`(widget 端) | LiveActivity/RaceLiveActivityAttributes.swift 没双勾 | step 4 重勾 |
| `Cannot find 'StopLiveActivityIntent' in scope`(widget 端) | AppIntents.swift 没双勾 | step 4 |
| `multiple definitions of '_main'` | 没删 Xcode 模板 PoleWidgetsBundle.swift | step 2 |
| Activity 启动后立刻消失 | weekendEnd 已过 / staleDate 太近 | 用未来 race 测 |
| 灵动岛不显示 | iOS < 16.1 / 非 Pro 机型 / 模拟器没选 14Pro+ | 换设备 |
| widget 显示赛季结束 | App Group ID 拼错 / 主 app 没启动一次 | 启动主 app 让 builder 写 snapshot |
| `entitlement com.apple.security.application-groups doesn't match` | App Group ID 拼错或两端不一致 | step 5 重新加 |
