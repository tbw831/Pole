# Pole 1.0 真机部署指南

**目标**：把 Pole 装到自己的 iPhone 14 Pro 上正常运行。
**适用人群**：仓库 owner 自用（铁博文）。
**预计耗时**：首次 30 分钟，后续每周 5 分钟（7 天证书过期重签）。

---

## 部署模式：Free Provisioning（个人 Apple ID 免费签名）

| 维度 | 现状 |
|---|---|
| 成本 | 免费（用普通 Apple ID 即可） |
| 证书有效期 | 7 天，每周需要连 Mac 重新 Run 一次 |
| 设备数上限 | 同一 Apple ID 最多 3 台 |
| 不支持的能力 | 远程 Push（**项目用本地通知，不影响**）/ CloudKit / IAP |
| 支持的能力 | 本地通知 ✓、Live Activity ✓、ActivityKit ✓、SwiftData ✓、所有项目实际用到的 capability ✓ |

> 想升级到 1 年证书 / TestFlight 分发 → 加入 Apple Developer Program $99/年（本指南末尾"后续路径"）。

---

## 一次性 audit 结论（已替你检查过 pbxproj）

下面这些**已经配好，不用动**：

| 项 | 配置 | 备注 |
|---|---|---|
| Deployment Target | `IPHONEOS_DEPLOYMENT_TARGET = 26.2` | iPhone 14 Pro 升 iOS 26 即可 |
| Swift 版本 | `SWIFT_VERSION = 5.0` | OK |
| 设备族 | `TARGETED_DEVICE_FAMILY = "1,2"` | iPhone + iPad |
| 自动签名 | `CODE_SIGN_STYLE = Automatic` | OK |
| Bundle ID | `com.tiebowen.Pole` | 主 app；测试 target `.PoleTests` / `.PoleUITests` |
| 版本 | `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` | **已经是 1.0**，不用改 |
| Live Activity | `INFOPLIST_KEY_NSSupportsLiveActivities = YES` | OK |
| 权限文案（中文） | 日历 / 麦克风 / Speech 三个 usage description 都有 | OK |
| API Key 注入 | `INFOPLIST_KEY_DSAPIKey = "$(DS_API_KEY)"` | **build 时取环境变量** `DS_API_KEY` 写到 Info.plist 的 `DSAPIKey` 字段 |

下面这些**需要你 Mac 端做一次**：

| 项 | 你要做什么 |
|---|---|
| `DEVELOPMENT_TEAM` | pbxproj 没硬写，Xcode 里第一次打开会让你选 |
| `DS_API_KEY` 环境变量 | 必须设，不然 AI tab 不可用（详见下方"AI 助手 API Key"） |
| 14 Pro 开发者模式 | iOS 16+ 必开，否则 app 装不上 |

---

## 第一次部署：完整步骤

### Step 0：Mac 准备（5 分钟）

**0.1 装最新 Xcode**：
- App Store 装 Xcode 26+（项目要求 iOS 26.2 SDK）
- 第一次启动 Xcode 会下 iOS Simulator runtime 等组件，等完成

**0.2 Xcode 登录 Apple ID**：
- Xcode → Settings (Cmd+,) → **Accounts** 标签
- 点 `+` → Apple ID → 输入你的 Apple ID（不需要付费开发者）
- 登录后会出现 "你的名字 (Personal Team)" —— 这就是你的免费 team

**0.3 装项目代码**（已 done）：
- 仓库已在本地 `/data00/home/tiebowen/project/Pole/`（Linux 这边维护源码）
- 需要把仓库**同步到 Mac**：
  - 走 git remote（推到 GitHub 私有仓库再在 Mac clone）—— 推荐
  - 或者 scp / rsync 整个目录到 Mac
  - 或者 Mac 直接 ssh 来 Linux 这边的目录（不推荐，编译会反复读盘）

> 如果选 git remote：在 GitHub 建私有仓库 → `git remote add origin <url>` → `git push -u origin main`，然后 Mac 端 `git clone`。

### Step 1：14 Pro 准备（2 分钟）

**1.1 升级到 iOS 26**：
- 设置 → 通用 → 软件更新 → 升到 iOS 26.x（项目要求 26.2，所以至少 26.0）
- 不升的话 app 装不上

**1.2 开启开发者模式**（iOS 16+ 强制）：
- 设置 → 隐私与安全性 → **开发者模式** → 打开
- 提示重启，确认 → 重启
- 重启后再确认一次"打开开发者模式" → 输入锁屏密码 → 完成

**1.3 USB 连 Mac**：
- 用原装数据线（或经过认证的）连
- 14 Pro 弹"信任此电脑" → 信任 → 输锁屏密码

> 也支持无线（同 WiFi 同 Apple ID 的 Mac/iPhone），但首次必须 USB。无线在 Xcode → Window → Devices and Simulators 里勾 "Connect via network"。

### Step 2：Xcode 配置（5 分钟）

**2.1 打开项目**：Mac 端 Finder 双击 `Pole.xcodeproj`（不是 `.xcworkspace`，本项目无 SPM 依赖）

**2.2 选 Team**：
- 左侧 navigator 选 `Pole` 蓝色项目根
- 中间编辑区选 **TARGETS → Pole**
- **Signing & Capabilities** 标签页
- "Automatically manage signing" 已勾 ✓
- **Team** 下拉 → 选 "你的名字 (Personal Team)"

**2.3 处理可能的 Bundle ID 冲突**（仅当 Xcode 报红色错误时）：
- 如果 Xcode 显示 `Failed to register bundle identifier ... is not available`，说明 `com.tiebowen.Pole` 已被别的 Apple ID 占用
- 修复：把 Bundle Identifier 改成 `com.tiebowen.Pole.dev`（或任何唯一字符串）
- **同步把 PoleTests 和 PoleUITests 两个 target 的 Bundle ID 后缀也改了**（保持 `.PoleTests` / `.PoleUITests` 层级，前缀跟主 app 一致）

**2.4 同样给 PoleTests / PoleUITests 选 Team**：
- TARGETS → PoleTests → Signing & Capabilities → Team 选同一个 Personal Team
- TARGETS → PoleUITests → 同上

> 不选 Team，Run 时会提示签名错误。

### Step 3：配 DeepSeek API Key（必须，否则 AI tab 不工作）

项目用 **DeepSeek 的 `deepseek-chat` 模型**（OpenAI 兼容协议）。Key 通过 `DS_API_KEY` 环境变量在 build 时注入到 Info.plist 的 `DSAPIKey` 字段。

**3.1 拿到 DeepSeek API Key**：
- 上 https://platform.deepseek.com/api_keys 申请（或用现有 key）
- 长得像 `sk-xxxxxxxxxxxxxxxxxxxx`

**3.2 在 Xcode scheme 里加环境变量**（推荐，不入仓库）：
- Xcode 顶栏：**Product → Scheme → Edit Scheme...** (或 Cmd+Shift+,)
- 左边选 **Run** → 右边选 **Arguments** 标签
- **Environment Variables** 区域 → `+` → 加：
  - Name: `DS_API_KEY`
  - Value: `sk-xxxxxxxxxxxxxxxxxxxx`（你的 key）
- Close

**3.3 验证（可选）**：
- Run 一次后，进 app 的 AI tab 输入"你好"
- 如果出错"未配置 DeepSeek API Key" → 环境变量没生效，重检查
- 如果有正常回复 → 配好了

> **注意**：环境变量只在 Xcode 启动 build 时生效。如果你用 `xcodebuild` 命令行 build，要 `DS_API_KEY=sk-xxx xcodebuild ...` 这样传。

### Step 4：选 14 Pro 作为 Run destination

- Xcode 顶栏中央的 device picker（默认显示 "Pole"）
- 下拉 → **iOS Device** 区域选 **你的 14 Pro 名字**（不要选模拟器！模拟器名字带 "iPhone 14 Pro"，真机名字是你给手机起的名）
- 如果没显示 14 Pro：
  - 检查 USB 连着、屏幕亮着、已解锁
  - Xcode → Window → Devices and Simulators 看设备状态
  - 14 Pro 上没"信任此电脑" → 拔了重插

### Step 5：Run（Cmd+R）

**5.1 点 Run 按钮（▶️）或 Cmd+R**

**5.2 第一次会经历**：
- Build 成功（约 1-3 分钟首次编译）
- 装到 14 Pro
- **失败**："Untrusted Developer" 弹窗 —— 这是预期行为，第一次必有

**5.3 14 Pro 端信任开发者**：
- 14 Pro：设置 → 通用 → **VPN 与设备管理**（iOS 26 可能叫"设备管理"）
- 找到"开发者 App" → 点你的 Apple ID
- "信任 [你的 Apple ID]"
- 确认信任

**5.4 Mac 再 Cmd+R 一次**：
- 这次 app 应该能正常启动，进 ContentView，看到赛车 / 积分榜 / AI / 关注 / 设置 5 个 tab
- 走过通知权限弹窗（系统第一次启动会弹）→ 选"允许"或"不允许"都可

**5.5 跑通 smoke test**：
- 赛车 tab：能加载 F1 / MotoGP / WSBK / FE 列表（要联网）
- 积分榜 tab：能切系列看积分
- AI tab：发"下一场 F1 是什么时候" → 看 LLM 流式回答（验证 API Key 工作）
- 关注 tab：空白（首次没关注）
- 设置 tab：能切语言 / 通知开关

---

## Widget Extension 怎么办？

**首次部署可以先跳过**——Widget Extension 的 target 还没在 Xcode 项目里加（看 `PoleWidgets/SETUP.md`）。

主 app 在 14 Pro 上跑通后，再按 `PoleWidgets/SETUP.md` 一次性接入 Widget Extension（约 10 分钟），重新 Cmd+R 就能用：
- 主屏 widget（small / medium / large + 锁屏 accessory 三尺寸）
- 灵动岛 / 锁屏 Live Activity（开始跟看一场赛事时）

接 Widget 时**会同时加 App Group capability** `group.com.tiebowen.Pole`，让主 app 写的 widget snapshot 能被 widget extension 读。Free Provisioning 支持 App Group，没问题。

---

## 7 天证书循环维护

Free Provisioning 的证书 7 天后过期，14 Pro 上 app 启动时会闪退或弹"无法验证 App"。

**重签步骤**：
1. 14 Pro 接 Mac
2. Xcode 打开项目
3. Cmd+R（不需要改任何配置，Xcode 自动重签）
4. 又能用 7 天

避免循环 → 升级付费 Apple Developer Program $99/年（证书 1 年）。

---

## 常见故障排查

| 症状 | 原因 | 修复 |
|---|---|---|
| Build 失败 "No account" / "Choose Team" | 没在 Xcode 登 Apple ID 或没选 Team | Step 2 |
| Build 失败 "Failed to register bundle identifier" | Bundle ID `com.tiebowen.Pole` 已被占用 | 改成 `com.tiebowen.Pole.dev`，3 个 target（主 + Tests + UITests）一起改 |
| Run 失败 "Untrusted Developer" 一直关不掉 | 14 Pro 没在"VPN 与设备管理"里信任 | Step 5.3 |
| Run 失败 "Could not launch ... operation couldn't be completed" | 14 Pro 锁屏 / 开发者模式没开 / 拔线了 | 解锁 + 检查开发者模式（Step 1.2） |
| App 启动闪退 / "ModelContainer 创建失败" | SwiftData schema 异常（极小概率，老版本残留） | 14 Pro 长按 Pole 图标 → 删除 → 重新 Run |
| AI tab 提示 "未配置 DeepSeek API Key" | `DS_API_KEY` 环境变量没生效 | Step 3.2 重设；clean build folder（Cmd+Shift+K）后再 Run |
| AI tab 报网络错误 | DeepSeek 服务问题或 key 失效 | 验 key：`curl https://api.deepseek.com/v1/models -H "Authorization: Bearer sk-..."` |
| 通知没弹 | 系统通知权限拒了 | 设置 → 通知 → Pole → 打开 |
| 赛事列表空 / 转圈 | 网络问题（jolpica / Pulselive / worldsbk 任一不通） | WiFi / 移动数据切换试；F1 / MotoGP / WSSP / FE 是不同数据源，部分挂不影响其他 |
| 7 天后 app 启不来 | 证书过期 | 重 Cmd+R 重签（上一节） |
| 模拟器 build 通过但真机 build 失败 "linker error" | 真机 SDK 缺失 / Xcode 不全 | Xcode → Settings → Platforms 装 iOS Device Support |

---

## 后续路径（如果想超越 Free Provisioning）

### 方案 B：付费开发者账号（$99/年）
- 加入 [Apple Developer Program](https://developer.apple.com/programs/)
- 证书 1 年（不用 7 天循环）
- 可以做 Ad-hoc 分发（最多 100 台 device，UDID 注册）
- 可以推 TestFlight 给最多 10000 个外部测试员

### 方案 C：TestFlight 内部测试
- 需要方案 B
- Archive → Distribute App → App Store Connect → TestFlight → Internal Testing
- 自己用 TestFlight app 装，证书 90 天

### 方案 D：App Store 公开发布
- 需要方案 B
- Archive → 上传 → 走完整 App Store 审核（一般 24-48 小时）
- 涉及隐私清单 / 应用元数据 / 截图 / 审核回复
- 如果走这条路，触发 axiom-shipping 完整流程：metadata、screenshots、age rating、export compliance、Privacy Manifest 等

---

## 1.0 标签

部署成功后，建议打 git tag 标记 1.0 起点：

```bash
git tag -a v1.0 -m "v1.0 - First device deploy on iPhone 14 Pro"
# 想推 GitHub 的话:
git push origin v1.0
```

---

## 检查清单（撕下版）

部署前 Mac 端：
- [ ] Xcode 26+ 装好
- [ ] Xcode 登 Apple ID
- [ ] 仓库同步到 Mac
- [ ] DeepSeek API Key 准备好

部署前 14 Pro 端：
- [ ] iOS 升 26+
- [ ] 开发者模式打开（设置 → 隐私与安全性）
- [ ] USB 连 Mac，"信任此电脑"

Xcode 配置：
- [ ] Pole target 选 Personal Team
- [ ] PoleTests / PoleUITests 也选 Team
- [ ] Bundle ID 没冲突（如冲突改 `.dev` 后缀）
- [ ] Run scheme 加 `DS_API_KEY` 环境变量

部署：
- [ ] destination 选 14 Pro 真机
- [ ] Cmd+R Build + Install
- [ ] 14 Pro 信任开发者（VPN 与设备管理）
- [ ] 再 Cmd+R 启动
- [ ] 通过 smoke test（5 个 tab 都能进 + AI 能回话）

部署后：
- [ ] `git tag v1.0`
- [ ] 记一下：7 天后要重 Cmd+R 重签
