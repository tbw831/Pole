# RAG 知识库

Pole AI 助手的本地领域知识来源。启动时由 `KnowledgeImporter` 扫描本目录所有 `*.md`，
按一级标题切 chunk，用 `EmbeddingService`(NLContextualEmbedding) embed 后存入 SwiftData。
LLM 通过 `retrieve_knowledge` tool 做语义检索，top-K 回答用户。

## ⚠️ Xcode 集成必读(Mac 端一次性)

**这个文件夹必须以 Folder Reference 加入 Xcode**(蓝色文件夹图标)而不是 Group(黄色)。

**步骤**:
1. Mac 端 Xcode 打开 Pole.xcodeproj
2. project navigator 里 right-click `Pole/Resources` → "Add Files to Pole..."
3. 选 `Knowledge` 整个文件夹
4. **关键**:勾选 "Create folder references"(蓝色文件夹),不勾 "Create groups"
5. 勾选 Pole target,Add

如果勾错了 Group,扫的时候 `Bundle.main.urls(forResourcesWithExtension:subdirectory:)`
返 nil,RAG 直接失效。

## 目录结构与文件命名

```
Knowledge/
  F1/{f1-rules.md, f1-circuits.md}            ← series=f1
  MotoGP/{motogp-rules.md, motogp-circuits.md} ← series=motogp
  WSBK/{wsbk-rules.md, wsbk-circuits.md}      ← series=wsbk
  FE/{fe-rules.md, fe-circuits.md}            ← series=fe
  General/general-strategy.md                  ← series=nil(跨系列)
  README.md                                    ← 本文件,不入库(没有 frontmatter)
```

**文件名必须带 series 前缀**(`f1-` / `motogp-` / `wsbk-` / `fe-` / `general-`)。
为什么:Xcode "Group" 模式(常用)会把所有 .md 平铺到 bundle root,**同名文件冲突报
"Multiple commands produce"**。前缀保证文件名全 bundle 唯一。

`KnowledgeImporter` 推断 series 优先级:
1. 文件名前缀(可靠,Group 模式必走)
2. 路径目录名(Folder Reference 模式 fallback)
3. frontmatter `series:` 字段(显式覆盖)

## Markdown 格式约定

```markdown
---
series: f1            ← 可选,空表示跨系列;路径有 F1/MotoGP/WSBK/FE 时自动推断
topic: rules          ← 可选,默认从文件名推断(rules.md → rules)
---

# 章节标题 1

这一段是一个 chunk,会被整段 embed,LLM 检索时一次返这整段。
chunk 长度建议 100-400 字之间,过短信息密度低,过长 embedding 摊平细节。

# 章节标题 2

下一段。`# ` 一级标题分隔,`## ` 二级标题不切。
chunk 内可以正常用 markdown 语法 — bold, list 等,LLM 看到原 markdown 也能理解。
```

## 扩展知识库

### 加新章节
直接在已有 `.md` 文件加新的 `# 标题`,启动后自动重导(只在库里 0 chunk 时跑,
**首次有内容后不重扫** — 想强制重导走 `KnowledgeImporter.importIfNeeded(force: true)`)。

### 加新文件
按"系列前缀-主题"格式命名 .md 文件:
- 比如要加 F1 车手百科:`Knowledge/F1/f1-drivers.md`(topic 自动推为 "drivers")
- 跨系列内容:`Knowledge/General/general-{主题}.md`
**前缀不可省**,Group 模式 build 会同名冲突。

### 强制重新导入
开发期改了内容,需要清库重导,临时改 `PoleApp.swift`:
```swift
await KnowledgeImporter.importIfNeeded(
    context: ...,
    force: true   // ← 加这个
)
```
跑一次后改回去。

## 写好 chunk 的几条建议

1. **每 chunk 自包含**:LLM 只看到 chunk 内容,前后 chunk 不可见,所以 chunk 内别用
   "前文提到""上一节"等代词。

2. **关键词丰富**:中文 + 英文混排,各种叫法都写一遍 — "Marc Marquez / 马奎斯 / 马克"。
   embed 找语义相近,不找字面命中,但提关键词能提高召回。

3. **避免太长**:超过 600 字的 chunk 信息密度被稀释。如果一个话题写很长,
   拆成多个 `# 标题`(各自单独 chunk)比挤一段强。

4. **别写实时数据**:积分、赛果、当前赛季排名等用 tool 查,不要塞 markdown(每年要改)。
   写"规则、历史、特点、策略"这些**不变的领域知识**。

## Debug

把对话里 LLM 调用 retrieve_knowledge 后返的 hits 看一遍,score 通常在 0.3-0.85 之间:
- score > 0.6 = 强相关,LLM 应该 heavily rely on
- 0.4 < score < 0.6 = 一般相关,LLM 参考即可
- score < 0.4 = 弱相关,可能 query 跟 chunk 不匹配,需要补 chunk 或调 query

如果用户问题语言切了(中→英)但只有中文 chunk,score 会偏低 — 考虑写双语 chunk。
