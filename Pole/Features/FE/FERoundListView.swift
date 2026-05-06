import SwiftUI

@MainActor
@Observable
final class FERoundListViewModel {
    enum State {
        case idle
        case loading
        case loaded(rounds: [FERound])
        case failed(message: String)
    }

    private(set) var state: State = .idle

    func load() async {
        state = .loading
        do {
            let rounds = try await FormulaEClient.shared.fetchSeasonRounds()
            state = .loaded(rounds: rounds)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

/// FE 赛历列表 —— 当前没有单场 detail/results,仅展示。
struct FERoundListView: View {
    @State private var viewModel = FERoundListViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t(zh: "Formula E 赛程", en: "Formula E Schedule"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .tint(MotorsportSeries.fe.brandColor)
                .navigationDestination(for: FERound.self) { FERoundDetailView(round: $0) }
                .navigationDestination(for: FESessionRef.self) { FESessionResultsView(ref: $0) }
                .task {
                    if case .idle = viewModel.state { await viewModel.load() }
                }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let rounds):
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(rounds) { round in
                        NavigationLink(value: round) {
                            MotorsportCard(series: .fe, isLive: round.currentStatus == .live) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("FE")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(MotorsportSeries.fe.brandColor)
                                        Text("·").foregroundStyle(.tertiary)
                                        Text(round.raceDate, format: .dateTime.month(.abbreviated).day().beijing())
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }
}
