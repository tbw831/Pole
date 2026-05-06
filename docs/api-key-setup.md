# API Key 本地配置

`LLMClient` 调用 DeepSeek API 需要 `DS_API_KEY`,**绝不能 commit 进仓库**。
本地开发选下面任一种路径配置即可。

## 路径一:Xcode Scheme 环境变量(推荐,最简单)

只在 Mac 端 Xcode 操作,无需碰任何文件:

1. Xcode 打开 `Pole.xcodeproj`
2. 顶部 scheme picker 旁的下拉 → **Edit Scheme...**
3. 左侧选 **Run** → 顶部选 **Arguments** tab
4. 在 **Environment Variables** 区点 `+`
5. Name: `DS_API_KEY`, Value: `sk-...`(你的 DeepSeek key)
6. 关闭 → **Close**(不要勾 "Shared",这样修改只存在 user-specific scheme,
   `xcuserdata/` 已 gitignore,不会 commit 出去)

完成后跑 app 即可。clean build 也保留。

> **验证**:Cmd+R 跑 app → 切到"Pole" tab → 发条消息。如果回复正常 = 成功。
> 如果弹"未配置 DeepSeek API Key" = env var 没生效,检查是否填错或大小写。

## 路径二:Info.plist + xcconfig(发布构建用)

适合做 archive / TestFlight / Release 构建,不依赖 scheme env var。

1. 在 `Pole/` 下创建 `Secrets.xcconfig.local`(已被 `.gitignore` 忽略),内容:
   ```
   DS_API_KEY = sk-你的key
   ```
2. Xcode → Project → Pole target → Build Settings → 顶部 + → Add User-Defined Setting
   - 名:`DS_API_KEY`
   - 值:`$(DS_API_KEY)`(从 xcconfig 引)
3. Xcode → Project 顶层 → Info → Configurations → 给 Debug/Release 都
   set Configuration File 指向 `Secrets.xcconfig.local`
4. `Pole/Info.plist` 加一条:
   ```
   <key>DSAPIKey</key>
   <string>$(DS_API_KEY)</string>
   ```
5. Build → key 被 build settings 注入到 Info.plist。

> 这条路径 key 会进 binary(Info.plist 是明文),只用于个人 build / 信任环境。
> Production 必须改走自有代理服务,key 留在服务端。

## 不要做的事

- ❌ 在 `LLMClient.swift` 里硬编码 `"sk-..."` — 会 commit 进库
- ❌ 在 `Info.plist` 直接写 key 而不通过 xcconfig 注入 — 会 commit 进库
- ❌ 在 shared scheme 里配 env var(勾了 "Shared")— `xcshareddata/xcschemes/*.xcscheme`
  会进 git,key 一样泄露
- ❌ 把 key 截图发到任何聊天 — 即使删了截图,服务端可能已 cache

## key 泄露应急

如果不小心 commit / 推送了 key:

1. 立刻去 [DeepSeek Platform](https://platform.deepseek.com) 撤销该 key
2. 生成新 key 走上面的路径配置
3. 仓库历史中的旧 key 用 `git filter-repo` 或 BFG 清理(被推到 GitHub 后清不干净 — GitHub
   有缓存,只能换 key)
