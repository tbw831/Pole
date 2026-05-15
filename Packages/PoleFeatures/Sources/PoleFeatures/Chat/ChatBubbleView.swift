import SwiftUI
import PoleDesignSystem
import PoleDomain

// MARK: - 单条消息气泡(用户右侧紫渐变 / AI 左侧白底卡片)
//
// 由 ChatView.renderItem 直接调用 — `.toolStep` case 在外层 RenderItem 折叠时已经
// 走 ChatToolCallView 渲染,这里只处理 user / assistant 两种气泡。

public struct BubbleView: View {
    let bubble: ChatViewModel.Bubble
    let isStreaming: Bool
    let onCopy: () -> Void
    let onRegenerate: () -> Void

    @State private var copied = false

    public var body: some View {
        switch bubble {
        case .user(_, let text):
            userBubble(text: text)
        case .assistant(_, let text):
            assistantBubble(text: text)
        case .toolStep:
            // Dead branch — ChatView.RenderItem 已经把所有连续 .toolStep 折叠成
            // ToolGroupView 渲染,单条 toolStep 永远不会进 BubbleView。
            // 显式 EmptyView 让以后误用也只是空白而非异常。
            EmptyView()
        }
    }

    // MARK: 用户气泡(右侧,紫渐变,首尾不对称圆角)

    private func userBubble(text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(DS.Font.bubble)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md - 2)
                .background(DS.Palette.aiGradient,
                            in: UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: DS.Radius.bubble,
                                    bottomLeading: DS.Radius.bubble,
                                    bottomTrailing: DS.Radius.sm,
                                    topTrailing: DS.Radius.bubble
                                )
                            ))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: { Label(L10n.t(zh: "复制", en: "Copy"), systemImage: "doc.on.doc") }
                }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: AI 气泡(左侧带头像,白底卡片,可流式光标 + 操作行)

    private func assistantBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            AIAvatar(size: .small)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                // 文本气泡 + 流式光标。
                // isStreaming 时 AssistantMarkdownText 走纯 Text 快路径,
                // 避免每个 chunk 都做 AttributedString markdown parse(主线程帧预算大头)。
                VStack(alignment: .leading, spacing: 0) {
                    AssistantMarkdownText(text: text, isStreaming: isStreaming)
                    if isStreaming {
                        HStack(spacing: 0) {
                            StreamingCursor()
                        }
                    }
                }
                .font(DS.Font.bubble)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md - 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: DS.Radius.sm,
                        bottomLeading: DS.Radius.bubble,
                        bottomTrailing: DS.Radius.bubble,
                        topTrailing: DS.Radius.bubble
                    )
                ))
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: DS.Radius.sm,
                            bottomLeading: DS.Radius.bubble,
                            bottomTrailing: DS.Radius.bubble,
                            topTrailing: DS.Radius.bubble
                        )
                    )
                    .fill(DS.Palette.aiBubbleFill)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: DS.Radius.sm,
                            bottomLeading: DS.Radius.bubble,
                            bottomTrailing: DS.Radius.bubble,
                            topTrailing: DS.Radius.bubble
                        )
                    )
                    .strokeBorder(DS.Palette.aiBubbleStroke, lineWidth: 0.5)
                )
                .shadow(color: DS.Shadow.bubble.color,
                        radius: DS.Shadow.bubble.radius,
                        x: DS.Shadow.bubble.x, y: DS.Shadow.bubble.y)
                .contextMenu {
                    Button {
                        onCopy()
                        showCopiedToast()
                    } label: { Label(L10n.t(zh: "复制", en: "Copy"), systemImage: "doc.on.doc") }
                    Button {
                        onRegenerate()
                    } label: { Label(L10n.t(zh: "重新生成", en: "Regenerate"), systemImage: "arrow.triangle.2.circlepath") }
                }
            }
            Spacer(minLength: 48)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func showCopiedToast() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    // 注: 单条 .toolStep 渲染逻辑已删除 — ChatView.RenderItem 把连续 .toolStep
    // 折叠成 ToolGroupView,BubbleView 永远拿不到 .toolStep case。
}

// MARK: - Assistant 文本(轻量 markdown 渲染)

/// 把 LLM 的回答按"空行=段落、单换行=同段落内独立行"切开,每行用 inline markdown 解析。
/// 这样 `**xxx**` 加粗、`*xxx*` 斜体、`` `xxx` `` 代码都生效,不需要完整 markdown parser。
/// 段落间间距大、段落内行间距小,视觉上比一坨 Text 整齐。
///
/// 性能: AttributedString markdown 解析是 ms 级 expensive,流式期间每 chunk 重新 parse
/// 全文会主线程吃帧时间预算。`isStreaming=true` 时走纯 Text 快路径(段落分行不解析 inline
/// markdown),流式结束后再切回完整 parse,视觉上一瞬间补回 **加粗** 等格式。
public struct AssistantMarkdownText: View {
    let text: String
    var isStreaming: Bool = false

    public var body: some View {
        if isStreaming {
            streamingFastPath
        } else {
            let blocks = parse(text)
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(blocks.indices, id: \.self) { i in
                    blockView(blocks[i])
                }
            }
        }
    }

    /// 流式快路径——按空行切段落,段落内单换行切行,
    /// 用 streamingBoldAttributed 处理 **xxx** 加粗（不做完整 markdown parse 避免每 chunk 卡帧）。
    private var streamingFastPath: some View {
        let paragraphs = text.components(separatedBy: "\n\n")
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(paragraphs.indices, id: \.self) { pi in
                let lines = paragraphs[pi]
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines.indices, id: \.self) { li in
                        Text(Self.streamingBoldAttributed(lines[li]))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// 共享 bold 正则,避免每个 chunk 重建。NSRegularExpression 线程安全。
    private static let boldRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)

    /// O(n) 正则扫描:`**xxx**` 渲染为加粗,其他 markdown 标记保留字面字符。
    /// 流式期间用,避免每个 chunk 重新跑完整 AttributedString markdown parse 卡帧。
    /// 跨 chunk 半成品 `**xx`(未闭合)：当普通文本，等下一 chunk 闭合 `**` 到达后下次重渲染才加粗。
    private static func streamingBoldAttributed(_ s: String) -> AttributedString {
        var result = AttributedString()
        guard let regex = Self.boldRegex else {
            return AttributedString(s)
        }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = regex.matches(in: s, options: [], range: nsRange)

        var lastEnd = s.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: s),
                  let innerRange = Range(match.range(at: 1), in: s) else { continue }
            result += AttributedString(String(s[lastEnd..<fullRange.lowerBound]))
            var bolded = AttributedString(String(s[innerRange]))
            bolded.font = .body.bold()
            result += bolded
            lastEnd = fullRange.upperBound
        }
        result += AttributedString(String(s[lastEnd..<s.endIndex]))
        return result
    }

    /// LLM 回答里可能出现的"块"类型。
    private enum Block: Hashable {
        case paragraph(lines: [AttributedString])
        case codeBlock(language: String?, code: String)
        /// 表格 — `rows[0]` 是 header,后续是数据行。
        case table(rows: [[String]])
    }

    /// 行级扫描:识别 ``` 代码块 / | 表格 / 普通段落,跨段落都用空行分隔。
    private func parse(_ raw: String) -> [Block] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // ----- 代码块 -----
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count, !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                // 跳过闭合 ```
                if i < lines.count, lines[i].hasPrefix("```") { i += 1 }
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }
            // ----- 段落 / 表格(收集到下一个空行或 ```) -----
            var paraLines: [String] = []
            while i < lines.count,
                  !lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
                  !lines[i].hasPrefix("```") {
                paraLines.append(lines[i])
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(makeBlock(from: paraLines))
            }
            // 跳过连续空行
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
            }
        }
        return blocks
    }

    /// 几行连续文本 → 表格 / 段落。表格判定:连续 ≥2 行都含 `|` 且不全是分隔行。
    private func makeBlock(from paraLines: [String]) -> Block {
        if paraLines.count >= 2, paraLines.allSatisfy({ $0.contains("|") }) {
            let rows = paraLines.compactMap { row -> [String]? in
                let cells = row
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !cells.isEmpty else { return nil }
                // 跳过分隔行 |---|---|
                if cells.allSatisfy({ $0.allSatisfy { c in c == "-" || c == ":" || c.isWhitespace } }) {
                    return nil
                }
                return cells
            }
            if rows.count >= 2 {
                return .table(rows: rows)
            }
        }
        let attrs = paraLines.map { line -> AttributedString in
            // 容错:LLM 偶发输出 ** xx **(边界空格)→ 规整成 **xx**
            let cleaned = line
                .replacingOccurrences(of: "** ", with: "**")
                .replacingOccurrences(of: " **", with: "**")
            if let attr = try? AttributedString(
                markdown: cleaned,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) { return attr }
            return AttributedString(line)
        }
        return .paragraph(lines: attrs)
    }

    @ViewBuilder
    private func blockView(_ b: Block) -> some View {
        switch b {
        case .paragraph(let lines):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines.indices, id: \.self) { i in
                    Text(lines[i])
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .codeBlock(let lang, let code):
            CodeBlockView(language: lang, code: code)
        case .table(let rows):
            TableBlockView(rows: rows)
        }
    }
}

// MARK: - 代码块组件(暗底 monospace + 复制按钮)

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部条:语言 + 复制按钮
            HStack(spacing: DS.Spacing.sm) {
                Text(language?.uppercased() ?? L10n.t(zh: "代码", en: "CODE"))
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                        Text(copied
                             ? L10n.t(zh: "已复制", en: "Copied")
                             : L10n.t(zh: "复制", en: "Copy"))
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(Color.black.opacity(0.55))

            // 代码区(横滚防长行)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.md)
                    .frame(minWidth: 0, alignment: .leading)
            }
            .background(Color.black.opacity(0.78))
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}

// MARK: - 表格降级组件
//
// 窄屏 iPhone 上 markdown 表格 (`| col | col |`) 渲染成多列必然错乱。
// 降级策略:每数据行渲染成一张"卡片",卡片内每个 cell 一行 "header → value",
// 横滚也不需要,直接顺序读完。

private struct TableBlockView: View {
    /// rows[0] 是 header,后续是数据行。
    let rows: [[String]]

    public var body: some View {
        let header = rows.first ?? []
        let dataRows = rows.dropFirst()

        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(Array(dataRows.enumerated()), id: \.offset) { _, row in
                tableCard(header: header, row: row)
            }
        }
    }

    private func tableCard(header: [String], row: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<row.count, id: \.self) { i in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    Text(i < header.count ? header[i] : "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 60, alignment: .leading)
                    Text(row[i])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.primaryFaint, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Palette.primary.opacity(0.20), lineWidth: 0.5)
        )
    }
}
