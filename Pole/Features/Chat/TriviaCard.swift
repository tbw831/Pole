import SwiftUI
import SwiftData
import PoleDesignSystem
import PoleDomain
import PoleAIKit

/// 首屏"今日冷知识"卡片——AI 每天生成一条,缓存到 SwiftData。
/// 同一天再开 app 不重复调 API。失败/没数据则不显示卡片(自然降级)。
struct TriviaCard: View {
    let modelContext: ModelContext

    @State private var trivia: String?
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        Group {
            if let trivia = trivia {
                content(trivia)
            } else if loading {
                placeholder
            }
            // 加载完毕但没拿到 → return EmptyView,卡片消失
        }
        .task { await loadIfNeeded() }
    }

    @ViewBuilder
    private func content(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "flag.checkered.2.crossed")
                .font(.callout)
                .foregroundStyle(DS.Palette.racingRed)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(zh: "📋 PIT NOTE · 冷知识", en: "📋 PIT NOTE · Trivia"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .dsHeroBanner()
    }

    private var placeholder: some View {
        ProgressView()
            .controlSize(.mini)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsHeroBanner()
    }

    @MainActor
    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true

        let dayKey = DailyTrivia.todayKey()
        let descriptor = FetchDescriptor<DailyTrivia>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        if let cached = try? modelContext.fetch(descriptor).first {
            trivia = cached.content
            return
        }

        loading = true
        if let new = try? await LLMClient.shared.generateDailyTrivia(), !new.isEmpty {
            let item = DailyTrivia(dayKey: dayKey, content: new)
            modelContext.insert(item)
            try? modelContext.save()
            trivia = new
        }
        loading = false
    }
}
