import SwiftUI

@MainActor
@Observable
final class TeamDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(items: [NewsItem])
        case failed(message: String)
    }

    let teamName: String
    let series: MotorsportSeries
    private(set) var state: State = .idle

    init(teamName: String, series: MotorsportSeries) {
        self.teamName = teamName
        self.series = series
    }

    func load() async {
        state = .loading
        let kw = TeamNewsKeywords.keywords(for: teamName)
        // ZXMOTO 走"通用 RSS keyword 过滤" + "中文官网 JSON" 双源合并
        async let rss = TeamNewsAggregator.shared.fetchTeamNews(series: series, keywords: kw)
        async let zx: [NewsItem] = isZXMOTO ? ((try? await ZXMOTOClient.shared.fetchNews()) ?? []) : []
        let (rssItems, zxItems) = await (rss, zx)
        // 中文官方源排前(实时性高且是张雪本人的内容);RSS 跟在后面
        let merged = zxItems + rssItems
        // URL 去重
        var seen: Set<String> = []
        let unique = merged.filter { seen.insert($0.id).inserted }
        state = .loaded(items: unique)
    }

    private var isZXMOTO: Bool {
        teamName.uppercased() == "ZXMOTO"
    }
}

struct TeamDetailView: View {
    @State private var viewModel: TeamDetailViewModel
    @State private var sheet: IdentifiableURL?

    init(teamName: String, series: MotorsportSeries) {
        _viewModel = State(initialValue: TeamDetailViewModel(teamName: teamName, series: series))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MotorsportNames.teamName(raw: viewModel.teamName, series: viewModel.series))
                        .font(.title2.weight(.semibold))
                    Text("\(viewModel.series.shortName) · \(L10n.t(zh: "车队 / 厂商", en: "Team / Manufacturer"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            newsSection
        }
        .dsDetailList()
        .navigationTitle(MotorsportNames.teamName(raw: viewModel.teamName, series: viewModel.series))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
        .refreshable { await viewModel.load() }
        .sheet(item: $sheet) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var newsSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            Section(L10n.t(zh: "新闻", en: "News")) {
                HStack {
                    ProgressView()
                    Text(L10n.t(zh: "聚合中…", en: "Aggregating…")).foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Section(L10n.t(zh: "新闻", en: "News")) {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        case .loaded(let items):
            if items.isEmpty {
                Section(L10n.t(zh: "新闻", en: "News")) {
                    Text(L10n.t(zh: "暂无相关新闻", en: "No related news"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("\(L10n.t(zh: "新闻", en: "News")) (\(items.count))") {
                    ForEach(items) { item in
                        Button { sheet = IdentifiableURL(url: item.url) } label: {
                            NewsRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(item.sourceName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: .capsule)
                    .foregroundStyle(.secondary)
                if let date = item.publishedAt {
                    Text(date, format: .dateTime.month().day().hour().minute().beijing())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}
