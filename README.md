# Pole

Pole 是一款 iOS 赛车赛事助手，覆盖 F1、MotoGP、WorldSBK 和 Formula E，提供赛历、积分榜、比赛详情、通知、桌面组件和 AI 助手。

## Features
- 多系列赛事追踪：F1、MotoGP、WorldSBK、Formula E
- 赛历、积分榜、比赛详情、车手信息
- 本地通知、日历写入、桌面组件、Live Activity
- AI 助手、新闻聚合、天气信息、关注系统

## Tech Stack
- SwiftUI
- SwiftData
- WidgetKit / ActivityKit
- App Intents
- Xcode project（`Pole.xcodeproj`）

## Getting Started
1. 使用 Xcode 打开 `Pole.xcodeproj`
2. 选择 `Pole` scheme
3. 按需配置 `DS_API_KEY`
4. 在 iPhone 模拟器或真机运行

## Development
- 构建：`xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' build`
- 测试：`xcodebuild -project Pole.xcodeproj -scheme Pole -destination 'platform=iOS Simulator,name=iPhone 14 Pro' test`

## Docs
- API Key 配置：`docs/api-key-setup.md`
- 真机部署：`docs/deploy.md`
- Widget 配置：`PoleWidgets/SETUP.md`
