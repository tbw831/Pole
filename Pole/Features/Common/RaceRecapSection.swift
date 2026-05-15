import SwiftUI
import SwiftData
import PoleDomain

/// 赛事概览 section — 跟 CircuitHighlightSection 视觉一致（自定义头部 row + chevron + footer）。
///
/// 行为：
/// - 默认折叠
/// - 第一次展开且没缓存 → 自动触发 LLM generate（不需要单独"生成"按钮）
/// - 已缓存 → 展开直接看内容
/// - 生成失败 → 错误 + 重试
/// - 展开 + 有内容 → footer "由 AI 生成,仅供参考"
struct RaceRecapSection: View {
    let eventKey: String
    let series: MotorsportSeries
    let title: String
    let dataProvider: @Sendable () async throws -> String

    @Environment(\.modelContext) private var context
    @Query private var matches: [RaceRecap]

    @State private var isExpanded: Bool = false
    @State private var loading = false
    @State private var errorMessage: String?

    init(
        eventKey: String,
        series: MotorsportSeries,
        title: String,
        dataProvider: @escaping @Sendable () async throws -> String
    ) {
        self.eventKey = eventKey
        self.series = series
        self.title = title
        self.dataProvider = dataProvider
        _matches = Query(filter: #Predicate<RaceRecap> { $0.eventKey == eventKey })
    }

    private var cached: RaceRecap? { matches.first }

    var body: some View {
        Section {
            // 头部 row — 整行可点（展开/折叠），跟 CircuitHighlightSection 视觉一致
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                // 第一次展开且没缓存 → 自动触发生成
                if isExpanded && cached == nil && !loading && errorMessage == nil {
                    Task { await generate() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy")
                        .foregroundStyle(series.brandColor)
                        .frame(width: 28, alignment: .center)
                    Text(L10n.t(zh: "赛事概览", en: "Race Summary"))
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
                if let recap = cached {
                    content(recap)
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
    private func content(_ recap: RaceRecap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AIMarkdownText(text: recap.content, font: .subheadline)
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
            let dataJSON = try await dataProvider()
            let content = try await LLMClient.shared.generateRaceRecap(
                title: title, dataContextJSON: dataJSON
            )
            guard !content.isEmpty else {
                errorMessage = L10n.t(zh: "AI 没返回内容,稍后再试", en: "AI returned empty content; try again later")
                loading = false
                return
            }
            let recap = RaceRecap(
                eventKey: eventKey,
                series: series.rawValue,
                title: title,
                content: content
            )
            context.insert(recap)
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
