import SwiftUI
import SwiftData
import PoleDomain
import PoleDesignSystem
import PoleAIKit

/// AI 生成的赛道亮点 section — **可折叠**。
/// 默认折叠显示"赛道亮点 ▾",点击展开第一次自动触发 LLM 生成,缓存后再展开直接显示。
/// 不同系列在同一赛道(F1 / MotoGP 都跑 Mugello)生成不同亮点,key 含 series。
public struct CircuitHighlightSection: View {
    public let series: MotorsportSeries
    public let circuitName: String
    public let country: String

    @Environment(\.modelContext) private var context
    @Query private var matches: [CircuitHighlight]

    @State private var isExpanded: Bool = false
    @State private var loading = false
    @State private var errorMessage: String?

    public init(series: MotorsportSeries, circuitName: String, country: String) {
        self.series = series
        self.circuitName = circuitName
        self.country = country
        let key = CircuitHighlight.makeKey(series: series, circuitName: circuitName)
        _matches = Query(filter: #Predicate<CircuitHighlight> { $0.key == key })
    }

    private var cached: CircuitHighlight? { matches.first }

    public var body: some View {
        Section {
            // 头部 row — 整行可点(展开/折叠)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                // 第一次展开且没缓存 → 自动触发生成(用户不用再点一次"看亮点")
                if isExpanded && cached == nil && !loading && errorMessage == nil {
                    Task { await generate() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .foregroundStyle(series.brandColor)
                        .frame(width: 28, alignment: .center)
                    Text(L10n.t(zh: "赛道亮点", en: "Circuit Highlight"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开的内容
            if isExpanded {
                if let entry = cached {
                    content(entry)
                } else if loading {
                    ProgressView().controlSize(.small)
                } else if let msg = errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(msg).font(.caption).foregroundStyle(.orange)
                        Button(L10n.t(zh: "重试", en: "Retry")) { Task { await generate() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        } footer: {
            if isExpanded, cached != nil {
                Text(L10n.t(zh: "由 AI 生成,仅供参考", en: "AI generated, for reference only"))
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func content(_ entry: CircuitHighlight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AIMarkdownText(text: entry.content, font: .subheadline)
            HStack {
                Spacer()
                Button {
                    Task { await regenerate() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.t(zh: "重新生成", en: "Regenerate"))
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func generate() async {
        loading = true
        errorMessage = nil
        do {
            let content = try await LLMClient.shared.generateCircuitHighlight(
                circuitName: circuitName, country: country, series: series
            )
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = L10n.t(zh: "AI 没返回内容,稍后再试", en: "AI returned empty; try later")
                loading = false
                return
            }
            let entry = CircuitHighlight(
                key: CircuitHighlight.makeKey(series: series, circuitName: circuitName),
                series: series.rawValue,
                circuitName: circuitName,
                content: trimmed
            )
            context.insert(entry)
            try? context.save()
        } catch {
            errorMessage = L10n.t(zh: "生成失败:\(error.localizedDescription)",
                                  en: "Generation failed: \(error.localizedDescription)")
        }
        loading = false
    }

    @MainActor
    private func regenerate() async {
        if let old = cached {
            context.delete(old)
            try? context.save()
        }
        await generate()
    }
}
