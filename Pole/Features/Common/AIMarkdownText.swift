import SwiftUI

/// AI 生成内容的轻量 markdown 渲染 — 段落分隔（空行）+ 行内 `**bold**`。
///
/// 用于 RaceRecap / CircuitHighlight 等显示 LLM markdown 文本的场景。
///
/// **不用 `AttributedString(markdown:)`**：实测在中英混排 + 多个 **bold**
/// 同段落的场景下偶发 parse 失败 fallback 到 plain text（用户看到字面 `**xxx**`），
/// 改用 O(n) 正则扫描 100% 可控，跟 ChatView.streamingBoldAttributed 一致。
///
/// 仅支持 `**bold**`，不处理 `*italic*` / `` `code` `` / 列表 / 表格。
/// 如 LLM 输出这些，会作为字面字符显示（已在 LLM prompt 里禁止）。
struct AIMarkdownText: View {
    let text: String
    var font: Font = .subheadline

    var body: some View {
        let paragraphs = Self.parseParagraphs(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p)
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 共享 bold 正则,避免每次渲染重建。NSRegularExpression 线程安全。
    private static let boldRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)

    /// O(n) 正则扫描:`**xxx**` 渲染为加粗(`inlinePresentationIntent: .stronglyEmphasized`),
    /// 让 SwiftUI 在容器 `.font(...)` 基础上自动叠加 bold weight,不破坏字号。
    private static func boldAttributed(_ s: String) -> AttributedString {
        guard let regex = boldRegex else { return AttributedString(s) }
        var result = AttributedString()
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        let matches = regex.matches(in: s, options: [], range: nsRange)

        var lastEnd = s.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: s),
                  let innerRange = Range(match.range(at: 1), in: s) else { continue }
            // 加粗段之前的普通文本
            if lastEnd < fullRange.lowerBound {
                result += AttributedString(String(s[lastEnd..<fullRange.lowerBound]))
            }
            // **xxx** 内部的加粗文本
            var bolded = AttributedString(String(s[innerRange]))
            bolded.inlinePresentationIntent = .stronglyEmphasized
            result += bolded
            lastEnd = fullRange.upperBound
        }
        // 末尾剩余普通文本
        if lastEnd < s.endIndex {
            result += AttributedString(String(s[lastEnd..<s.endIndex]))
        }
        return result
    }

    /// 把 raw 按 `\n\n` 切段落,每段过 boldAttributed 渲染。
    /// 容错:LLM 偶发 `** xx **` 边界空格 → 规整成 `**xx**`。
    private static func parseParagraphs(_ raw: String) -> [AttributedString] {
        raw.components(separatedBy: "\n\n")
            .compactMap { block -> AttributedString? in
                let s = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { return nil }
                let cleaned = s
                    .replacingOccurrences(of: "** ", with: "**")
                    .replacingOccurrences(of: " **", with: "**")
                return boldAttributed(cleaned)
            }
    }
}
