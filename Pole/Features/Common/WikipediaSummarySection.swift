import SwiftUI

/// 车手简介 section — 可折叠下拉框。
/// 默认折叠显示"车手简介 ▾",点击展开第一次自动触发 LLM 生成,缓存在 @State(detail 页生命周期)。
/// 失败/超时时显示具体错误 + 重试按钮。
struct WikipediaSummarySection: View {
    let queryTitle: String      // 车手名(英文/中文)
    let series: MotorsportSeries

    @State private var isExpanded: Bool = false
    @State private var bio: String?
    @State private var errorMsg: String?
    @State private var loaded = false
    @State private var loading = false

    var body: some View {
        Section {
            // 头部 row — 整行可点(展开/折叠)
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                // 第一次展开 + 没缓存 → 自动触发生成
                if isExpanded && bio == nil && !loaded && !loading && errorMsg == nil {
                    Task { await fetch() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(series.brandColor)
                    Text(L10n.t(zh: "车手简介", en: "Driver Bio"))
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

            // 展开内容
            if isExpanded {
                if let bio = bio {
                    aiContent(bio: bio)
                } else if loading {
                    ProgressView().controlSize(.small)
                } else if let msg = errorMsg {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle").font(.caption2)
                            Text(msg).font(.caption)
                        }
                        .foregroundStyle(.orange)
                        Button(L10n.t(zh: "重试", en: "Retry")) {
                            errorMsg = nil
                            loaded = false
                            Task { await fetch() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        } footer: {
            if isExpanded, bio != nil {
                Text(L10n.t(zh: "由 AI 生成,仅供参考",
                            en: "AI generated, for reference only"))
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func aiContent(bio: String) -> some View {
        Text(bio)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    @MainActor
    private func fetch() async {
        loading = true
        do {
            bio = try await LLMClient.shared.fetchRiderBio(name: queryTitle, series: series)
        } catch {
            errorMsg = error.localizedDescription
        }
        loaded = true
        loading = false
    }
}
