import Foundation
import SwiftData
import NaturalLanguage
import PoleDomain

/// 启动时把 `Resources/Knowledge/**/*.md` 切 chunk → embed → 写入 SwiftData。
///
/// **触发时机**:PoleApp 启动后异步调一次(放 .task / Task 里跑,不阻塞 UI)。
/// **去重**:用 source 字段+chunk hash 检测,已导入过的 markdown 不重复 embed。
/// **首次启动慢**:300 chunk × ~50ms embed = 15s,在 background Task 跑,UI 该干嘛干嘛。
/// **markdown 格式约定**:
/// ```
/// ---
/// series: f1            ← optional,空表示跨系列
/// topic: rules
/// ---
/// # 章节标题1
///
/// 内容...
///
/// # 章节标题2
///
/// 内容...
/// ```
/// **chunk 切分**:按一级标题 `# ` 切 — 每个 # 块就是一个 chunk。
/// 想拆得更细的话, content 里再按段落空行二次切(可选)。
@MainActor
public enum KnowledgeImporter {
    /// 入口 — 检查是否已导入,没导入就扫 Bundle 全量灌库。
    /// `force=true` 时清库重导(开发期 / 知识库内容更新后用)。
    /// `bundle` 默认 `.main`(主 app bundle 持有 Resources/Knowledge/*.md)。Package 化后必须显式
    /// 传入主 app bundle,因为 PoleAIKit 自己的 module bundle 里没有这些 md。
    public static func importIfNeeded(context: ModelContext, bundle: Bundle = .main, force: Bool = false) async {
        if force {
            // 清库重导:fetch all + delete all
            let descriptor = FetchDescriptor<KnowledgeChunk>()
            if let existing = try? context.fetch(descriptor) {
                for c in existing { context.delete(c) }
                try? context.save()
            }
        } else {
            // 已经有 chunk = 跳过(简单去重,不做内容 hash 比对)
            let descriptor = FetchDescriptor<KnowledgeChunk>()
            if let count = try? context.fetchCount(descriptor), count > 0 {
                return
            }
        }

        // 扫 Bundle 内 Resources/Knowledge 目录
        guard let urls = bundleMarkdownFiles(bundle: bundle) else {
            print("[KnowledgeImporter] no markdown files found in Bundle Resources/Knowledge")
            return
        }
        var totalChunks = 0
        for url in urls {
            let count = await importFile(url, context: context)
            totalChunks += count
        }
        print("[KnowledgeImporter] imported \(totalChunks) chunks from \(urls.count) files")
    }

    // MARK: - 内部:扫 Bundle

    /// 找出 Bundle 里 Knowledge/ 目录下所有 .md 文件 URL(递归)。
    ///
    /// Xcode 把 Resources/Knowledge 整个文件夹引用的方式决定如何 lookup:
    /// - **Folder Reference**(蓝色文件夹,推荐) → 子目录保留,FileManager 递归能拿全
    /// - **Group**(黄色文件夹) → 文件全平铺到 Bundle root,且**不能有同名文件**(否则 build 报
    ///   "Multiple commands produce" 冲突)。这种模式下 Knowledge 子目录消失。
    ///
    /// 三段 fallback:
    /// 1. FileManager 递归扫 Bundle.bundleURL/Knowledge(Folder Reference 模式)
    /// 2. Bundle.urls(subdirectory:) 顶层(部分 Folder Reference 子集场景)
    /// 3. 平铺扫所有 .md,文件名以已知 series prefix 开头才认(Group 模式 fallback,
    ///    要求文件名形如 `f1-rules.md` / `motogp-circuits.md` 等)
    private static func bundleMarkdownFiles(bundle: Bundle) -> [URL]? {
        // 路径 1: FileManager 递归(Folder Reference 模式最可靠)
        let knowledgeURL = bundle.bundleURL.appendingPathComponent("Knowledge")
        if FileManager.default.fileExists(atPath: knowledgeURL.path) {
            var urls: [URL] = []
            if let enumerator = FileManager.default.enumerator(
                at: knowledgeURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    if url.pathExtension.lowercased() == "md" {
                        // 跳过 README — 没有 frontmatter,不该入库
                        if url.lastPathComponent.lowercased() == "readme.md" { continue }
                        urls.append(url)
                    }
                }
            }
            if !urls.isEmpty { return urls }
        }

        // 路径 2: subdirectory API(部分场景顶层有 .md)
        if let urls = bundle.urls(forResourcesWithExtension: "md", subdirectory: "Knowledge") {
            let filtered = urls.filter { $0.lastPathComponent.lowercased() != "readme.md" }
            if !filtered.isEmpty { return filtered }
        }

        // 路径 3: 平铺(Group 模式 fallback)— 文件名前缀决定 series
        if let urls = bundle.urls(forResourcesWithExtension: "md", subdirectory: nil) {
            let knownPrefixes = ["f1-", "motogp-", "wsbk-", "fe-", "general-"]
            let filtered = urls.filter { url in
                let name = url.lastPathComponent.lowercased()
                if name == "readme.md" { return false }
                return knownPrefixes.contains(where: { name.hasPrefix($0) })
            }
            if !filtered.isEmpty { return filtered }
        }
        return nil
    }

    // MARK: - 内部:解析单文件

    /// 解析一个 markdown 文件 → 多个 chunk。返导入条数。
    private static func importFile(_ url: URL, context: ModelContext) async -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }

        // 1. 解析 frontmatter — 提取 series / topic 元数据
        let (frontmatter, body) = parseFrontmatter(content)
        let series = frontmatter["series"]
        let topic = frontmatter["topic"]

        // 2. 切 chunk — 按一级标题 # 切,每段 = 一个 chunk
        let chunks = splitByH1(body: body)

        // 3. 路径推断 series — 没 frontmatter 时按 Knowledge/F1/rules.md → series=f1 推
        let inferredSeries = series ?? inferSeriesFromPath(url)
        let inferredTopic = topic ?? inferTopicFromPath(url)
        let sourceLabel = url.deletingPathExtension().lastPathComponent

        // 4. 每个 chunk embed + 写入
        var imported = 0
        for (heading, text) in chunks {
            let fullText = heading.isEmpty ? text : "# \(heading)\n\n\(text)"
            // 中文为主的 chunk 用 zh 模型;含大量 ASCII 时也用 zh,因为 NLContextualEmbedding zh
            // 模型对 mixed-script 容忍度还可以
            guard let vector = try? await EmbeddingService.shared.embed(
                fullText,
                language: .simplifiedChinese
            ) else { continue }
            let data = KnowledgeChunk.encodeVector(vector)
            let chunk = KnowledgeChunk(
                text: fullText,
                source: "\(sourceLabel)#\(slugify(heading))",
                seriesRaw: inferredSeries,
                topic: inferredTopic,
                vectorData: data
            )
            context.insert(chunk)
            imported += 1
        }
        try? context.save()
        return imported
    }

    // MARK: - 内部:frontmatter / 切分 / slug

    /// 解析 YAML-style frontmatter(简单 key: value 对,不支持嵌套 / 数组)。
    /// 返 (metadata, body 不含 frontmatter)。
    private static func parseFrontmatter(_ content: String) -> ([String: String], String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return ([:], content) }
        let afterFirstFence = String(trimmed.dropFirst("---".count))
        guard let endRange = afterFirstFence.range(of: "\n---") else { return ([:], content) }
        let frontmatterText = String(afterFirstFence[afterFirstFence.startIndex..<endRange.lowerBound])
        let body = String(afterFirstFence[endRange.upperBound...])

        var meta: [String: String] = [:]
        for line in frontmatterText.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                meta[parts[0]] = parts[1]
            }
        }
        return (meta, body)
    }

    /// 按一级标题 `# ` 切 chunk,返 [(heading, text)]。
    /// 没有任何 # 的话整个 body 当成一个 chunk(heading 空字符串)。
    private static func splitByH1(body: String) -> [(String, String)] {
        var chunks: [(String, String)] = []
        var currentHeading = ""
        var currentBuffer: [String] = []

        func flush() {
            let text = currentBuffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty || !currentHeading.isEmpty {
                chunks.append((currentHeading, text))
            }
        }

        for line in body.components(separatedBy: "\n") {
            // 严格匹配 `# ` 开头(避免吃到 `## `):用前缀检查 + 后跟空格判断
            if line.hasPrefix("# ") {
                flush()
                currentHeading = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                currentBuffer = []
            } else {
                currentBuffer.append(line)
            }
        }
        flush()
        return chunks
    }

    /// 从路径推 series。优先级:
    /// 1. 文件名前缀(`f1-rules.md` → "f1")— Group 模式平铺时唯一可靠的推断
    /// 2. 路径目录名(`Knowledge/F1/...` → "f1")— Folder Reference 模式 fallback
    /// 路径含 General / 文件名以 general- 开头 → nil(跨系列通用知识)。
    private static func inferSeriesFromPath(_ url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        // 1. 文件名前缀
        if stem.hasPrefix("f1-")      { return "f1" }
        if stem.hasPrefix("motogp-")  { return "motogp" }
        if stem.hasPrefix("wsbk-")    { return "wsbk" }
        if stem.hasPrefix("fe-")      { return "fe" }
        if stem.hasPrefix("general-") { return nil }
        // 2. 路径目录名 fallback
        let comps = url.pathComponents.map { $0.lowercased() }
        for c in comps {
            switch c {
            case "f1":      return "f1"
            case "motogp":  return "motogp"
            case "wsbk":    return "wsbk"
            case "fe":      return "fe"
            default: continue
            }
        }
        return nil
    }

    /// 从路径推 topic — 文件名 stem 去掉 series 前缀。
    /// "f1-rules.md" → "rules", "motogp-circuits.md" → "circuits"。
    private static func inferTopicFromPath(_ url: URL) -> String? {
        var stem = url.deletingPathExtension().lastPathComponent.lowercased()
        for prefix in ["f1-", "motogp-", "wsbk-", "fe-", "general-"] {
            if stem.hasPrefix(prefix) {
                stem = String(stem.dropFirst(prefix.count))
                break
            }
        }
        return stem.isEmpty ? nil : stem
    }

    /// 把 heading 转成 url-safe slug 用作 source 锚点("DRS 规则" → "drs-规则")。
    private static func slugify(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.urlPathAllowed.inverted)
            .joined()
    }
}
