import SwiftUI
import PoleDomain
import PoleDesignSystem
import PoleAIKit

/// 车手赛季表现 AI 总结 — 折叠 section,视觉跟 RaceRecapSection / CircuitHighlightSection
/// 一致(自定义 Button 头 + chevron + footer)。
///
/// 内存缓存(@State)而非 SwiftData @Model:每次进 page 重新生成,避免持久化车手 ×
/// 赛季 × 时间组合膨胀;LLM 调用本身有 chat 缓存层。
///
/// 行为:
/// - 默认折叠
/// - 第一次展开且没缓存 → 自动触发 LLM generate(不需要单独"生成"按钮)
/// - 已缓存 → 直接展开看内容
/// - 生成失败 → 错误 + 重试
/// - 展开 + 有内容 → footer "由 AI 生成,仅供参考"
public struct DriverSeasonReviewSection: View {
    public let driverName: String
    public let series: MotorsportSeries
    public let dataProvider: @Sendable () async throws -> String

    @State private var content: String?
    @State private var isExpanded: Bool = false
    @State private var loading = false
    @State private var errorMessage: String?

    public init(
        driverName: String,
        series: MotorsportSeries,
        dataProvider: @escaping @Sendable () async throws -> String
    ) {
        self.driverName = driverName
        self.series = series
        self.dataProvider = dataProvider
    }

    public var body: some View {
        Section {
            // 头部 row — 整行可点(展开/折叠),跟 RaceRecap / CircuitHighlight 一致
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                // 第一次展开且没缓存 → 自动触发生成
                if isExpanded && content == nil && !loading && errorMessage == nil {
                    Task { await generate() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(series.brandColor)
                    Text(L10n.t(zh: "赛季表现总结", en: "Season Review"))
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
                if let c = content {
                    contentView(c)
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
            if isExpanded, content != nil {
                Text(L10n.t(zh: "由 AI 生成,仅供参考", en: "AI generated, for reference only"))
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func contentView(_ c: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AIMarkdownText(text: c, font: .subheadline)
            HStack {
                Spacer()
                Button {
                    Task {
                        content = nil
                        await generate()
                    }
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
            let result = try await LLMClient.shared.generateDriverSeasonReview(
                driverName: driverName, series: series, dataContextJSON: dataJSON
            )
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = L10n.t(zh: "AI 没返回内容,稍后再试", en: "AI returned empty; try later")
                loading = false
                return
            }
            content = trimmed
        } catch {
            errorMessage = L10n.t(zh: "生成失败:\(error.localizedDescription)",
                                  en: "Generation failed: \(error.localizedDescription)")
        }
        loading = false
    }
}
