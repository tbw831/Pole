import SwiftUI
import PoleDomain
import PoleDesignSystem
import PoleMotorsportKit

@MainActor
@Observable
final class WSBKRoundListViewModel {
    enum State {
        case idle
        case loading
        case loaded(rounds: [WSBKRound])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        do {
            let rounds = try await WSBKClient.shared.fetchSeasonRounds()
            // live 排第一,其余按 weekendStart 升序
            let sorted = rounds.sorted { a, b in
                let aLive = a.currentStatus == .live
                let bLive = b.currentStatus == .live
                if aLive != bLive { return aLive }
                return a.weekendStart < b.weekendStart
            }
            state = .loaded(rounds: sorted)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

struct WSBKRoundListView: View {
    @State private var viewModel = WSBKRoundListViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t(zh: "WSBK 赛程", en: "WorldSBK Schedule"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    if case .idle = viewModel.state {
                        await viewModel.load()
                    }
                }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let rounds):
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(rounds) { round in
                        NavigationLink(value: round) {
                            RoundRow(round: round)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationDestination(for: WSBKRound.self) { round in
                WSBKRoundDetailView(round: round)
            }
            .navigationDestination(for: WSSPSessionWithResults.self) { item in
                WSSPSessionResultsView(item: item)
            }

        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}

private struct RoundRow: View {
    let round: WSBKRound

    var body: some View {
        MotorsportCard(series: .wssp, isLive: round.currentStatus == .live) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(MotorsportSeries.wssp.shortName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MotorsportSeries.wssp.brandColor)
                    Text("·").foregroundStyle(.tertiary)
                    Text(weekendDateRange)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(round.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(round.subheadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } trailing: {
            StatusBadge(status: round.currentStatus)
        }
    }

    private var weekendDateRange: String {
        let s = round.weekendStart.formatted(.dateTime.month(.abbreviated).day().beijing())
        let e = round.weekendEnd.formatted(.dateTime.month(.abbreviated).day().beijing())
        return "\(s) – \(e)"
    }
}
